import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/views/social_commerce_view.dart';
import 'package:shop_pos/views/website_builder_view.dart';

void main() {
  testWidgets('website builder shows a retry when settings cannot load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebsiteBuilderView(state: PosState())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Storefront settings'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('social commerce identifies channels and approval states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SocialCommerceView())),
    );

    expect(find.text('Facebook & Instagram'), findsOneWidget);
    expect(find.text('WhatsApp Business'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('App review required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
