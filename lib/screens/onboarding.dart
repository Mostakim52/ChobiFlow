import 'package:flutter/material.dart';
import '../chobi_theme.dart';

class Onboarding extends StatefulWidget {
  final VoidCallback onDone;
  const Onboarding({super.key, required this.onDone});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final _pc = PageController();
  int _i = 0;

  final _pages = const [
    _ObData(
      kicker: 'NAMASTE â€¢ CHOBI = PICTURE',
      title: 'Endless screenshots,\nfinally in flow.',
      body:
          'ChobiFlow auto-sorts every screenshot into living collections â€” work, chats, travel, ideas â€” so the right one is 5 seconds away.',
      icon: Icons.water_drop,
      c1: Color(0xFF5B2EEE),
      c2: Color(0xFF9D7BFF),
    ),
    _ObData(
      kicker: 'SMART AUTO-TAG â€¢ SEARCH',
      title: 'Snap it. Tag it.\nFind it instantly.',
      body:
          'On-device smart tags read your screenshots. Search â€œflightâ€, â€œrentâ€, â€œerrorâ€ â€” ChobiFlow surfaces it with a glow.',
      icon: Icons.auto_awesome,
      c1: Color(0xFFE68A00),
      c2: Color(0xFFFFD166),
    ),
    _ObData(
      kicker: 'FAVORITES â€¢ FLOW',
      title: 'Keep the gems.\nEverything in flow.',
      body:
          'Favorite, multi-move and share in one swipe. Your homescreen icon says ChobiFlow â€” your mind says relief.',
      icon: Icons.favorite,
      c1: Color(0xFF0E9F8A),
      c2: Color(0xFF5EEAD4),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131022),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB020),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text('ChobiFlow',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF131022))),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Skip',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const FlowRibbon(height: 40, opacity: 0.95),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (v) =>
                    setState(() => _i = v),
                itemCount: _pages.length,
                itemBuilder: (c, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration:
                              const Duration(milliseconds: 400),
                          child: Container(
                            key: ValueKey(i),
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [p.c1, p.c2],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight),
                              borderRadius:
                                  BorderRadius.circular(36),
                              boxShadow: [
                                BoxShadow(
                                    color: p.c1.withValues(
                                        alpha: 0.5),
                                    blurRadius: 40,
                                    offset:
                                        const Offset(0, 18)),
                              ],
                            ),
                            child: Center(
                              child: Icon(p.icon, size: 48,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(p.kicker,
                            style: const TextStyle(
                                color: Color(0xFF2DD4BF),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                fontSize: 12)),
                        const SizedBox(height: 10),
                        Text(p.title,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05)),
                        const SizedBox(height: 12),
                        Text(p.body,
                            style: const TextStyle(
                                color: Color(0xFFB9B2D3),
                                fontSize: 15,
                                height: 1.5)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 26),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                      _pages.length,
                      (d) => AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 300),
                        margin:
                            const EdgeInsets.only(right: 8),
                        width: _i == d ? 34 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _i == d
                              ? const Color(0xFFFFB020)
                              : Colors.white24,
                          borderRadius:
                              BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      if (_i < 2) {
                        _pc.nextPage(
                            duration: const Duration(
                                milliseconds: 450),
                            curve: Curves.easeOutCubic);
                      } else {
                        widget.onDone();
                      }
                    },
                    child: AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB020),
                        borderRadius:
                            BorderRadius.circular(99),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFFFFB020)
                                  .withValues(alpha: 0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Text(
                          _i < 2 ? 'Next  â†’' : 'Start flowing  â†’',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF131022))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObData {
  final String kicker, title, body;
  final IconData icon;
  final Color c1, c2;
  const _ObData(
      {required this.kicker,
      required this.title,
      required this.body,
      required this.icon,
      required this.c1,
      required this.c2});
}
