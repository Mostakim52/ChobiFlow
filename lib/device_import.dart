import 'package:photo_manager/photo_manager.dart';

/// A real screenshot found on the device (Screenshots folder / gallery).
class DeviceShot {
  final String path;
  final String title;
  final DateTime date;
  final int width;
  final int height;
  const DeviceShot({
    required this.path,
    required this.title,
    required this.date,
    this.width = 0,
    this.height = 0,
  });
}

/// Reads the device's Screenshots folder via MediaStore / PhotoKit.
/// All platform calls are wrapped in try/catch so tests and
/// permission-denied states degrade gracefully to demo data.
class DeviceImport {
  /// true if we may read images (authorized or limited).
  static Future<bool> hasAccess() async {
    try {
      final s = await PhotoManager.requestPermissionExtend();
      return s == PermissionState.authorized ||
          s == PermissionState.limited;
    } catch (_) {
      return false;
    }
  }

  /// Ask the OS for photo access. Call once, in context (first Flow build).
  static Future<bool> request() async {
    try {
      final s = await PhotoManager.requestPermissionExtend();
      return s == PermissionState.authorized ||
          s == PermissionState.limited;
    } catch (_) {
      return false;
    }
  }

  /// Scan ALL Screenshots albums (phones often have two, e.g. Samsung
  /// keeps real shots in DCIM/Screenshots while other apps write to
  /// Pictures/Screenshots — stopping after the first album silently
  /// orphaned the second). Falls back to filename filter over recent
  /// images when the OEM names the album differently.
  /// Paths are deduped by normalized form so one file never counts twice.
  static Future<({List<DeviceShot> shots, int albums})> scan(
      {int limit = 300}) async {
    try {
      final ok = await hasAccess();
      if (!ok) return (shots: const <DeviceShot>[], albums: 0);
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false)
          ],
        ),
      );
      final wanted = <AssetPathEntity>[];
      for (final a in albums) {
        final n = a.name.toLowerCase();
        if (n.contains('screenshot')) wanted.add(a);
      }
      final sources = wanted.isNotEmpty ? wanted : albums;
      final out = <DeviceShot>[];
      final seen = <String>{};
      final touched = <String>{};
      for (final album in sources) {
        final isShotAlbum = wanted.isNotEmpty;
        final assets = await album.getAssetListRange(start: 0, end: limit);
        if (assets.isNotEmpty) touched.add(album.name);
        for (final asset in assets) {
          final rawName = await asset.titleAsync;
          final name =
              rawName.trim().isEmpty ? 'Screenshot' : rawName;
          if (!isShotAlbum &&
              !name.toLowerCase().contains('screenshot') &&
              !name.toLowerCase().contains('screen shot')) {
            continue;
          }
          final file = await asset.file;
          if (file == null) continue;
          final key = norm(file.path);
          if (!seen.add(key)) continue;
          final title = _prettyTitle(name);
          out.add(DeviceShot(
            path: file.path,
            title: title,
            date: asset.createDateTime,
            width: asset.width,
            height: asset.height,
          ));
          if (out.length >= limit) {
            return (shots: out, albums: touched.length);
          }
        }
      }
      return (shots: out, albums: touched.length);
    } catch (_) {
      return (shots: const <DeviceShot>[], albums: 0);
    }
  }

  /// `/sdcard/x` and `/storage/emulated/0/x` are the same file —
  /// normalize before comparing so dedupe can't miss (or double-add).
  static String norm(String p) {
    const equiv = ['/storage/emulated/0', '/sdcard'];
    for (final pre in equiv) {
      if (p.startsWith(pre)) return p.substring(pre.length);
    }
    return p;
  }

  // ---------- content identification (no filenames needed) ----------

  /// Shared stopwords: generic UI/photo words that must never become
  /// tags or stack names (they'd drown out real content everywhere).
  static const stopwords = {
    'this', 'that', 'with', 'from', 'have', 'more', 'will', 'about',
    'into', 'over', 'after', 'before', 'when', 'what', 'where', 'which',
    'their', 'there', 'been', 'were', 'said', 'each', 'other', 'than',
    'then', 'them', 'they', 'also', 'just', 'like', 'your', 'ours',
    'today', 'hello', 'thanks', 'please', 'sent', 'show', 'open',
    'search', 'home', 'back', 'done', 'cancel', 'save', 'next',
    'message', 'screen', 'screens', 'screenshot', 'screenshots',
    'shot', 'shots', 'image', 'images', 'photo', 'photos', 'img',
  };

  /// Top content words by frequency — pure function, unit-tested.
  static List<String> keywords(String text, [int max = 8]) {
    final freq = <String, int>{};
    for (final w in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (w.length < 4 || stopwords.contains(w)) continue;
      freq[w] = (freq[w] ?? 0) + 1;
    }
    final keys = freq.keys.toList()
      ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
    return keys.take(max).toList();
  }

  /// Collection guess from INSIDE-text (OCR) + title — pure, unit-tested.
  /// Works on any phone regardless of filename scheme.
  static String guessFromText(String text) {
    final t = text.toLowerCase();
    if (t.contains('boarding') ||
        t.contains('flight') ||
        t.contains('hotel') ||
        t.contains('check-in') ||
        t.contains('checkout') ||
        t.contains('check out') ||
        t.contains('itinerary') ||
        t.contains('booking') ||
        t.contains('reservation') ||
        t.contains('departure') ||
        t.contains('arrival')) {
      return 'travel';
    }
    if (t.contains('invoice') ||
        t.contains('meeting') ||
        t.contains('standup') ||
        t.contains('stand up') ||
        t.contains('pull request') ||
        t.contains('stack trace') ||
        t.contains('exception') ||
        t.contains('error') ||
        t.contains('salary') ||
        t.contains('offer letter') ||
        t.contains('deadline') ||
        t.contains('sprint')) {
      return 'work';
    }
    if (t.contains('receipt') ||
        t.contains('receipts') ||
        t.contains('billed') ||
        t.contains('billing') ||
        t.contains('paid') ||
        t.contains('payment') ||
        t.contains('order id') ||
        t.contains('order number') ||
        t.contains('delivered') ||
        t.contains('transaction') ||
        t.contains('balance') ||
        t.contains('otp') ||
        t.contains('verification code') ||
        t.contains('recipe') ||
        t.contains('ingredients')) {
      return 'personal';
    }
    return 'recent';
  }

  static String _prettyTitle(String filename) {
    var t = filename.replaceAll(RegExp(r'\.(png|jpg|jpeg|webp)$',
        caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'[_\-]+'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return 'Screenshot';
    if (t.toLowerCase() == 'screenshot') return 'Screenshot';
    return t[0].toUpperCase() + t.substring(1);
  }

  /// First-pass guess from the filename only. Deliberately conservative:
  /// anything without explicit keywords stays in 'recent' for the vision
  /// model + OCR to sort properly. (An old tall-portrait→chats heuristic
  /// once dumped 249 screenshots into Chats — never again.)
  static String guessCollectionId(String title, int width, int height) {
    final t = title.toLowerCase();
    if (t.contains('flight') ||
        t.contains('hotel') ||
        t.contains('boarding') ||
        t.contains('trip') ||
        t.contains('itinerary')) {
      return 'travel';
    }
    // Messaging apps are unambiguous even from the filename.
    if (t.contains('whatsapp') ||
        t.contains('telegram') ||
        t.contains('discord') ||
        t.contains('messenger') ||
        t.contains('signal')) {
      return 'chats';
    }
    if (t.contains('invoice') ||
        t.contains('meeting') ||
        t.contains('standup') ||
        t.contains('salary') ||
        t.contains('offer letter')) {
      return 'work';
    }
    if (t.contains('receipt') ||
        t.contains('rent') ||
        t.contains('invoice') ||
        t.contains('bill')) {
      return 'personal';
    }
    return 'recent';
  }
}
