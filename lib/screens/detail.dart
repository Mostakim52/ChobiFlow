import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../chobi_theme.dart';
import '../flow_store.dart';
import '../models.dart';
import '../widgets/flow_widgets.dart';

class ShotDetail extends StatelessWidget {
  final FlowStore store;
  final ShotItem shot;
  const ShotDetail({super.key, required this.store, required this.shot});

  @override
  Widget build(BuildContext context) {
    final col = store.collectionOf(shot.collectionId);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            leading: _roundBtn(context, Icons.arrow_back, () => Navigator.pop(context)),
            actions: [
              _roundBtn(context, shot.isFav ? Icons.favorite : Icons.favorite_border, () {
                store.toggleFav(shot);
                HapticFeedback.lightImpact();
              }, filled: shot.isFav),
              _roundBtn(context, Icons.ios_share, () {
                SharePlus.instance.share(ShareParams(
                    text: '${shot.title} — via ChobiFlow\n${shot.note}'));
              }),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'shot-${shot.id}',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 90, 16, 12),
                  child: ShotThumb(shot: shot, borderRadius: 28),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: col.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: col.color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(col.icon, size: 14, color: col.color),
                        const SizedBox(width: 6),
                        Text(col.name,
                            style: TextStyle(
                                color: col.color, fontWeight: FontWeight.w800, fontSize: 12)),
                        const SizedBox(width: 6),
                        const Text('•', style: TextStyle(color: Colors.grey)),
                        const SizedBox(width: 6),
                        Text(DateFormat('MMM d, h:mm a').format(shot.createdAt),
                            style: TextStyle(
                                color: dark ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(shot.title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900, height: 1.05)),
                  if (shot.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(shot.note,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.5,
                            color: dark ? const Color(0xFFB9B2D3) : const Color(0xFF5A5478))),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in shot.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: t == 'auto'
                                ? const Color(0xFFFFB020).withValues(alpha: 0.18)
                                : dark
                                    ? Colors.white10
                                    : const Color(0xFFF1EBDD),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                                color: t == 'auto'
                                    ? const Color(0xFFFFB020).withValues(alpha: 0.5)
                                    : dark
                                        ? Colors.white12
                                        : const Color(0xFFE2D8C2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (t == 'auto')
                                const Icon(Icons.auto_awesome,
                                    size: 13, color: Color(0xFFE68A00)),
                              if (t == 'auto') const SizedBox(width: 4),
                              Text('#$t',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const FlowRibbon(height: 36, opacity: 0.9),
                  const SizedBox(height: 18),
                  _ActionGrid(store: store, shot: shot),
                  const SizedBox(height: 18),
                  _OcrCard(shot: shot),
                  _MoveRow(store: store, shot: shot),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(BuildContext context, IconData icon, VoidCallback onTap,
      {bool filled = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: filled
                ? const Color(0xFFFFB020)
                : dark
                    ? Colors.black54
                    : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)
            ],
          ),
          child: Icon(icon,
              size: 19,
              color: filled
                  ? const Color(0xFF131022)
                  : dark
                      ? Colors.white
                      : const Color(0xFF131022)),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final FlowStore store;
  final ShotItem shot;
  const _ActionGrid({required this.store, required this.shot});
  @override
  Widget build(BuildContext context) {
    final items = [
      (shot.isFav ? Icons.favorite : Icons.favorite_border,
          shot.isFav ? 'Faved' : 'Favorite', () => store.toggleFav(shot)),
      (Icons.ios_share, 'Share', () {
        SharePlus.instance
            .share(ShareParams(text: '${shot.title} — via ChobiFlow'));
      }),
    ];
    return Row(
      children: [
        for (final (icon, label, fn) in items)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  right: label == 'Favorite' || label == 'Faved' ? 10 : 0),
              child: Pressable(
                onTap: fn,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF21183D)
                            : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color:
                            Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF3A2E63)
                                : const Color(0xFFEEE6D6)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 8),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OcrCard extends StatelessWidget {
  final ShotItem shot;
  const _OcrCard({required this.shot});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (shot.imagePath == null) return const SizedBox.shrink();
    final has = shot.ocrDone && shot.ocrText.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF21183D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: dark
                ? const Color(0xFF3A2E63)
                : const Color(0xFFEEE6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.document_scanner_outlined,
                  size: 16, color: Color(0xFF0E9F8A)),
              SizedBox(width: 6),
              Text('Text inside this shot',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          if (has)
            SelectableText(
              shot.ocrText.length > 600
                  ? '${shot.ocrText.substring(0, 600)}…'
                  : shot.ocrText,
              style: TextStyle(
                  height: 1.5,
                  color: dark
                      ? const Color(0xFFB9B2D3)
                      : const Color(0xFF5A5478)),
            )
          else
            Text(
              shot.ocrDone
                  ? 'No readable text found — mostly visual.'
                  : 'Not identified yet — tap Identify on the home banner.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  final FlowStore store;
  final ShotItem shot;
  const _MoveRow({required this.store, required this.shot});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Move to collection',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: store.collections.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (c, i) {
              final col = store.collections[i];
              final active = col.id == shot.collectionId;
              return Pressable(
                onTap: () {
                  store.moveShots([shot.id], col.id);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 76,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: active
                        ? col.color
                        : Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF21183D)
                            : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: col.color.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(col.icon,
                          color: active ? Colors.white : col.color,
                          size: 22),
                      const SizedBox(height: 6),
                      Text(col.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: active
                                  ? Colors.white
                                  : Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
