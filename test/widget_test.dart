import 'package:donato_valerie/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('navigates operations sections', (tester) async {
    final store = await _testStore();

    await tester.pumpWidget(DonatoValerieApp(store: store));

    expect(find.text('Operations desk'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Add Interview'), findsOneWidget);

    await tester.tap(find.text('Gear'));
    await tester.pumpAndSettle();
    expect(find.text('Checkout'), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Compliance reporting'), findsOneWidget);
  });

  testWidgets('shows a newly added equipment checkout record', (tester) async {
    final store = await _testStore();

    await tester.pumpWidget(DonatoValerieApp(store: store));
    await tester.tap(find.text('Gear'));
    await tester.pumpAndSettle();

    await store.add(
      const OperationRecord(
        id: 'test-equipment',
        kind: RecordKind.equipment,
        title: 'Radio DV-44',
        subtitle: 'North team',
        owner: 'Ops desk',
        schedule: 'Return Monday',
        status: 'Checked out',
        secondary: 'Ready kit',
        notes: 'Checked locally before release.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Radio DV-44'), findsOneWidget);
  });
}

Future<OperationsStore> _testStore() async {
  SharedPreferences.setMockInitialValues({});
  return OperationsStore.load();
}
