import 'package:flutter/material.dart';

class ShotCollection {
  final String id;
  String name;
  int iconCode;
  int colorValue;
  final bool isBuiltin;
  final DateTime createdAt;
  /// Created by Smart Stacks (AI grouping) — safe to re-cluster / prune.
  bool isAuto;

  ShotCollection({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    this.isBuiltin = false,
    DateTime? createdAt,
    this.isAuto = false,
  }) : createdAt = createdAt ?? DateTime.now();

  // Const map so release builds can tree-shake icons (numeric keys:
  // Icons.x.codePoint is not a constant expression). Values mirror
  // flow_store's builtin + smartLook + new-stack picker icons.
  static const _iconByCode = <int, IconData>{
    0xe0ee: Icons.bolt, // bolt
    0xe6f4: Icons.work_outline,
    0xe155: Icons.chat_bubble_outline,
    0xe299: Icons.flight_takeoff,
    0xe25c: Icons.favorite_outline,
    0xf3e8: Icons.sticky_note_2_outlined,
    0xe50d: Icons.receipt_long,
    0xe0b7: Icons.auto_awesome,
    0xf091: Icons.folder_outlined,
  };

  IconData get icon =>
      _iconByCode[iconCode] ?? Icons.folder_outlined;

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconCode': iconCode,
        'colorValue': colorValue,
        'isBuiltin': isBuiltin,
        'isAuto': isAuto,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ShotCollection.fromJson(Map<String, dynamic> j) => ShotCollection(
        id: j['id'] as String,
        name: j['name'] as String,
        iconCode: j['iconCode'] as int,
        colorValue: j['colorValue'] as int,
        isBuiltin: (j['isBuiltin'] as bool?) ?? false,
        isAuto: (j['isAuto'] as bool?) ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class ShotItem {
  final String id;
  String title;
  String collectionId;
  DateTime createdAt;
  List<String> tags;
  bool isFav;
  bool isArchived;
  bool isTrashed;
  int gradientSeed;
  String kind;
  String note;
  String? imagePath; // real file if imported
  bool aiTagged;
  // On-device identification (OCR): text read from inside the image.
  String ocrText;
  bool ocrDone;

  ShotItem({
    required this.id,
    required this.title,
    required this.collectionId,
    DateTime? createdAt,
    List<String>? tags,
    this.isFav = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.gradientSeed = 0,
    this.kind = 'note',
    this.note = '',
    this.imagePath,
    this.aiTagged = true,
    this.ocrText = '',
    this.ocrDone = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        tags = tags ?? const [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'collectionId': collectionId,
        'createdAt': createdAt.toIso8601String(),
        'tags': tags,
        'isFav': isFav,
        'isArchived': isArchived,
        'isTrashed': isTrashed,
        'gradientSeed': gradientSeed,
        'kind': kind,
        'note': note,
        'imagePath': imagePath,
        'aiTagged': aiTagged,
        'ocrText': ocrText,
        'ocrDone': ocrDone,
      };

  factory ShotItem.fromJson(Map<String, dynamic> j) => ShotItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled',
        collectionId: j['collectionId'] as String? ?? 'recent',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        tags: ((j['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
        isFav: (j['isFav'] as bool?) ?? false,
        isArchived: (j['isArchived'] as bool?) ?? false,
        isTrashed: (j['isTrashed'] as bool?) ?? false,
        gradientSeed: (j['gradientSeed'] as int?) ?? 0,
        kind: j['kind'] as String? ?? 'note',
        note: j['note'] as String? ?? '',
        imagePath: j['imagePath'] as String?,
        aiTagged: (j['aiTagged'] as bool?) ?? false,
        ocrText: j['ocrText'] as String? ?? '',
        ocrDone: (j['ocrDone'] as bool?) ?? false,
      );
}

enum SortMode { newest, oldest, name }
enum FilterMode { all, favorites, ai }
