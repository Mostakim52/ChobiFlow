import 'package:chobiflow/flow_store.dart';
import 'package:chobiflow/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ChobiFlow boots to splash then content',
      (WidgetTester tester) async {
    final store = FlowStore();
    await tester.pumpWidget(
        ChobiFlowApp(store: store, seenOnboarding: true));
    await tester.pump(const Duration(milliseconds: 100));
    // Either splash (ChobiFlow) or home (Screenshot) should appear
    expect(
        find.textContaining('ChobiFlow').evaluate().isNotEmpty ||
            find.textContaining('Screenshot').evaluate().isNotEmpty,
        true);
  });
}
