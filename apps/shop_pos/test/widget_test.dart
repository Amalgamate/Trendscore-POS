import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shop_pos/cart.dart';
import 'package:shop_pos/main.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/views/inventory_view.dart';

/// Checkout smoke tests.
///
/// The counter test that shipped with `flutter create` referenced a `MyApp`
/// class that stopped existing the moment the POS replaced it, so it was red
/// from the day it was written.
///
/// These run at 1440x900 rather than the framework's 800x600 default: the POS
/// targets a desktop till, and at 800x600 the layout switches to its compact
/// mode, which gives the catalogue grid too little height to render a single
/// product. Testing there would assert on a screen no cashier ever sees.
void main() {
  Future<void> pumpPos(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = PosState(includeDemoProducts: true);
    // A configured shop code takes the shell past first-run shop setup.
    state.serverUrl = 'http://localhost:4000';
    state.currentLoggedInUser = state.users.first;
    await tester.pumpWidget(RetailPosApp(state: state));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('checkout screen renders its core affordances', (
    WidgetTester tester,
  ) async {
    await pumpPos(tester);

    // The cashier must be able to find a product...
    expect(find.byType(TextField), findsNWidgets(2));

    // ...the basket has a clear empty state and cannot be charged yet.
    expect(find.text('Current Sale'), findsOneWidget);
    expect(find.text('0 items in basket'), findsOneWidget);
    expect(find.textContaining('CHARGE KES'), findsOneWidget);

    // The catalogue actually renders goods to sell.
    expect(find.text('Fresh milk 500ml'), findsOneWidget);
  });

  testWidgets('tapping a product adds it to the basket', (
    WidgetTester tester,
  ) async {
    await pumpPos(tester);

    await tester.tap(find.text('Fresh milk 500ml'));
    await tester.pump();

    // The product now appears twice — once as the catalogue card, once as a
    // basket line — which is exactly what "added" means.
    expect(find.text('Fresh milk 500ml'), findsNWidgets(2));
    expect(find.textContaining('CHARGE KES'), findsOneWidget);
    expect(find.text('0 items in basket'), findsNothing);
  });

  testWidgets('measured product flows through quantity, payment and receipt', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = PosState(includeDemoProducts: true)
      ..serverUrl = 'http://localhost:4000';
    state.currentLoggedInUser = state.users.first;
    state.products = [
      state.products.first.copyWith(
        id: 'ui-test-measured-oil',
        name: 'TEST UI cooking oil',
        unit: 'l',
        unitPrice: Money.parse('300.00'),
        stock: 20,
        quickQuantityPresets: ['250 ml'],
      ),
    ];

    await tester.pumpWidget(RetailPosApp(state: state));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST UI cooking oil'));
    await tester.pumpAndSettle();
    expect(find.text('Sell TEST UI cooking oil'), findsOneWidget);

    await tester.tap(find.text('250 ml'));
    await tester.enterText(find.byType(TextField).last, '125');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(state.cart.lines.single.lineTotal, Money.parse('37.50'));
    expect(find.textContaining('125 ml'), findsWidgets);

    await tester.tap(find.textContaining('CHARGE KES'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash Tender'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Amina Wanjiku');
    await tester.tap(find.text('Confirm Cash Payment'));
    await tester.pumpAndSettle();

    expect(find.text('Payment Approved'), findsOneWidget);
    expect(find.textContaining('Amina Wanjiku'), findsOneWidget);
    expect(find.textContaining('125 ml'), findsWidgets);
    expect(state.products.single.stock, 19.875);
    expect(state.salesLedger.single.subtotal, Money.parse('37.50'));
    expect(state.salesLedger.single.items.single.unit, 'ml');
  });

  testWidgets('inventory and product editor fit a compact phone screen', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final size in [const Size(360, 800), const Size(320, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryView(state: PosState(includeDemoProducts: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Inventory at $size');
      expect(find.text('Inventory'), findsOneWidget);

      await tester.tap(find.byTooltip('Add product'));
      await tester.pumpAndSettle();
      expect(find.text('Create product'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Product editor at $size');

      await tester.tap(find.byTooltip('Back to products'));
      await tester.pumpAndSettle();
    }
  });
}
