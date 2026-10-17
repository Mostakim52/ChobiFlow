import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'device_import.dart';
import 'smart_stacks.dart';

const _kShots = 'chobiflow_shots_v1';
const _kCols = 'chobiflow_cols_v1';
const _kSeenOnboarding = 'chobiflow_seen_onboarding_v1';
const _kThemeMode = 'chobiflow_theme_v1';
const _kDensity = 'chobiflow_density_v1';
const _kAutoImport = 'chobiflow_autoimport_v1';
const _kAutoIdentify = 'chobiflow_autoidentify_v1';
const _kAutoSmart = 'chobiflow_autosmart_v1';
const _kSmartRan = 'chobiflow_smartran_v1';
const _kSmartGen = 'chobiflow_smartgen_v1';
const _kSmartGenCurrent = 4;
const _kEmb = 'chobiflow_emb_v1';
const _uuid = Uuid();

class FlowStore extends ChangeNotifier {
  List<ShotItem> shots = [];
  List<ShotCollection> collections = [];
  bool loaded = false;
  ThemeMode themeMode = ThemeMode.system;
  bool comfyGrid = true;
  bool autoImport = true;
  bool autoIdentify = true;

  // On-device identification (OCR) progress.
  bool ocrRunning = false;
  int ocrDoneCount = 0;
  int ocrTotal = 0;
  bool _ocrCancel = false;

  // Smart Stacks (vision-model grouping) progress.
  bool autoSmart = true;
  bool smartEverRan = false;
  bool smartRunning = false;
  String smartPhase = ''; // download | embed | cluster | error
  String smartError = '';
  double smartThreshold = 0.78;
  double? smartModelProgress;
  int smartDone = 0;
  int smartTotal = 0;
  bool _smartCancel = false;
  final Map<String, String> _embCache = {};
  bool _embLoaded = false;

  String search = '';
  FilterMode filter = FilterMode.all;
  SortMode sort = SortMode.newest;

