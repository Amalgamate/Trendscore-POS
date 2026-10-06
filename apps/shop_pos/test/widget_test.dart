import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shop_pos/main.dart';
import 'package:shop_pos/pos_state.dart';

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
    final state = PosState();
    state.currentLoggedInUser = state.users.first;
    await tester.pumpWidget(RetailPosApp(state: state));
    await tester.pump();
  }

  testWidgets('checkout screen renders its core affordances', (WidgetTester tester) async {
    await pumpPos(tester);

    // The cashier must be able to find a product...
    expect(find.byType(TextField), findsOneWidget);

    // ...and an empty basket cannot be charged: the button reads as a prompt
    // rather than quoting an amount nobody has added up yet.
    expect(find.text('Add items to continue'), findsOneWidget);
    expect(find.textContaining('Charge KES'), findsNothing);

    // The catalogue actually renders goods to sell.
    expect(find.text('Fresh milk 500ml'), findsOneWidget);
  });

  testWidgets('tapping a product adds it to the basket', (WidgetTester tester) async {
    await pumpPos(tester);

    await tester.tap(find.text('Fresh milk 500ml'));
    await tester.pump();

    // The product now appears twice — once as the catalogue card, once as a
    // basket line — which is exactly what "added" means.
    expect(find.text('Fresh milk 500ml'), findsNWidgets(2));
    expect(find.textContaining('Charge KES'), findsOneWidget);
    expect(find.text('Add items to continue'), findsNothing);
  });
}


