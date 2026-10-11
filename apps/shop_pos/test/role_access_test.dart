import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/main.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/views/settings_view.dart';

void main() {
  Future<void> pumpAsRole(
    WidgetTester tester,
    PosUserRole role, {
    Size size = const Size(1920, 911),
  }) async {
    tester.view.physicalSize = size;
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
      'Online Orders',
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
    expect(find.byTooltip('Storefront'), findsNothing);
    expect(find.byTooltip('Integrations'), findsNothing);

    await tester.tap(find.byTooltip('Profile, settings, and sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Storefront'), findsOneWidget);
    expect(find.text('M-Pesa'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Lock and sign out'), findsOneWidget);
  });

  test('cashiers can access online orders but stock clerks cannot', () {
    expect(accessibleTabsFor(PosUserRole.cashier).contains(10), isTrue);
    expect(accessibleTabsFor(PosUserRole.stockClerk).contains(10), isFalse);
    expect(accessibleTabsFor(PosUserRole.cashier).contains(11), isFalse);
    expect(accessibleTabsFor(PosUserRole.owner).contains(11), isTrue);
    expect(accessibleTabsFor(PosUserRole.manager).contains(11), isTrue);
    expect(accessibleTabsFor(PosUserRole.superAdmin).contains(11), isTrue);
  });

  testWidgets('authorized staff can open M-Pesa from the profile dropdown', (
    tester,
  ) async {
    await pumpAsRole(tester, PosUserRole.manager);

    await tester.tap(find.byTooltip('Profile, settings, and sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M-Pesa'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Daraja is not connected. No M-Pesa payments are being initiated or verified.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Integrations'), findsNothing);
  });

  testWidgets(
    'authorized staff can open Storefront from the profile dropdown',
    (tester) async {
      await pumpAsRole(tester, PosUserRole.manager);

      await tester.tap(find.byTooltip('Profile, settings, and sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Storefront'));
      await tester.pumpAndSettle();

      expect(find.text('Storefront settings'), findsOneWidget);
    },
  );

  testWidgets('managers can open Integrations from compact navigation', (
    tester,
  ) async {
    await pumpAsRole(tester, PosUserRole.manager, size: const Size(390, 844));

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Integrations'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Daraja is not connected. No M-Pesa payments are being initiated or verified.',
      ),
      findsOneWidget,
    );
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