  FlowStore() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == (prefs.getString(_kThemeMode) ?? 'system'),
      orElse: () => ThemeMode.system,
    );
    comfyGrid = prefs.getBool(_kDensity) ?? true;
    autoImport = prefs.getBool(_kAutoImport) ?? true;
    autoIdentify = prefs.getBool(_kAutoIdentify) ?? true;
    autoSmart = prefs.getBool(_kAutoSmart) ?? true;
    smartEverRan = prefs.getBool(_kSmartRan) ?? false;
    // Engine upgrades re-arm the one-time auto analysis so the improved
    // brain actually runs instead of sitting behind a stale flag.
    if ((prefs.getInt(_kSmartGen) ?? 0) < _kSmartGenCurrent) {
      smartEverRan = false;
      await prefs.setBool(_kSmartRan, false);
      await prefs.setInt(_kSmartGen, _kSmartGenCurrent);
      // Any engine generation change also invalidates cached embeddings
      // (gen 4 switched the model's input normalization) — purge them so
      // clusters can never mix embeddings from two different contracts.
      await prefs.remove(_kEmb);
      _embCache.clear();
    }
    final cRaw = prefs.getString(_kCols);
    final sRaw = prefs.getString(_kShots);
    if (cRaw == null || sRaw == null) {
      _seed();
      await persist();
    } else {
      try {
        collections = (jsonDecode(cRaw) as List)
            .map((e) => ShotCollection.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        shots = (jsonDecode(sRaw) as List)
            .map((e) => ShotItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _seed();
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kCols, jsonEncode(collections.map((e) => e.toJson()).toList()));
    await prefs.setString(
        _kShots, jsonEncode(shots.map((e) => e.toJson()).toList()));
    await prefs.setString(_kThemeMode, themeMode.name);
    await prefs.setBool(_kDensity, comfyGrid);
    await prefs.setBool(_kAutoImport, autoImport);
    await prefs.setBool(_kAutoIdentify, autoIdentify);
    await prefs.setBool(_kAutoSmart, autoSmart);
    await prefs.setBool(_kSmartRan, smartEverRan);
  }

  Future<void> setAutoImport(bool v) async {
    autoImport = v;
    notifyListeners();
    await persist();
  }

  Future<void> setAutoIdentify(bool v) async {
    autoIdentify = v;
    notifyListeners();
    await persist();
  }

  Future<void> setAutoSmart(bool v) async {
    autoSmart = v;
    notifyListeners();
    await persist();
  }

  void cancelSmart() {
    _smartCancel = true;
  }

  // ---------------- Smart Stacks (self-invented categories) ----------------

  /// Shots the vision model may (re)organize: EVERY real screenshot
  /// except trashed/archived ones and ones inside the user's own custom
  /// stacks. Builtin stacks are machine-made, so the model is allowed
  /// to fix their mistakes (e.g. the old aspect-ratio heuristic that
  /// dumped 249 shots into Chats).
  List<ShotItem> smartEligible() {
    final protected = collections
        .where((c) => !c.isBuiltin && !c.isAuto)
        .map((c) => c.id)
        .toSet();
    return shots
        .where((s) =>
            s.imagePath != null &&
            !s.isTrashed &&
            !s.isArchived &&
            !protected.contains(s.collectionId))
        .toList();
  }

  Future<void> _loadEmbCache() async {
    if (_embLoaded) return;
    _embLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kEmb);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        // Drop '' failure markers: past failures must retry, not stick.
        if (v is String && v.isNotEmpty) _embCache[k] = v;
      });
    } catch (_) {}
  }

  /// One-time repair: a run that embedded zero vectors must not count as
  /// "ran" (it would block auto-magic forever). Returns true if repaired.
  bool _smartRepaired = false;

  Future<void> repairSmartState() async {
    if (_smartRepaired) return;
    _smartRepaired = true;
    await _loadEmbCache();
    final valid = _embCache.values.where((v) => v.isNotEmpty).length;
    if (smartEverRan && valid == 0) {
      smartEverRan = false;
      await persist();
    }
  }

  Future<void> _saveEmbCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Drop cache for deleted shots so it can't grow forever.
      final ids = shots.map((s) => s.id).toSet();
      _embCache.removeWhere((k, _) => !ids.contains(k));
      await prefs.setString(_kEmb, jsonEncode(_embCache));
    } catch (_) {}
  }

  List<double>? _decodeEmb(String b64) {
    if (b64.isEmpty) return null;
    try {
      final bytes = base64Decode(b64);
      if (bytes.length != 512 * 4) return null;
      final f =
          Float32List.view(bytes.buffer, bytes.offsetInBytes, 512);
      return f.toList();
    } catch (_) {
      return null;
    }
  }

  String _encodeEmb(List<double> v) =>
      base64Encode(Float32List.fromList(v).buffer.asUint8List());

  /// Run the vision model over eligible shots, discover natural groups,
  /// and return proposals (nothing is applied — UI shows a preview).
  /// One-time model download (~43MB FP32) happens inside, with progress.
  Future<List<SmartProposal>> runSmartAnalysis() async {
    if (smartRunning) return [];
    final eligible = smartEligible();
    if (eligible.length < 6) return [];
    smartRunning = true;
    _smartCancel = false;
    smartPhase = 'download';
    smartError = '';
    SmartEngine.lastError = null;
    smartModelProgress = null;
    smartDone = 0;
    smartTotal = eligible.length;
    notifyListeners();

    final engine = SmartEngine();
    dynamic session;
    String inputName = '';
    try {
      // 1. model (cached after first download; FP32 S0 — see SmartEngine
      //    for why INT8 is not offered as a smaller/faster alternative)
      String modelPath;
      try {
        modelPath = await engine.ensureModel(onProgress: (p) {
          smartModelProgress = p;
          notifyListeners();
        });
      } catch (_) {
        smartPhase = 'error';
        smartError = 'model download failed';
        smartRunning = false;
        notifyListeners();
        return [];
      }
      // 2. session
      try {
        session = await engine.openSession(modelPath);
        inputName = (session.inputNames.first as String);
      } catch (_) {
        smartPhase = 'error';
        smartError = 'vision model failed to open';
        smartRunning = false;
        notifyListeners();
        return [];
      }
      // 3. embed
      smartPhase = 'embed';
      notifyListeners();
      await _loadEmbCache();
      final vecs = <List<double>>[];
      final keys = <Set<String>>[];
      final items = <ShotItem>[];
      var i = 0;
      for (final s in eligible) {
        if (_smartCancel) break;
        List<double>? v;
        final cached = _embCache[s.id];
        if (cached != null) {
          v = _decodeEmb(cached);
        }
        if (v == null && cached == null) {
          v = await engine.embedFile(session, inputName, s.imagePath!);
          _embCache[s.id] = v == null ? '' : _encodeEmb(v);
        }
        if (v != null) {
          vecs.add(v);
          keys.add({
            ...s.tags.where((t) => t != 'auto' && t != 'ocr'),
            ...DeviceImport.keywords(s.ocrText, 6),
          });
          items.add(s);
        }
        i++;
        smartDone = i;
        if (i % 10 == 0 || i == eligible.length) {
          notifyListeners();
          await _saveEmbCache();
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
      if (_smartCancel) {
        smartRunning = false;
        smartPhase = '';
        notifyListeners();
        await _saveEmbCache();
        return [];
      }
      // 4. cluster (zero vectors = broken inference, not "no groups")
      if (vecs.isEmpty && !_smartCancel) {
        smartPhase = 'error';
        smartError = SmartEngine.lastError ?? 'no embeddings produced';
        smartRunning = false;
        notifyListeners();
        await _saveEmbCache();
        return [];
      }
      // 4. cluster — adaptive strictness: start picky (0.78), loosen
      // to 0.72 then 0.66 until at least 2 natural groups appear.
      // A diverse library yields a few honest stacks instead of nothing
      // (or worse, junk). The used bar is reported in the preview.
      smartPhase = 'cluster';
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 50));
      var groups = <List<int>>[];
      var used = 0.78;
      for (final tau in [0.78, 0.72, 0.66]) {
        if (_smartCancel) break;
        final g = discoverClusters(vecs: vecs, keys: keys, threshold: tau);
        if (g.length > groups.length) {
          groups = g;
          used = tau;
        }
        if (groups.length >= 2) break;
      }
      smartThreshold = used;
      groups = refineLargeGroups(
        groups: groups,
        vecs: vecs,
        keys: keys,
        baseThreshold: used,
      );
      final proposals = <SmartProposal>[];
      for (var gi = 0; gi < groups.length; gi++) {
        final g = groups[gi];
        final members = [for (final idx in g) items[idx]];
        final named = nameCluster(
          titles: [for (final m in members) m.title],
          keys: [for (final m in members) keys[items.indexOf(m)]],
          fallback: 'Smart Stack ${gi + 1}',
        );
        var coh = 0.0;
        var pairs = 0;
        for (var a = 0; a < g.length; a++) {
          for (var b = a + 1; b < g.length; b++) {
            coh += cosine(vecs[g[a]], vecs[g[b]]);
            pairs++;
          }
        }
        proposals.add(SmartProposal(
          name: named.name,
          altName: named.alt,
          kind: named.kind,
          memberIds: [for (final m in members) m.id],
          cohesion: pairs == 0 ? 1 : coh / pairs,
        ));
      }
      smartEverRan = true;
      smartRunning = false;
      smartPhase = '';
      notifyListeners();
      await _saveEmbCache();
      await persist();
      return proposals;
    } finally {
      try {
        await (session as dynamic)?.close();
      } catch (_) {}
      if (smartRunning) {
        smartRunning = false;
        smartPhase = '';
        notifyListeners();
      }
    }
  }

  (IconData, Color) smartLook(String kind) {
    switch (kind) {
      case 'travel':
        return (Icons.flight_takeoff, const Color(0xFFE68A00));
      case 'work':
        return (Icons.work_outline, const Color(0xFF0E9F8A));
      case 'receipt':
        return (Icons.receipt_long, const Color(0xFFEC4899));
      case 'chat':
        return (Icons.chat_bubble_outline, const Color(0xFF3B82F6));
      default:
        return (Icons.auto_awesome, const Color(0xFF5B2EEE));
    }
  }

  /// Apply approved proposals: create AI stacks, move still-eligible
  /// members, prune emptied AI stacks. Returns shots moved.
  Future<int> applySmartProposals(List<SmartProposal> proposals) async {
    final byId = {for (final s in shots) s.id: s};
    final takenNames =
        collections.map((c) => c.name.toLowerCase()).toSet();
    var moved = 0;
    for (final p in proposals) {
      // Unique names with meaning first: try the longer 3-word variant
      // before falling back to a numeric suffix ("Reply 2" tells nobody
      // anything; "Chat • Reply • Birthday" does).
      var name = p.name;
      if (takenNames.contains(name.toLowerCase()) &&
          p.altName.isNotEmpty &&
          !takenNames.contains(p.altName.toLowerCase())) {
        name = p.altName;
      }
      var k = 2;
      while (takenNames.contains(name.toLowerCase())) {
        name = '${p.name} $k';
        k++;
      }
      takenNames.add(name.toLowerCase());
      final look = smartLook(p.kind);
      final col = ShotCollection(
        id: _uuid.v4(),
        name: name,
        iconCode: (look.$1).codePoint,
        colorValue: (look.$2).toARGB32(),
        isAuto: true,
      );
      collections.add(col);
      for (final mid in p.memberIds) {
        final s = byId[mid];
        if (s == null || s.isTrashed) continue;
        s.collectionId = col.id;
        moved++;
      }
    }
    // Prune AI stacks left empty (e.g. after a re-run reshuffles).
    collections.removeWhere((c) =>
        c.isAuto &&
        !shots.any((s) => s.collectionId == c.id && !s.isTrashed));
    notifyListeners();
    await persist();
    return moved;
  }

  /// Shots with a real file that haven't been identified yet.
  int computePendingOcr() {
    var n = 0;
    for (final s in shots) {
      if (s.imagePath != null && !s.ocrDone && !s.isTrashed) n++;
    }
    return n;
  }

  int get identifiedCount =>
      shots.where((s) => s.ocrDone && s.ocrText.isNotEmpty).length;

  void cancelOcr() {
    _ocrCancel = true;
  }

  /// Identify every pending image ON-DEVICE (ML Kit text recognition):
  /// reads the text inside each screenshot, merges content keywords into
  /// tags, and moves still-unsorted ('recent') shots to the collection
  /// the content suggests. Resumable (ocrDone persists), cancellable,
  /// throttled UI updates (every 5 files) + breathing room per file.
  /// Returns newly identified count. Stops early after 5 straight
  /// failures (usually: text model still downloading → needs internet
  /// once) so a broken environment can't spin forever.
  Future<int> runOcrBatch() async {
    if (ocrRunning) return 0;
    final queue = shots
        .where((s) =>
            s.imagePath != null && !s.ocrDone && !s.isTrashed)
        .toList();
    if (queue.isEmpty) return 0;
    ocrRunning = true;
    _ocrCancel = false;
    ocrTotal = queue.length;
    ocrDoneCount = 0;
    notifyListeners();
    TextRecognizer? rec;
    try {
      rec = TextRecognizer(script: TextRecognitionScript.latin);
    } catch (_) {
      rec = null;
    }
    if (rec == null) {
      ocrRunning = false;
      notifyListeners();
      return 0;
    }
    final recognizer = rec;
    var failStreak = 0;
    var processed = 0;
    try {
      for (final s in queue) {
        if (_ocrCancel) break;
        try {
          final f = File(s.imagePath!);
          if (!await f.exists()) {
            s.ocrDone = true;
            s.ocrText = '';
          } else {
            final res = await recognizer
                .processImage(InputImage.fromFilePath(s.imagePath!));
            final t = res.text.trim();
            s.ocrText = t.length > 2000 ? t.substring(0, 2000) : t;
            s.ocrDone = true;
            _enrichFromOcr(s);
            failStreak = 0;
          }
        } catch (_) {
          failStreak++;
          if (failStreak >= 5) break;
        }
        processed++;
        ocrDoneCount = processed;
        if (processed % 5 == 0 || processed == queue.length) {
          notifyListeners();
          await persist();
        }
        // Let the UI thread breathe between images.
        await Future.delayed(const Duration(milliseconds: 30));
      }
    } finally {
      try {
        await recognizer.close();
      } catch (_) {}
      ocrRunning = false;
      notifyListeners();
      await persist();
    }
    return processed;
  }

  /// Fold OCR text into tags + collection. Never touches shots the user
  /// already sorted out of 'recent' — auto-guess only refines the
  /// unsorted pile.
  void _enrichFromOcr(ShotItem s) {
    if (s.ocrText.isEmpty) return;
    final contentWords = DeviceImport.keywords(s.ocrText, 5);
    final merged = <String>{...s.tags, ...contentWords, 'ocr'};
    s.tags = merged.take(8).toList();
    if (s.collectionId == 'recent') {
      final guess = DeviceImport.guessFromText(
          '${s.title} ${s.ocrText}');
      if (guess != 'recent' && _hasCollection(guess)) {
        s.collectionId = guess;
        s.kind = _kindFor(guess);
      }
    }
  }

  /// Import real device screenshots, skipping ones already organized.
  /// ONE notify + ONE persist for the whole batch — the old per-shot
  /// persist (full JSON rewrite × N) froze the UI on big libraries.
  /// Returns how many were added plus a per-collection breakdown so the
  /// UI can show what the organizer actually did.
  Future<({int added, Map<String, int> perCollection})> importDeviceShots(
      List<DeviceShot> found) async {
    // Compare by normalized path: /sdcard/x == /storage/emulated/0/x.
    final known = shots
        .where((s) => s.imagePath != null)
        .map((s) => DeviceImport.norm(s.imagePath!))
        .toSet();
    final batch = <ShotItem>[];
    final per = <String, int>{};
    for (final d in found) {
      final key = DeviceImport.norm(d.path);
      if (!known.add(key)) continue;
      final guess = DeviceImport.guessCollectionId(
          d.title, d.width, d.height);
      final target = _hasCollection(guess) ? guess : 'recent';
      final kind = _kindFor(target);
      batch.add(ShotItem(
        id: _uuid.v4(),
        title: d.title,
        collectionId: target,
        createdAt: d.date,
        tags: _autoTag(d.title,
            'From Screenshots • ${_fmtDate(d.date)}', kind, []),
        gradientSeed: d.date.millisecondsSinceEpoch % 997,
        kind: kind,
        note:
            'From Screenshots • ${_fmtDate(d.date)} • auto-organized on import.',
        imagePath: d.path,
        aiTagged: true,
      ));
      known.add(key);
      per[target] = (per[target] ?? 0) + 1;
    }
    if (batch.isNotEmpty) {
      shots.insertAll(0, batch);
      notifyListeners();
      await persist();
    }
    return (added: batch.length, perCollection: per);
  }

  bool _hasCollection(String id) =>
      collections.any((c) => c.id == id);

  String _kindFor(String colId) {
    switch (colId) {
      case 'travel':
        return 'travel';
      case 'chats':
        return 'chat';
      case 'work':
        return 'work';
      case 'personal':
        return 'receipt';
      default:
        return 'note';
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  // ---------- derived ----------
  List<ShotItem> get visibleShots {
    Iterable<ShotItem> out = shots.where((s) => !s.isTrashed && !s.isArchived);
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      out = out.where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.note.toLowerCase().contains(q) ||
          s.ocrText.toLowerCase().contains(q) ||
          s.tags.any((t) => t.toLowerCase().contains(q)));
    }
    if (filter == FilterMode.favorites) out = out.where((s) => s.isFav);
    if (filter == FilterMode.ai) out = out.where((s) => s.aiTagged);
    final list = out.toList();
    switch (sort) {
      case SortMode.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortMode.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortMode.name:
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
    }
    return list;
  }

  List<ShotItem> shotsIn(String collectionId, {bool includeArchived = false}) {
    final list = shots.where((s) {
      if (s.isTrashed) return false;
      if (!includeArchived && s.isArchived) return false;
      return s.collectionId == collectionId;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<ShotItem> get archived =>
      shots.where((s) => s.isArchived && !s.isTrashed).toList();
  List<ShotItem> get trashed => shots.where((s) => s.isTrashed).toList();
  List<ShotItem> get favorites =>
      shots.where((s) => s.isFav && !s.isTrashed).toList();

  ShotCollection collectionOf(String id) {
    return collections.firstWhere(
      (c) => c.id == id,
      orElse: () => collections.first,
    );
  }

  int get totalCount => shots.where((s) => !s.isTrashed).length;

  // ---------- mutations ----------
  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  void setFilter(FilterMode f) {
    filter = f;
    notifyListeners();
  }

  void setSort(SortMode s) {
    sort = s;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await persist();
  }

  Future<void> setDensity(bool comfy) async {
    comfyGrid = comfy;
    notifyListeners();
    await persist();
  }

  Future<void> toggleFav(ShotItem s) async {
    s.isFav = !s.isFav;
    notifyListeners();
    await persist();
  }

  Future<void> toggleArchive(ShotItem s) async {
    s.isArchived = !s.isArchived;
    if (s.isArchived) s.isTrashed = false;
    notifyListeners();
    await persist();
  }

  Future<void> trash(ShotItem s) async {
    s.isTrashed = true;
    notifyListeners();
    await persist();
  }

  Future<void> restore(ShotItem s) async {
    s.isTrashed = false;
    s.isArchived = false;
    notifyListeners();
    await persist();
  }

  Future<void> deleteForever(ShotItem s) async {
    shots.removeWhere((e) => e.id == s.id);
    notifyListeners();
    await persist();
  }

  Future<void> emptyTrash() async {
    shots.removeWhere((s) => s.isTrashed);
    notifyListeners();
    await persist();
  }

  Future<void> moveShots(List<String> ids, String collectionId) async {
    for (final s in shots) {
      if (ids.contains(s.id)) s.collectionId = collectionId;
    }
    notifyListeners();
    await persist();
  }

  Future<ShotItem> addShot({
    required String title,
    required String collectionId,
    String kind = 'note',
    List<String>? tags,
    String note = '',
    String? imagePath,
    DateTime? createdAt,
  }) async {
    final autoTags = _autoTag(title, note, kind, tags ?? []);
    final now = createdAt ?? DateTime.now();
    final shot = ShotItem(
      id: _uuid.v4(),
      title: title,
      collectionId: collectionId,
      createdAt: now,
      tags: autoTags,
      gradientSeed: now.millisecondsSinceEpoch % 997,
      kind: kind,
      note: note,
      imagePath: imagePath,
      aiTagged: true,
    );
    shots.insert(0, shot);
    notifyListeners();
    await persist();
    return shot;
  }

  Future<ShotCollection> addCollection(String name, IconData icon, Color c) async {
    final col = ShotCollection(
      id: _uuid.v4(),
      name: name,
      iconCode: icon.codePoint,
      colorValue: c.toARGB32(),
    );
    collections.add(col);
    notifyListeners();
    await persist();
    return col;
  }

  Future<void> renameCollection(ShotCollection c, String name) async {
    c.name = name;
    notifyListeners();
    await persist();
  }

  Future<void> deleteCollection(ShotCollection c) async {
    if (c.isBuiltin) return;
    // move its shots to Recent
    for (final s in shots) {
      if (s.collectionId == c.id) s.collectionId = 'recent';
    }
    collections.removeWhere((e) => e.id == c.id);
    notifyListeners();
    await persist();
  }

  List<String> _autoTag(
      String title, String note, String kind, List<String> base) {
    final out = <String>{...base, kind, 'auto'};
    final text = '$title $note'.toLowerCase();
    const keywords = {
      'flight': 'travel',
      'hotel': 'travel',
      'recipe': 'food',
      'meeting': 'work',
      'standup': 'work',
      'invoice': 'work',
      'chat': 'chat',
      'meme': 'fun',
      'code': 'dev',
      'error': 'dev',
      'design': 'design',
      'rent': 'personal',
    };
    keywords.forEach((k, v) {
      if (text.contains(k)) out.add(v);
    });
    return out.take(5).toList();
  }

  // ---------- seed ----------
  void _seed() {
    collections = [
      ShotCollection(
          id: 'recent',
          name: 'Recent',
          iconCode: Icons.bolt.codePoint,
          colorValue: const Color(0xFF5B2EEE).toARGB32(),
          isBuiltin: true),
      ShotCollection(
          id: 'work',
          name: 'Work',
          iconCode: Icons.work_outline.codePoint,
          colorValue: const Color(0xFF0E9F8A).toARGB32(),
          isBuiltin: true),
      ShotCollection(
          id: 'chats',
          name: 'Chats',
          iconCode: Icons.chat_bubble_outline.codePoint,
          colorValue: const Color(0xFF3B82F6).toARGB32(),
          isBuiltin: true),
      ShotCollection(
          id: 'travel',
          name: 'Travel',
          iconCode: Icons.flight_takeoff.codePoint,
          colorValue: const Color(0xFFE68A00).toARGB32(),
          isBuiltin: true),
      ShotCollection(
          id: 'personal',
          name: 'Personal',
          iconCode: Icons.favorite_outline.codePoint,
          colorValue: const Color(0xFFEC4899).toARGB32(),
          isBuiltin: true),
      ShotCollection(
          id: 'notes',
          name: 'Notes',
          iconCode: Icons.sticky_note_2_outlined.codePoint,
          colorValue: const Color(0xFF8B5CF6).toARGB32(),
          isBuiltin: true),
    ];
  }

  static Future<bool> seenOnboarding() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSeenOnboarding) ?? false;
  }

  static Future<void> setSeenOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSeenOnboarding, true);
  }
}
