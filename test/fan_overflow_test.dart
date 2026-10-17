import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chobiflow/models.dart';
import 'package:chobiflow/widgets/flow_widgets.dart';

void main() {
  testWidgets('FanStack placeholder at fan-card width has no overflow',
      (tester) async {
    final shot = ShotItem(
      id: 'd1',
      title: 'Some demo title text',
      collectionId: 'recent',
      createdAt: DateTime.now(),
      tags: const ['auto'],
      gradientSeed: 1,
      kind: 'note',
    );
    bool overflowed = false;
    FlutterError.onError = (details) {
      overflowed = true;
      debugPrint('OVERFLOW DETAILS: ${details.exceptionAsString()}');
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 92,
            child: FanStack(shots: [shot], accent: const Color(0xFF5B2EEE)),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    if (overflowed) fail('FanStack overflowed at fan-card width');
  });
}
