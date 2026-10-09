import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/main.dart';
import 'package:shop_pos/pos_state.dart';

void main() {
  Future<void> pumpAsRole(WidgetTester tester, PosUserRole role) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = PosState(includeDemoProducts: true)
      ..currentLoggedInUser = PosUser(
        id: 'test-user',
        fullName: 'Test Staff',
        phone: '254700000000',
        role: role,
      );
    await tester.pumpWidget(RetailPosApp(state: state));
    await tester.pump();
  }

  testWidgets('managers see Staff Management but not Settings', (tester) async {
    await pumpAsRole(tester, PosUserRole.manager);

    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();

    expect(find.text('Staff Management'), findsOneWidget);
    expect(find.text('Add Staff Member'), findsOneWidget);
  });

  testWidgets('owners see Settings but not the separate Staff module', (tester) async {
    await pumpAsRole(tester, PosUserRole.owner);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Staff'), findsNothing);
  });
}
