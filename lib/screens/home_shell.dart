import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../chobi_theme.dart';
import '../device_import.dart';
import '../flow_store.dart';
import '../smart_stacks.dart';
import '../models.dart';
import '../widgets/flow_widgets.dart';
import 'detail.dart';

class HomeShell extends StatefulWidget {
  final FlowStore store;
  const HomeShell({super.key, required this.store});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() => widget.store.setSearch(_searchCtl.text));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        child: _body(),
      ),
      extendBody: true,
      floatingActionButton: _tab == 2
          ? null
          : FloatingActionButton.small(
              onPressed: () => _openAdd(context),
              child: const Icon(Icons.add),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF21183D) : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, -8)),
          ],
        ),
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          child: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (v) {
              setState(() => _tab = v);
              HapticFeedback.selectionClick();
            },
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.water_drop_outlined),
                  activeIcon: Icon(Icons.water_drop),
                  label: 'Flow'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.grid_view_outlined),
                  activeIcon: Icon(Icons.grid_view_rounded),
                  label: 'Stacks'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  activeIcon: Icon(Icons.search_rounded),
                  label: 'Search'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0:
        return _FlowTab(key: const ValueKey('flow'), store: widget.store, onAdd: () => _openAdd(context));
      case 1:
        return _StacksTab(key: const ValueKey('stacks'), store: widget.store);
      case 2:
        return _SearchTab(
            key: const ValueKey('search'), store: widget.store, ctl: _searchCtl);
      default:
        return _FlowTab(
            key: const ValueKey('flow'), store: widget.store,
            onAdd: () => _openAdd(context));
    }
  }

  void _openAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSheet(store: widget.store),
    );
  }
}

// ---------------- FLOW TAB ----------------
class _FlowTab extends StatefulWidget {
  final FlowStore store;
  final VoidCallback onAdd;
  const _FlowTab({super.key, required this.store, required this.onAdd});
  @override
  State<_FlowTab> createState() => _FlowTabState();
}

class _FlowTabState extends State<_FlowTab> {
  final Set<String> _sel = {};
  bool get selecting => _sel.isNotEmpty;

