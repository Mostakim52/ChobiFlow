import 'dart:io';
import 'dart:math' as math;
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../chobi_theme.dart';
import '../models.dart';

/// Gradient thumbnail that looks like a mini screenshot mock.
/// Deterministic from [seed] + [kind] so demo data looks rich with zero assets.
class ShotThumb extends StatelessWidget {
  final ShotItem shot;
  final double borderRadius;
  const ShotThumb({super.key, required this.shot, this.borderRadius = 20});

  List<Color> _palette() {
    const sets = [
      [Color(0xFF5B2EEE), Color(0xFF9D7BFF)],
      [Color(0xFF0E9F8A), Color(0xFF5EEAD4)],
      [Color(0xFFE68A00), Color(0xFFFFD166)],
      [Color(0xFFEC4899), Color(0xFFF9A8D4)],
      [Color(0xFF3B82F6), Color(0xFF93C5FD)],
      [Color(0xFF8B5CF6), Color(0xFFC4B5FD)],
    ];
    return sets[shot.gradientSeed % sets.length];
  }

  @override
  Widget build(BuildContext context) {
    final pal = _palette();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: pal,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // paper sheet mock
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.black.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: LayoutBuilder(builder: (c, box) {
                    // The decorative paper mock needs ~106px. In short
                    // slots (92x104 fan cards in the Stacks grid) it
                    // overflows the bottom — render compact instead.
                    if (box.maxHeight < 118) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                  width: 18,
                                  height: 6,
                                  decoration: BoxDecoration(
                                      color: pal.first,
                                      borderRadius:
                                          BorderRadius.circular(99))),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                        color: dark
                                            ? Colors.white24
                                            : const Color(0xFFE7E2F5),
                                        borderRadius:
                                            BorderRadius.circular(99))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Expanded(
                            child: Container(
                                decoration: BoxDecoration(
                                    color:
                                        pal.first.withValues(alpha: 0.18),
                                    borderRadius:
                                        BorderRadius.circular(8))),
                          ),
                          const SizedBox(height: 7),
                          Icon(_kindIcon(shot.kind),
                              size: 12, color: pal.first),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                                width: 26,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: pal.first,
                                    borderRadius:
                                        BorderRadius.circular(99))),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: dark
                                          ? Colors.white24
                                          : const Color(0xFFE7E2F5),
                                      borderRadius:
                                          BorderRadius.circular(99))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                            height: 46,
                            decoration: BoxDecoration(
                                color: pal.first.withValues(alpha: 0.18),
                                borderRadius:
                                    BorderRadius.circular(10))),
                        const SizedBox(height: 8),
                        Container(
                            height: 8,
                            width: double.infinity,
                            decoration: BoxDecoration(
                                color: dark
                                    ? Colors.white24
                                    : const Color(0xFFE7E2F5),
                                borderRadius:
                                    BorderRadius.circular(99))),
                        const SizedBox(height: 6),
                        FractionallySizedBox(
                            widthFactor: 0.7,
                            alignment: Alignment.centerLeft,
                            child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                    color: dark
                                        ? Colors.white24
                                        : const Color(0xFFE7E2F5),
                                    borderRadius: BorderRadius.circular(
                                        99)))),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(_kindIcon(shot.kind),
                                size: 14, color: pal.first),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                shot.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: dark
                                      ? Colors.white
                                      : const Color(0xFF131022),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            if (shot.imagePath != null) _RealImage(path: shot.imagePath!),
            if (shot.isFav)
              const Positioned(
                top: 8,
                right: 8,
                child: _FavDot(),
              ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'chat':
        return Icons.chat_bubble;
      case 'travel':
        return Icons.flight;
      case 'work':
        return Icons.work;
      case 'dev':
        return Icons.terminal;
      case 'food':
        return Icons.restaurant;
      case 'fun':
        return Icons.emoji_emotions;
      case 'design':
        return Icons.palette;
      case 'receipt':
        return Icons.receipt_long;
      default:
        return Icons.sticky_note_2;
    }
  }
}

class _RealImage extends StatelessWidget {
  final String path;
  const _RealImage({required this.path});
  @override
  Widget build(BuildContext context) {
    final f = File(path);
    if (!f.existsSync()) return const SizedBox.shrink();
    // Decode a small thumbnail, not the full 1440px+ screenshot —
    // full-res decodes for every grid cell were the #1 jank source.
    return Positioned.fill(
      child: Image(
        image: ResizeImage(FileImage(f), width: 480),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

class _FavDot extends StatelessWidget {
  const _FavDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        color: Color(0xFF131022),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.favorite, size: 12, color: Color(0xFFFFB020)),
    );
  }
}

/// Staggered entrance wrapper — fade + slide + scale with index delay.
class Entrance extends StatefulWidget {
  final int index;
  final Widget child;
  const Entrance({super.key, required this.index, required this.child});
  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final delay = (widget.index.clamp(0, 10) * 0.06).toDouble();
    _fade = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _c, curve: Interval(delay, 1, curve: Curves.easeOut)));
    _slide = Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(
        CurvedAnimation(
            parent: _c, curve: Interval(delay, 1, curve: Curves.easeOutCubic)));
    Future.delayed(const Duration(milliseconds: 30), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(_fade),
            child: widget.child),
      ),
    );
  }
}

