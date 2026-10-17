import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chobi_theme.dart';
import 'flow_store.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  final store = FlowStore();
  final seen = await FlowStore.seenOnboarding();
  runApp(ChobiFlowApp(store: store, seenOnboarding: seen));
}

class ChobiFlowApp extends StatelessWidget {
  final FlowStore store;
  final bool seenOnboarding;
  const ChobiFlowApp(
      {super.key, required this.store, required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (c, _) {
        final mode = store.themeMode;
        // Splash while loading
        if (!store.loaded) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF131022),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(colors: [
                          Color(0xFFFFB020),
                          Color(0xFF2DD4BF)
                        ]),
                      ),
                      child: const Center(
                          child: Text('CF',
                              style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white))),
                    ),
                    const SizedBox(height: 16),
                    const Text('ChobiFlow',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 24)),
                    const SizedBox(height: 8),
                    const SizedBox(
                      width: 160,
                      child: LinearProgressIndicator(
                        color: Color(0xFFFFB020),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return MaterialApp(
          title: 'ChobiFlow',
          debugShowCheckedModeBanner: false,
          theme: ChobiTheme.light(),
          darkTheme: ChobiTheme.dark(),
          themeMode: mode,
          home: seenOnboarding
              ? HomeShell(store: store)
              : Onboarding(onDone: () async {
                  await FlowStore.setSeenOnboarding();
                  // Rebuild with onboarding seen by pushing replacement:
                  // simplest: recreate via navigator
                  runApp(ChobiFlowApp(store: store, seenOnboarding: true));
                }),
        );
      },
    );
  }
}