  // Device Screenshots-folder import state.
  bool _askedOnce = false;
  bool _scanning = false;
  bool _denied = false;
  int _deviceFound = 0;
  int _deviceAlbums = 0;
  int _importedTotal = 0;
  int _ocrPending = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeAutoScan();
      _refreshOcrPending();
      _maybeSmart();
    });
  }

  /// Kick off on-device identification in the background (fire & forget —
  /// progress streams through the store + banner). Auto-called after
  /// imports when the Settings toggle is on.
  Future<void> _startOcr() async {
    final store = widget.store;
    if (store.ocrRunning) return;
    if (store.computePendingOcr() == 0) return;
    await store.runOcrBatch();
    if (!mounted) return;
    setState(() => _ocrPending = store.computePendingOcr());
    if (!context.mounted) return;
    if (_ocrPending == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'All screenshots identified — search now reads inside images'),
        behavior: SnackBarBehavior.floating,
      ));
      _maybeSmart();
    }
  }

  void _refreshOcrPending() {
    if (!mounted) return;
    setState(
        () => _ocrPending = widget.store.computePendingOcr());
  }

  /// Run the vision-model analysis, then show the approve-before-anything-
  /// moves preview sheet.
  Future<void> _startSmart() async {
    final store = widget.store;
    if (store.smartRunning) return;
    final proposals = await store.runSmartAnalysis();
    if (!mounted || !context.mounted) return;
    if (proposals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No natural groups found — needs 6+ visually similar shots'),
        behavior: SnackBarBehavior.floating,
      ));
      setState(() {});
      return;
    }
    showSmartPreviewSheet(context, store, proposals);
  }

  /// One-time magic: once everything is identified, let the AI propose
  /// stacks by itself. Manual re-runs always available afterwards.
  Future<void> _maybeSmart() async {
    final store = widget.store;
    if (!mounted || store.smartRunning || store.ocrRunning) return;
    await store.repairSmartState();
    if (!mounted ||
        !store.autoSmart ||
        store.smartEverRan) {
      return;
    }
    if (store.computePendingOcr() > 0) return;
    if (store.smartEligible().length < 8) return;
    _startSmart();
  }

  /// First launch: ask for photo access once, then auto-organize any
  /// real screenshots found in the device Screenshots folder.
  Future<void> _maybeAutoScan() async {
    if (_askedOnce || !mounted) return;
    _askedOnce = true;
    if (!widget.store.autoImport) return;
    setState(() => _scanning = true);
    try {
      final granted = await DeviceImport.request();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _scanning = false;
          _denied = true;
        });
        return;
      }
      final res = await DeviceImport.scan();
      final found = res.shots;
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() => _scanning = false);
        return;
      }
      final result = await widget.store.importDeviceShots(found);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _deviceFound = found.length;
        _deviceAlbums = res.albums;
        _importedTotal += result.added;
      });
      _refreshOcrPending();
      if (widget.store.autoIdentify && _ocrPending > 0) _startOcr();
      if (result.added > 0 && context.mounted) {
        _showImportReport(context, result.added, result.perCollection);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _denied = true;
        });
      }
    }
  }

  /// Manual re-scan from the banner / settings.
  Future<void> rescan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _denied = false;
    });
    try {
      final granted = await DeviceImport.request();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _scanning = false;
          _denied = true;
        });
        return;
      }
      final res = await DeviceImport.scan();
      final found = res.shots;
      if (!mounted) return;
      final result = await widget.store.importDeviceShots(found);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _deviceFound = found.length;
        _deviceAlbums = res.albums;
        _importedTotal += result.added;
      });
      _refreshOcrPending();
      if (widget.store.autoIdentify && _ocrPending > 0) _startOcr();
      if (context.mounted) {
        if (result.added > 0) {
          _showImportReport(
              context, result.added, result.perCollection);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Screenshots folder already fully organized '
                '(${found.length} found)'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// "Here's what I did" sheet — the organizing must be SEEN, not silent.
  void _showImportReport(
      BuildContext context, int added, Map<String, int> per) {
    final store = widget.store;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 14),
            Text('Organized $added screenshots',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 22)),
            const Text('Tap a stack to see what landed where.',
                style: TextStyle(
                    color: Color(0xFF0E9F8A),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final entry in (per.entries.toList()
                      ..sort((a, b) =>
                          b.value.compareTo(a.value))))
                      _ReportRow(
                        store: store,
                        collectionId: entry.key,
                        count: entry.value,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF131022),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99)),
                ),
                child: const Text('Nice — show my flow',
                    style:
                        TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (c, _) {
        final store = widget.store;
        final shots = store.visibleShots;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('ChobiFlow',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      height: 1)),
                        ),
                        _iconBtn(context, Icons.tune_rounded,
                            () => _openSettings(context)),
                        _iconBtn(context,
                            store.themeMode == ThemeMode.dark
                                ? Icons.light_mode
                                : Icons.dark_mode, () {
                          store.setTheme(
                              store.themeMode == ThemeMode.dark
                                  ? ThemeMode.light
                                  : ThemeMode.dark);
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${store.totalCount} screenshots · '
                      '${store.collections.length} stacks',
                      style: TextStyle(
                          color: dark
                              ? const Color(0xFFB9B2D3)
                              : const Color(0xFF6B6486),
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const FlowRibbon(height: 44),
                    const SizedBox(height: 12),
                    _DeviceBanner(
                      scanning: _scanning,
                      denied: _denied,
                      found: _deviceFound,
                      albums: _deviceAlbums,
                      imported: _importedTotal,
                      ocrPending: _ocrPending,
                      store: widget.store,
                      onScan: rescan,
                      onIdentify: _startOcr,
                      onAnalyze: _startSmart,
                    ),
                    const SizedBox(height: 14),
                    _FilterBar(store: store),
                  ],
                ),
              ),
            ),
            if (selecting)
              SliverToBoxAdapter(child: _SelectBar(
                count: _sel.length,
                onClear: () => setState(_sel.clear),
                onFav: () async {
                  for (final s in store.shots.where((e) => _sel.contains(e.id))) {
                    s.isFav = true;
                  }
                  await store.persist();
                  if (mounted) setState(_sel.clear);
                },
                onMove: () => _pickCollection(context),
              )),
            SliverPadding(
              padding:
                  const EdgeInsets.fromLTRB(20, 12, 20, 140),
              sliver: ShotMasonrySliver(
                shots: shots,
                selected: _sel,
                comfy: store.comfyGrid,
                onTap: (s) {
                  if (selecting) {
                    setState(() {
                      if (_sel.contains(s.id)) {
                        _sel.remove(s.id);
                      } else {
                        _sel.add(s.id);
                      }
                    });
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ShotDetail(
                              store: store, shot: s)),
                    );
                  }
                },
                onLongPress: (s) {
                  HapticFeedback.mediumImpact();
                  setState(() => _sel.add(s.id));
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _iconBtn(BuildContext c, IconData i, VoidCallback f) {
    final dark = Theme.of(c).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: f,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF21183D) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: dark
                    ? const Color(0xFF3A2E63)
                    : const Color(0xFFEEE6D6)),
          ),
          child: Icon(i, size: 20),
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(store: widget.store),
    );
  }

  void _pickCollection(BuildContext context) {
    final store = widget.store;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move ${_sel.length} to…',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final col in store.collections)
                  GestureDetector(
                    onTap: () async {
                      await store.moveShots(
                          _sel.toList(), col.id);
                      if (context.mounted) Navigator.pop(context);
                      setState(_sel.clear);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: col.color.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(99),
                        border: Border.all(
                            color: col.color
                                .withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(col.icon,
                              size: 16, color: col.color),
                          const SizedBox(width: 6),
                          Text(col.name,
                              style: const TextStyle(
                                  fontWeight:
                                      FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Preview-before-anything-moves sheet for AI-invented stacks.
void showSmartPreviewSheet(
    BuildContext context, FlowStore store, List<SmartProposal> proposals) {
  final total = proposals.fold(0, (n, p) => n + p.size);
  final pct = (store.smartThreshold * 100).round();
  final excluded = <int>{};
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(
      builder: (c, setSheet) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 14),
            Text('AI invented ${proposals.length} stacks',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 22)),
            Text('$total screenshots grouped by look + content '
                '($pct% similarity bar) — untick any stack to skip it.',
                style: const TextStyle(
                    color: Color(0xFF0E9F8A),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < proposals.length; i++)
                      _SmartProposalRow(
                        store: store,
                        proposal: proposals[i],
                        included: !excluded.contains(i),
                        onToggle: () => setSheet(() {
                          if (excluded.contains(i)) {
                            excluded.remove(i);
                          } else {
                            excluded.add(i);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99)),
                    ),
                    child: const Text('Discard',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: excluded.length == proposals.length
                        ? null
                        : () async {
                            final kept = [
                              for (var i = 0;
                                  i < proposals.length;
                                  i++)
                                if (!excluded.contains(i))
                                  proposals[i]
                            ];
                            final moved = await store
                                .applySmartProposals(kept);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    'Created ${kept.length} smart stacks • '
                                    '$moved shots moved'),
                                behavior:
                                    SnackBarBehavior.floating,
                              ));
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB020),
                      foregroundColor: const Color(0xFF131022),
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99)),
                    ),
                    child: Text(
                        'Create ${proposals.length - excluded.length} stacks  →',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SmartProposalRow extends StatelessWidget {
  final FlowStore store;
  final SmartProposal proposal;
  final bool included;
  final VoidCallback onToggle;
  const _SmartProposalRow({
    required this.store,
    required this.proposal,
    required this.included,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in store.shots) s.id: s};
    final samples = [
      for (final id in proposal.memberIds.take(3))
        byId[id]
    ].whereType<ShotItem>().toList();
    final look = store.smartLook(proposal.kind);
    final match = (proposal.cohesion * 100).round().clamp(0, 99);
    return Opacity(
      opacity: included ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF21183D)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: look.$2.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            height: 64,
            child: Stack(
              children: [
                for (var i = 0; i < samples.length; i++)
                  Positioned(
                    left: i * 24.0,
                    child: Container(
                      width: 56,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white, width: 2),
                      ),
                      child: ShotThumb(
                          shot: samples[i], borderRadius: 10),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proposal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                    '${proposal.size} shots • $match% match • AI',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0E9F8A),
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: included
                    ? look.$2.withValues(alpha: 0.14)
                    : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                  included ? Icons.check_circle : Icons.circle_outlined,
                  size: 22,
                  color: included ? look.$2 : Colors.grey),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final FlowStore store;
  final String collectionId;
  final int count;
  const _ReportRow({
    required this.store,
    required this.collectionId,
    required this.count,
  });
  @override
  Widget build(BuildContext context) {
    final col = store.collectionOf(collectionId);
    final sample =
        store.shotsIn(collectionId).take(3).toList();
    return Pressable(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CollectionPage(
                  store: store, collection: col)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF21183D)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: col.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: col.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(col.icon, color: col.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count → ${col.name}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900)),
                  if (sample.isNotEmpty)
                    Text(sample.map((s) => s.title).join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// Banner for device import + on-device identification: scanning,
/// permission nudge, OCR progress, identify prompt, or summary.
class _DeviceBanner extends StatelessWidget {
  final bool scanning;
  final bool denied;
  final int found;
  final int albums;
  final int imported;
  final int ocrPending;
  final FlowStore store;
  final VoidCallback onScan;
  final VoidCallback onIdentify;
  final VoidCallback onAnalyze;
  const _DeviceBanner({
    required this.scanning,
    required this.denied,
    required this.found,
    this.albums = 0,
    required this.imported,
    required this.ocrPending,
    required this.store,
    required this.onScan,
    required this.onIdentify,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ocrRunning = store.ocrRunning;
    final smartRunning = store.smartRunning;
    final smartN =
        (!smartRunning && ocrPending == 0 && !scanning && !denied)
            ? store.smartEligible().length
            : 0;
    String title;
    String body;
    IconData icon;
    String action;
    VoidCallback? act;
    if (scanning) {
      title = 'Scanning Screenshots folders…';
      body = 'Reading your device screenshots to auto-organize them.';
      icon = Icons.sync;
      action = '…';
      act = null;
    } else if (denied) {
      title = 'See your real screenshots here';
      body = 'Allow photo access so ChobiFlow can organize '
          'your Screenshots folders — not just demo data.';
      icon = Icons.photo_library_outlined;
      action = 'Allow';
      act = onScan;
    } else if (ocrRunning) {
      title = 'Identifying images… '
          '${store.ocrDoneCount}/${store.ocrTotal}';
      body = 'Reading the text inside each screenshot, on your phone. '
          'Stacks + search get smarter as it goes. Plug in if low.';
      icon = Icons.document_scanner_outlined;
      action = 'Cancel';
      act = store.cancelOcr;
    } else if (ocrPending > 0) {
      title = '$ocrPending screenshots need identifying';
      body = 'Looks inside each image (text, receipts, chats…) — '
          'no filenames needed, nothing leaves your phone.';
      icon = Icons.document_scanner_outlined;
      action = 'Identify';
      act = onIdentify;
    } else if (smartRunning) {
      if (store.smartPhase == 'download') {
        final pct = store.smartModelProgress == null
            ? ''
            : ' ${(store.smartModelProgress! * 100).round()}%';
        title = 'Fetching vision model…$pct';
        body = 'One-time ~43MB download — then everything runs '
            'offline, on your phone, forever.';
      } else if (store.smartPhase == 'embed') {
        title = 'Looking at images… ${store.smartDone}/${store.smartTotal}';
        body = 'The vision model compares what your screenshots '
            'look like. Nothing moves without your approval.';
      } else {
        title = 'Inventing categories…';
        body = 'Grouping look-alikes and naming each stack.';
      }
      icon = Icons.auto_awesome;
      action = 'Cancel';
      act = store.cancelSmart;
    } else if (store.smartPhase == 'error') {
      title = 'Smart analysis stumbled';
      body = store.smartError.isNotEmpty
          ? 'Reason: ${store.smartError}. Tap to retry — '
            'photos never leave your phone.'
          : 'The vision step failed (model, memory, or a bad image). '
            'Nothing moved. Tap to retry — photos never leave your phone.';
      icon = Icons.cloud_off_outlined;
      action = 'Retry';
      act = onAnalyze;
    } else if (smartN >= 6) {
      title = 'Let AI invent the categories?';
      body = 'Compares what $smartN screenshots look like + say, '
          'proposes smart stacks — you approve before anything moves.';
      icon = Icons.auto_awesome;
      action = 'Analyze';
      act = onAnalyze;
    } else if (found == 0 && imported == 0) {
      title = 'Scan device screenshots';
      body = 'Pulls your real Screenshots folders into collections. '
          'Demo data stays until you organize the real thing.';
      icon = Icons.photo_library_outlined;
      action = 'Scan';
      act = onScan;
    } else if (imported == 0 && store.identifiedCount > 0) {
      final where = albums > 1 ? ' across $albums folders' : '';
      title = 'All caught up • $found in Screenshots$where';
      body = '${store.identifiedCount} identified — search reads inside '
          'images now. New shots auto-import on launch.';
      icon = Icons.check_circle_outline;
      action = 'Scan';
      act = onScan;
    } else if (imported == 0) {
      final where = albums > 1 ? ' across $albums folders' : '';
      title = 'All caught up • $found in Screenshots$where';
      body = 'Everything already organized. New shots auto-import '
          'on launch — or tap Scan now.';
      icon = Icons.check_circle_outline;
      action = 'Scan';
      act = onScan;
    } else {
      title = '$found in Screenshots • $imported just organized';
      body = 'New screenshots? Re-scan anytime — duplicates are skipped.';
      icon = Icons.check_circle_outline;
      action = 'Scan';
      act = onScan;
    }
    final useGradient = scanning ||
        ocrRunning ||
        ocrPending > 0 ||
        smartRunning ||
        store.smartPhase == 'error' ||
        smartN >= 6 ||
        found > 0 ||
        imported > 0;
    const ink = Color(0xFF131022);
    final titleColor =
        useGradient ? ink : Theme.of(context).textTheme.bodyLarge?.color;
    final bodyColor = useGradient
        ? const Color(0xFF5A4A1A)
        : (dark ? const Color(0xFFB9B2D3) : const Color(0xFF6B6486));
    double? progress;
    if (ocrRunning && store.ocrTotal > 0) {
      progress = store.ocrDoneCount / store.ocrTotal;
    } else if (smartRunning) {
      if (store.smartPhase == 'download') {
        progress = store.smartModelProgress;
      } else if (store.smartPhase == 'embed' && store.smartTotal > 0) {
        progress = store.smartDone / store.smartTotal;
      }
    }
    return Pressable(
      onTap: act,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: useGradient
              ? const LinearGradient(colors: [
                  Color(0xFFFFB020),
                  Color(0xFFFFD166),
                ])
              : null,
          color: useGradient
              ? null
              : (dark ? const Color(0xFF21183D) : Colors.white),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: dark
                  ? const Color(0xFF3A2E63)
                  : const Color(0xFFEEE6D6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (scanning || ocrRunning || smartRunning)
                  const SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: Color(0xFF131022)),
                  )
                else
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (useGradient
                              ? ink
                              : const Color(0xFF0E9F8A))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        size: 20,
                        color: useGradient
                            ? ink
                            : const Color(0xFF0E9F8A)),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: titleColor)),
                      const SizedBox(height: 2),
                      Text(body,
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: bodyColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131022),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(action,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12)),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor:
                      const Color(0xFF131022).withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(
                      Color(0xFF131022)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final FlowStore store;
  const _FilterBar({required this.store});
  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool active, VoidCallback onTap,
        {Color? glow}) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF131022)
                : Theme.of(context).brightness ==
                        Brightness.dark
                    ? Colors.white10
                    : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: active
                    ? const Color(0xFF131022)
                    : Theme.of(context).brightness ==
                            Brightness.dark
                        ? Colors.white12
                        : const Color(0xFFEEE6D6)),
            boxShadow: active && glow != null
                ? [
                    BoxShadow(
                        color: glow.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 6))
                  ]
                : [],
          ),
          child: Text(label,
              style: TextStyle(
                  color: active
                      ? Colors.white
                      : Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('All', store.filter == FilterMode.all,
            () => store.setFilter(FilterMode.all)),
        chip('Favorites', store.filter == FilterMode.favorites,
            () => store.setFilter(FilterMode.favorites),
            glow: const Color(0xFFFFB020)),
        GestureDetector(
          onTap: () {
            final next = store.sort == SortMode.newest
                ? SortMode.oldest
                : store.sort == SortMode.oldest
                    ? SortMode.name
                    : SortMode.newest;
            store.setSort(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB020).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: const Color(0xFFFFB020)
                      .withValues(alpha: 0.45)),
            ),
            child: Text('Sort: ${store.sort.name}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF8A5A00))),
          ),
        ),
      ],
    );
  }
}

