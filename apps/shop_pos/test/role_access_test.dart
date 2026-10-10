import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/main.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/views/settings_view.dart';

void main() {
  Future<void> pumpAsRole(WidgetTester tester, PosUserRole role) async {
    tester.view.physicalSize = const Size(1920, 911);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = PosState(includeDemoProducts: true)
      ..serverUrl = 'http://localhost:4001'
      ..savedTabIndex = 2
      ..currentLoggedInUser = PosUser(
        id: 'test-user',
        fullName: 'Test Staff',
        phone: '254700000000',
        role: role,
      );
    await tester.pumpWidget(RetailPosApp(state: state));
    await tester.pump();
  }

  testWidgets('managers can open Profile but not Settings', (tester) async {
    await pumpAsRole(tester, PosUserRole.manager);

    expect(find.text('Credit'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    final navigationViewport = tester.getRect(
      find.byKey(const ValueKey('sidebar-navigation-scroll-view')),
    );
    expect(
      navigationViewport.height,
      greaterThan(600),
      reason: 'the navigation should use the available sidebar height',
    );
    for (final label in [
      'POS',
      'Sales',
      'Stock',
      'Orders',
      'Delivery',
      'Credit',
      'Till',
      'Reports',
    ]) {
      expect(
        find.byTooltip(label).hitTestable(),
        findsOneWidget,
        reason: '$label should be visible without scrolling the sidebar',
      );
    }

    await tester.tap(find.byTooltip('Profile, settings, and sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Lock and sign out'), findsOneWidget);
  });

  testWidgets('owners can open Profile and Settings from the avatar menu', (
    tester,
  ) async {
    await pumpAsRole(tester, PosUserRole.owner);

    expect(find.text('Settings'), findsNothing);
    expect(find.text('Staff'), findsNothing);

    await tester.tap(find.byTooltip('Profile, settings, and sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Lock and sign out'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Test Staff'), findsNWidgets(2));
    expect(find.text('254700000000'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile, settings, and sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
  });
}
