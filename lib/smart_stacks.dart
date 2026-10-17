import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'device_import.dart';

/// Smart Stacks engine: on-device vision (MobileCLIP2-S0) + unsupervised
/// clustering. The model looks at what screenshots LOOK like, groups the
/// look-alikes, and names each group from the words inside — no fixed
/// categories, no filenames, no server.
///
/// Model: felixhrdyn/mobileclip2-s0-onnx, vision encoder only, FP32
/// (43MB) — INT8 dynamic quantization breaks this backbone (see
/// ensureModel). Downloaded on demand.

// ---------------------------------------------------------------- pure math

double cosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

double jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var inter = 0;
  for (final w in a) {
    if (b.contains(w)) inter++;
  }
  return inter / (a.length + b.length - inter);
}

/// Agglomerative single-linkage discovery: grows each seed with anything
/// similar enough to ANY member. Returns index groups of size >= minSize.
/// Fused signal: 0.8 visual cosine + 0.2 keyword overlap.
List<List<int>> discoverClusters({
  required List<List<double>> vecs,
  required List<Set<String>> keys,
  double threshold = 0.78,
  int minSize = 3,
}) {
  double sim(int i, int j) {
    final v = cosine(vecs[i], vecs[j]) + 0.2 * jaccard(keys[i], keys[j]);
    return v > 1 ? 1 : v;
  }

  final n = vecs.length;
  final assigned = List<bool>.filled(n, false);
  final groups = <List<int>>[];
  for (var s = 0; s < n; s++) {
    if (assigned[s]) continue;
    final group = <int>[s];
    assigned[s] = true;
    var grew = true;
    while (grew) {
      grew = false;
      for (var i = 0; i < n; i++) {
        if (assigned[i]) continue;
        var best = 0.0;
        for (final m in group) {
          final v = sim(i, m);
          if (v > best) best = v;
        }
        if (best >= threshold) {
          group.add(i);
          assigned[i] = true;
          grew = true;
        }
      }
    }
    if (group.length >= minSize) groups.add(group);
  }
  // Biggest, most coherent first.
  double cohesion(List<int> g) {
    if (g.length < 2) return 1;
    var sum = 0.0, c = 0;
    for (var a = 0; a < g.length; a++) {
      for (var b = a + 1; b < g.length; b++) {
        sum += sim(g[a], g[b]);
        c++;
      }
    }
    return c == 0 ? 1 : sum / c;
  }

  groups.sort((a, b) {
    final sizeCmp = b.length.compareTo(a.length);
    if (sizeCmp != 0) return sizeCmp;
    return cohesion(b).compareTo(cohesion(a));
  });
  return groups;
}

/// Break chaining mega-clusters: any group bigger than maxSize gets
/// re-clustered once at a stricter bar, so "120 vaguely similar shots"
/// becomes real topics. Pure function, unit-tested.
List<List<int>> refineLargeGroups({
  required List<List<int>> groups,
  required List<List<double>> vecs,
  required List<Set<String>> keys,
  required double baseThreshold,
  int maxSize = 60,
  int minSize = 3,
}) {
  final out = <List<int>>[];
  for (final g in groups) {
    if (g.length <= maxSize) {
      out.add(g);
      continue;
    }
    final subVecs = [for (final i in g) vecs[i]];
    final subKeys = [for (final i in g) keys[i]];
    final sub = discoverClusters(
      vecs: subVecs,
      keys: subKeys,
      threshold: (baseThreshold + 0.08).clamp(0.0, 0.97),
      minSize: minSize,
    );
    if (sub.isEmpty) {
      out.add(g);
    } else {
      for (final s in sub) {
        out.add([for (final j in s) g[j]]);
      }
      // Members that fell out of every sub-group keep a home.
      final kept = sub.expand((s) => s).map((j) => g[j]).toSet();
      final rest = g.where((i) => !kept.contains(i)).toList();
      if (rest.length >= minSize) out.add(rest);
    }
  }
  out.sort((a, b) => b.length.compareTo(a.length));
  return out;
}

String _titleCase(String w) =>
    w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);

/// Name a discovered group from the words inside its members.
/// Returns display name + a longer tiebreak variant + kind hint.
({String name, String alt, String kind}) nameCluster({
  required List<String> titles,
  required List<Set<String>> keys,
  required String fallback,
}) {
  final freq = <String, int>{};
  for (final set in keys) {
    for (final w in set) {
      if (DeviceImport.stopwords.contains(w)) continue;
      freq[w] = (freq[w] ?? 0) + 1;
    }
  }
  for (final t in titles) {
    for (final w in t.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (w.length < 5 || DeviceImport.stopwords.contains(w)) continue;
      freq[w] = (freq[w] ?? 0) + 1;
    }
  }
  final words = freq.keys.toList()
    ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
  final top = words.take(2).toList();
  if (top.isEmpty) return (name: fallback, alt: '', kind: 'note');
  final name = top.map(_titleCase).join(' • ');
  final alt = words.take(3).toList().map(_titleCase).join(' • ');
  final joined = words.take(6).join(' ');
  String kind = 'note';
  if (RegExp(r'flight|hotel|boarding|trip|travel|map|booking')
      .hasMatch(joined)) {
    kind = 'travel';
  } else if (RegExp(r'chat|message|meme|instagram|tiktok|discord|whatsapp')
      .hasMatch(joined)) {
    kind = 'chat';
  } else if (RegExp(
          r'work|meeting|invoice|error|code|build|standup|receipt|bill|bank|otp|payment|order')
      .hasMatch(joined)) {
    // receipts/bills vs work both land here; split by money words.
    kind = RegExp(r'receipt|bill|bank|otp|payment|order|recipe')
            .hasMatch(joined)
        ? 'receipt'
        : 'work';
  }
  return (name: name, alt: alt, kind: kind);
}