class _SelectBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear, onFav, onMove;
  const _SelectBar(
      {required this.count,
      required this.onClear,
      required this.onFav,
      required this.onMove});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF131022),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text('$count selected',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
                onPressed: onFav,
                icon: const Icon(Icons.favorite,
                    color: Color(0xFFFFB020))),
            IconButton(
                onPressed: onMove,
                icon: const Icon(Icons.drive_file_move,
                    color: Colors.white)),
            IconButton(
                onPressed: onClear,
                icon:
                    const Icon(Icons.close, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

// ---------------- STACKS TAB ----------------
class _StacksTab extends StatelessWidget {
  final FlowStore store;
  const _StacksTab({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (c, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text('Stacks',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight:
                                        FontWeight.w900)),
                        Text(
                            '${store.collections.length} collections • tap to dive in',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _newCollection(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB020),
                        borderRadius:
                            BorderRadius.circular(99),
                      ),
                      child: const Text('+ New',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF131022))),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            child: FlowRibbon(height: 36),
          )),
          SliverPadding(
            padding:
                const EdgeInsets.fromLTRB(20, 0, 20, 140),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (c, i) {
                  final col = store.collections[i];
                  final shots = store.shotsIn(col.id);
                  return Entrance(
                    index: i,
                    child: Pressable(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                CollectionPage(
                                    store: store,
                                    collection: col)),
                      ),
                      onLongPress: () =>
                          _editCollection(context, col),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                                      .brightness ==
                                  Brightness.dark
                              ? const Color(0xFF21183D)
                              : Colors.white,
                          borderRadius:
                              BorderRadius.circular(26),
                          border: Border.all(
                              color: Theme.of(context)
                                          .brightness ==
                                      Brightness.dark
                                  ? const Color(0xFF3A2E63)
                                  : const Color(0xFFEEE6D6)),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            FanStack(
                                shots: shots,
                                accent: col.color),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  padding:
                                      const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: col.color.withValues(
                                        alpha: 0.14),
                                    borderRadius:
                                        BorderRadius.circular(
                                            12),
                                  ),
                                  child: Icon(col.icon,
                                      size: 16,
                                      color: col.color),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(col.name,
                                          maxLines: 1,
                                          overflow: TextOverflow
                                              .ellipsis,
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight
                                                      .w900)),
                                      Text(
                                          '${shots.length} shots',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                      context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: store.collections.length,
              ),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: 232,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _newCollection(BuildContext context) {
    final nameCtl = TextEditingController();
    Color picked = const Color(0xFF5B2EEE);
    IconData icon = Icons.folder_outlined;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (c, setS) {
        return Container(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          decoration: BoxDecoration(
            color: Theme.of(c).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New stack',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                  hintText: 'e.g. Recipes, Flights, Memes…',
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Color',
                  style:
                      TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (final col
                      in ChobiColors.collectionPalette)
                    GestureDetector(
                      onTap: () => setS(() => picked = col),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: col,
                          shape: BoxShape.circle,
                          border: picked == col
                              ? Border.all(
                                  color: Colors.black,
                                  width: 3)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Icon',
                  style:
                      TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final ic in [
                    Icons.folder_outlined,
                    Icons.work_outline,
                    Icons.flight_takeoff,
                    Icons.chat_bubble_outline,
                    Icons.favorite_outline,
                    Icons.receipt_long,
                    Icons.palette_outlined,
                    Icons.terminal,
                  ])
                    GestureDetector(
                      onTap: () => setS(() => icon = ic),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: icon == ic
                              ? const Color(0xFF131022)
                              : Theme.of(c).cardColor,
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                        child: Icon(ic,
                            color: icon == ic
                                ? Colors.white
                                : picked),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (nameCtl.text.trim().isEmpty) {
                      return;
                    }
                    await store.addCollection(
                        nameCtl.text.trim(), icon, picked);
                    if (c.mounted) Navigator.pop(c);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF131022),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(99)),
                  ),
                  child: const Text('Create stack',
                      style: TextStyle(
                          fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _editCollection(
      BuildContext context, ShotCollection col) {
    final nameCtl = TextEditingController(text: col.name);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(col.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                    filled: true,
                    hintText: 'Rename…',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(16),
                        borderSide:
                            BorderSide.none))),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await store.renameCollection(
                          col, nameCtl.text.trim());
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 10),
                if (!col.isBuiltin)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await store
                            .deleteCollection(col);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                          foregroundColor:
                              const Color(0xFFFF6B6B)),
                      child: const Text('Delete'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------- SEARCH TAB ----------------
class _SearchTab extends StatelessWidget {
  final FlowStore store;
  final TextEditingController ctl;
  const _SearchTab(
      {super.key, required this.store, required this.ctl});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (c, _) {
        final results = store.visibleShots;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 56, 20, 0),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Search the flow',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                                fontWeight:
                                    FontWeight.w900)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ctl,
                      decoration: InputDecoration(
                        hintText:
                            'Try “flight”, “rent”, “error”…',
                        prefixIcon:
                            const Icon(Icons.search),
                        filled: true,
                        fillColor: Theme.of(context)
                                    .brightness ==
                                Brightness.dark
                            ? const Color(0xFF21183D)
                            : Colors.white,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(99),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FilterBar(store: store),
                    const SizedBox(height: 6),
                    Text('${results.length} results',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  20, 12, 20, 140),
              sliver: ShotMasonrySliver(
                shots: results,
                selected: const {},
                comfy: store.comfyGrid,
                onTap: (s) => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ShotDetail(
                            store: store, shot: s))),
                onLongPress: (_) {},
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------- COLLECTION PAGE ----------------
class CollectionPage extends StatefulWidget {
  final FlowStore store;
  final ShotCollection collection;
  const CollectionPage(
      {super.key, required this.store, required this.collection});
  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final Set<String> _sel = {};
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (c, _) {
        final shots =
            widget.store.shotsIn(widget.collection.id);
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 210,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        widget.collection.color,
                        widget.collection.color
                            .withValues(alpha: 0.55),
                      ]),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            56, 10, 20, 0),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Icon(widget.collection.icon,
                                color: Colors.white,
                                size: 30),
                            const Spacer(),
                            Text(widget.collection.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight:
                                        FontWeight.w900)),
                            Text('${shots.length} shots',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight:
                                        FontWeight.w700)),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_sel.isNotEmpty)
                SliverToBoxAdapter(
                    child: _SelectBar(
                  count: _sel.length,
                  onClear: () =>
                      setState(_sel.clear),
                  onFav: () async {
                    for (final s in widget.store.shots
                        .where((e) =>
                            _sel.contains(e.id))) {
                      s.isFav = true;
                    }
                    await widget.store.persist();
                    setState(_sel.clear);
                  },
                  onMove: () {},
                )),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    20, 16, 20, 100),
                sliver: ShotMasonrySliver(
                  shots: shots,
                  selected: _sel,
                  comfy: widget.store.comfyGrid,
                  onTap: (s) {
                    if (_sel.isNotEmpty) {
                      setState(() {
                        if (_sel.contains(s.id)) {
                          _sel.remove(s.id);
                        } else {
                          _sel.add(s.id);
                        }
                      });
                    } else {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ShotDetail(
                                      store:
                                          widget.store,
                                      shot: s)));
                    }
                  },
                  onLongPress: (s) => setState(
                      () => _sel.add(s.id)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------- ADD SHEET ----------------
class _AddSheet extends StatefulWidget {
  final FlowStore store;
  const _AddSheet({required this.store});
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String _colId = 'recent';
  String _kind = 'note';
  String? _img;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.store.collections.isNotEmpty) {
      _colId = widget.store.collections.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius:
                          BorderRadius.circular(99))),
            ),
            const SizedBox(height: 14),
            const Text('Add to flow',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22)),
            const Text('AI will auto-tag it for you',
                style: TextStyle(
                    color: Color(0xFF0E9F8A),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Title — e.g. Flight to Tokyo 6:40AM',
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Note (optional)…',
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Collection',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final col in widget.store.collections)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _colId = col.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 9),
                      decoration: BoxDecoration(
                        color: _colId == col.id
                            ? col.color
                            : col.color.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(99),
                      ),
                      child: Text(col.name,
                          style: TextStyle(
                              color: _colId == col.id
                                  ? Colors.white
                                  : col.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Type',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final k in [
                  'note',
                  'chat',
                  'work',
                  'travel',
                  'dev',
                  'fun'
                ])
                  GestureDetector(
                    onTap: () =>
                        setState(() => _kind = k),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 9),
                      decoration: BoxDecoration(
                        color: _kind == k
                            ? const Color(0xFF131022)
                            : Theme.of(context).cardColor,
                        borderRadius:
                            BorderRadius.circular(99),
                      ),
                      child: Text(k,
                          style: TextStyle(
                              color: _kind == k
                                  ? Colors.white
                                  : null,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.image, size: 18),
                    label: Text(_img == null
                        ? 'Gallery'
                        : 'Picked'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _snap,
                    icon: const Icon(Icons.photo_camera,
                        size: 18),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFFFB020),
                  foregroundColor:
                      const Color(0xFF131022),
                  padding: const EdgeInsets.symmetric(
                      vertical: 17),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(99)),
                ),
                child: Text(
                    _busy ? 'Flowing…' : 'Add to ChobiFlow  →',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (f != null) setState(() => _img = f.path);
  }

  Future<void> _snap() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 82);
    if (f != null) setState(() => _img = f.path);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give it a title first')));
      return;
    }
    setState(() => _busy = true);
    await widget.store.addShot(
      title: _title.text.trim(),
      collectionId: _colId,
      kind: _kind,
      note: _note.text.trim(),
      imagePath: _img,
    );
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context);
  }
}

