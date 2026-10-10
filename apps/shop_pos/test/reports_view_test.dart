import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/views/reports_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports stay list-based on a mobile-sized screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ReportsView(state: PosState(includeDemoProducts: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gross sales'), findsOneWidget);
    expect(find.text('Payment totals'), findsOneWidget);
    expect(find.byTooltip('Export to Excel'), findsOneWidget);
    expect(find.text('Revenue by Hour'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(find.text('Product performance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop reports show a labeled Excel export action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ReportsView(state: PosState(includeDemoProducts: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Cash Flow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