// ------------------------------------------------------------ vision model

class SmartProposal {
  final String name;
  final String altName;
  final String kind;
  final List<String> memberIds;
  final double cohesion;
  const SmartProposal({
    required this.name,
    this.altName = '',
    required this.kind,
    required this.memberIds,
    required this.cohesion,
  });
  int get size => memberIds.length;
}

class SmartEngine {
  static const _f32url =
      'https://huggingface.co/felixhrdyn/mobileclip2-s0-onnx/resolve/main/vision_model.onnx';
  static const _f32name = 'smart_vision_f32.onnx';
  static const _legacyQ8 = 'smart_vision_q8.onnx';

  /// Download progress 0..1 (null when size unknown). Throws on failure.
  /// FP32 vision only: MobileCLIP2's FastViT backbone degrades badly under
  /// dynamic INT8 quantization (measured 12x slower AND near-random
  /// embeddings on CPU), so the 11MB "small" file is a trap, not a fallback.
  Future<String> ensureModel({void Function(double?)? onProgress}) async {
    final dir = await getApplicationDocumentsDirectory();
    final f32 = File('${dir.path}/$_f32name');
    if (await f32.exists() && await f32.length() > 1000000) {
      return f32.path;
    }
    await _download(_f32url, f32, onProgress);
    // Free the legacy INT8 file if an older build left it behind.
    final old = File('${dir.path}/$_legacyQ8');
    if (await old.exists()) {
      try {
        await old.delete();
      } catch (_) {}
    }
    return f32.path;
  }

  Future<void> _download(
      String url, File dest, void Function(double?)? onProgress) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('model download HTTP ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : null;
      final sink = dest.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null) onProgress?.call(got / total);
      }
      await sink.close();
      if (await dest.length() < 1000000) {
        throw HttpException('model download truncated');
      }
    } finally {
      client.close();
    }
  }

  Future<OrtSession> openSession(String modelPath) async {
    final ort = OnnxRuntime();
    return ort.createSession(modelPath);
  }

  /// Last inference failure reason (for honest error UI). Null when clean.
  static String? lastError;

  /// 512-d L2-normalized visual embedding, or null when undecodable.
  /// Input contract (MobileCLIP2-S0 ONNX, measured not assumed): 256x256
  /// RGB, shortest-edge bicubic resize + center crop, /255 with NO mean/std
  /// normalization (the OpenAI-CLIP stats this model family is often
  /// shipped with measurably hurt it: purity 0.94/coverage 0.69 vs
  /// 1.00/1.00 on labeled probes), NCHW float32.
  Future<List<double>?> embedFile(
      OrtSession session, String inputName, String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final src = img.decodeImage(bytes);
      if (src == null) return null;
      final side = math.min(src.width, src.height);
      final scale = 256.0 / side;
      final resized = img.copyResize(src,
          interpolation: img.Interpolation.cubic,
          width: (src.width * scale).round(),
          height: (src.height * scale).round());
      final cx = (resized.width - 256) ~/ 2;
      final cy = (resized.height - 256) ~/ 2;
      final crop = img.copyCrop(resized,
          x: cx.clamp(0, resized.width - 256),
          y: cy.clamp(0, resized.height - 256),
          width: 256,
          height: 256);
      final data = Float32List(1 * 3 * 256 * 256);
      var o = 0;
      for (var c = 0; c < 3; c++) {
        for (var y = 0; y < 256; y++) {
          for (var x = 0; x < 256; x++) {
            final p = crop.getPixel(x, y);
            final v = c == 0
                ? p.r.toDouble()
                : (c == 1 ? p.g.toDouble() : p.b.toDouble());
            data[o++] = v / 255.0;
          }
        }
      }
      // NOTE: pass the Float32List itself, NOT .toList(). A 196608-float
      // List<double> exceeds the platform-channel binder limit and fails
      // every inference; typed data travels compact (~786KB).
      final input =
          await OrtValue.fromList(data, [1, 3, 256, 256]);
      Map<String, OrtValue>? outputs;
      try {
        outputs = await session.run({inputName: input});
        // [1,512] output: use the FLATTENED list. asList() keeps the
        // batch dimension ([[..512..]]) and casting that to num throws.
        final raw =
            await outputs.values.first.asFlattenedList();
        final vec = raw.map((e) => (e as num).toDouble()).toList();
        if (vec.length != 512) {
          lastError = 'unexpected embedding dim ${vec.length}';
          return null;
        }
        var norm = 0.0;
        for (final v in vec) {
          norm += v * v;
        }
        norm = math.sqrt(norm);
        if (norm == 0) return null;
        lastError = null;
        return vec.map((v) => v / norm).toList();
      } finally {
        try {
          await input.dispose();
        } catch (_) {}
        if (outputs != null) {
          for (final o in outputs.values) {
            try {
              await o.dispose();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      lastError = e.toString().split('\n').first.take(140);
      return null;
    }
  }
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