// ---------------- SETTINGS ----------------
class _SettingsSheet extends StatelessWidget {
  final FlowStore store;
  const _SettingsSheet({required this.store});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (c, _) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tune your flow',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20)),
            const SizedBox(height: 4),
            Text(
                'Chobi = picture, Flow = calm',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
            const Text('Appearance',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final m in ThemeMode.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => store.setTheme(m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          decoration: BoxDecoration(
                            color: store.themeMode == m
                                ? const Color(0xFF131022)
                                : Theme.of(context).cardColor,
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                          child: Text(m.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color:
                                      store.themeMode == m
                                          ? Colors.white
                                          : null,
                                  fontWeight:
                                      FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                    child: Text('Comfy grid',
                        style: TextStyle(
                            fontWeight: FontWeight.w800))),
                Switch(
                    value: store.comfyGrid,
                    activeTrackColor:
                        const Color(0xFFFFB020),
                    onChanged: (v) =>
                        store.setDensity(v)),
              ],
            ),
            Row(
              children: [
                const Expanded(
                    child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Auto-organize Screenshots',
                        style: TextStyle(
                            fontWeight: FontWeight.w800)),
                    Text('Scan device folder on launch',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey)),
                  ],
                )),
                Switch(
                    value: store.autoImport,
                    activeTrackColor:
                        const Color(0xFFFFB020),
                    onChanged: (v) =>
                        store.setAutoImport(v)),
              ],
            ),
            Row(
              children: [
                const Expanded(
                    child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Auto-identify new shots',
                        style: TextStyle(
                            fontWeight: FontWeight.w800)),
                    Text('Read text inside images, on-device',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey)),
                  ],
                )),
                Switch(
                    value: store.autoIdentify,
                    activeTrackColor:
                        const Color(0xFFFFB020),
                    onChanged: (v) =>
                        store.setAutoIdentify(v)),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                  Icons.document_scanner_outlined),
              title: const Text('Identify screenshots now'),
              subtitle: Text(store.ocrRunning
                  ? 'Working… ${store.ocrDoneCount}/${store.ocrTotal}'
                  : '${store.computePendingOcr()} pending • '
                    '${store.identifiedCount} already read'),
              onTap: store.ocrRunning
                  ? null
                  : () {
                      Navigator.pop(context);
                      // Fire through the Flow tab next build is complex;
                      // run directly on the store instead.
                      store.runOcrBatch();
                    },
            ),
            Row(
              children: [
                const Expanded(
                    child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Smart stacks (AI grouping)',
                        style: TextStyle(
                            fontWeight: FontWeight.w800)),
                    Text('Vision model invents categories',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey)),
                  ],
                )),
                Switch(
                    value: store.autoSmart,
                    activeTrackColor:
                        const Color(0xFFFFB020),
                    onChanged: (v) =>
                        store.setAutoSmart(v)),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.auto_awesome_outlined),
              title: const Text('Re-analyze smart stacks'),
              subtitle: Text(store.smartRunning
                  ? '${store.smartPhase}… ${store.smartDone}/${store.smartTotal}'
                  : '${store.smartEligible().length} eligible • '
                    '${store.collections.where((c) => c.isAuto).length} AI stacks'),
              onTap: store.smartRunning
                  ? null
                  : () async {
                      final nav = Navigator.of(context);
                      final ctx = nav.context;
                      nav.pop();
                      final proposals =
                          await store.runSmartAnalysis();
                      if (!ctx.mounted) return;
                      if (proposals.isNotEmpty) {
                        showSmartPreviewSheet(
                            ctx, store, proposals);
                      }
                    },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('About ChobiFlow v1.0.0'),
              subtitle: const Text(
                  'Screenshot Organizer • Untapped Niche • \$2.99/mo spirit, free forever here'),
            ),
            // Keep version/date for README sync check
            const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
