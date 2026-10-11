import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/views/mpesa_integration_view.dart';

void main() {
  testWidgets('M-Pesa overview states clearly that Daraja is not connected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MpesaIntegrationView()));

    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.text(
        'Daraja is not connected. No M-Pesa payments are being initiated or verified.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup preview masks credentials and cannot save or test yet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MpesaIntegrationView()));
    await tester.tap(find.text('M-Pesa setup'));
    await tester.pumpAndSettle();

    expect(find.text('Paybill or Till number'), findsOneWidget);
    expect(find.text('Consumer key'), findsOneWidget);
    expect(find.text('Consumer secret'), findsOneWidget);
    expect(find.text('Lipa Na M-Pesa passkey'), findsOneWidget);
    await tester.ensureVisible(find.text('Consumer secret'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.obscureText,
      ),
      findsNWidgets(3),
    );
    await tester.ensureVisible(find.text('Save configuration'));
    await tester.pumpAndSettle();
    final saveButton = find.ancestor(
      of: find.text('Save configuration'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    final testButton = find.ancestor(
      of: find.text('Test connection'),
      matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(testButton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transactions and reconciliation show explicit unavailable states',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: MpesaIntegrationView()));
      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();
      expect(find.text('Transaction history is not connected'), findsOneWidget);

      await tester.tap(find.text('Reconciliation'));
      await tester.pumpAndSettle();
      expect(find.text('Callback activity'), findsOneWidget);
      expect(
        find.textContaining('No callback endpoint is active.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