/// Pressable scale wrapper for tactile micro-interaction.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  double _s = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _s = 0.96),
      onTapUp: (_) => setState(() => _s = 1),
      onTapCancel: () => setState(() => _s = 1),
      child: AnimatedScale(
        scale: _s,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// OpenContainer wrapper for shared-element style transitions.
class FlowOpen extends StatelessWidget {
  final Widget closed;
  final Widget Function(BuildContext) openBuilder;
  const FlowOpen({super.key, required this.closed, required this.openBuilder});
  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      openColor: Theme.of(context).scaffoldBackgroundColor,
      middleColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 480),
      transitionType: ContainerTransitionType.fadeThrough,
      closedBuilder: (c, action) => closed,
      openBuilder: (c, _) => openBuilder(c),
    );
  }
}

/// Fanned stack preview for a collection (like the reference, but bolder).
class FanStack extends StatelessWidget {
  final List<ShotItem> shots;
  final Color accent;
  const FanStack({super.key, required this.shots, required this.accent});
  @override
  Widget build(BuildContext context) {
    final items = shots.take(3).toList();
    if (items.isEmpty) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Center(
          child: Icon(Icons.add_photo_alternate_outlined,
              color: accent, size: 30),
        ),
      );
    }
    return SizedBox(
      height: 118,
      child: Stack(
        // Clip the fanned cards to the stack's bounds. Without this,
        // the last card paints past the cell edge (debug shows the red
        // "overflowed" stripes; release paints outside the card).
        clipBehavior: Clip.hardEdge,
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * 26.0,
              top: (i % 2) * 10.0,
              child: Transform.rotate(
                angle: (i - 1) * 0.09,
                child: Container(
                  width: 92,
                  height: 104,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      )
                    ],
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: ShotThumb(shot: items[i], borderRadius: 13),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF131022),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('${shots.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Virtualized masonry sliver of shots with hero + selection support.
///
/// NOTE: this must stay a sliver (SliverMasonryGrid). The old
/// shrinkWrap + NeverScrollablePhysics version built all 285 cells and
/// 285 animation controllers up front — that was the lag on big libraries.
/// Only the first 12 cells get entrance animations.
class ShotMasonrySliver extends StatelessWidget {
  final List<ShotItem> shots;
  final Set<String> selected;
  final void Function(ShotItem) onTap;
  final void Function(ShotItem) onLongPress;
  final bool comfy;
  const ShotMasonrySliver({
    super.key,
    required this.shots,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.comfy = true,
  });
  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) {
      return const SliverToBoxAdapter(child: EmptyFlow());
    }
    return SliverMasonryGrid.count(
      crossAxisCount: comfy ? 2 : 3,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childCount: shots.length,
      itemBuilder: (c, i) {
        final s = shots[i];
        final isSel = selected.contains(s.id);
        final h = 150.0 + ((s.gradientSeed % 5) * 22);
        final cell = Pressable(
          onTap: () => onTap(s),
          onLongPress: () => onLongPress(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: isSel
                  ? Border.all(
                      color: ChobiColors.marigold, width: 3)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: Theme.of(context).brightness ==
                              Brightness.dark
                          ? 0.35
                          : 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Stack(
              children: [
                Hero(
                  tag: 'shot-${s.id}',
                  child: SizedBox(
                    height: h,
                    child: ShotThumb(shot: s, borderRadius: 20),
                  ),
                ),
                if (isSel)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: ChobiColors.marigold
                            .withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          backgroundColor: ChobiColors.marigold,
                          child: Icon(Icons.check,
                              color: Color(0xFF131022)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        if (i < 12) return Entrance(index: i, child: cell);
        return cell;
      },
    );
  }
}

class EmptyFlow extends StatelessWidget {
  const EmptyFlow({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF21183D) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: dark
                ? const Color(0xFF3A2E63)
                : const Color(0xFFEEE6D6)),
      ),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 2 * math.pi),
            duration: const Duration(seconds: 9),
            builder: (c, v, child) => Transform.rotate(
              angle: v,
              child: child,
            ),
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0xFFFFB020),
                  Color(0xFF2DD4BF),
                ]),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 16),
          Text('Nothing in the flow yet',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Import a screenshot or pick a collection.\nChobiFlow will auto-tag it for you.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark
                    ? const Color(0xFFB9B2D3)
                    : const Color(0xFF6B6486)),
          ),
          const SizedBox(height: 8),
          const FlowRibbon(height: 34, opacity: 0.9),
        ],
      ),
    );
  }
}
