import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/cart.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/views/receipt_dialog.dart';

SaleRecord sampleSale({String? customerName}) => SaleRecord(
  receiptNumber: 'REC-TEST-0001',
  timestamp: DateTime(2026, 11, 3, 10),
  cashier: 'Test Cashier',
  items: const [],
  subtotal: const Money.shillings(100),
  vatAmount: const Money(1379),
  paymentMethod: SalePaymentMethod.cash,
  paymentReference: 'CASH',
  customerName: customerName,
);

void main() {
  Future<void> pumpReceipt(
    WidgetTester tester, {
    String? customerName,
    bool showCustomerName = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = PosState(includeDemoProducts: false)
      ..showCustomerNameOnReceipt = showCustomerName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptDialog(
            sale: sampleSale(customerName: customerName),
            onNewSale: () {},
            state: state,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('thermal receipt shows a saved customer name when enabled', (
    tester,
  ) async {
    await pumpReceipt(tester, customerName: 'Grace Njeri');

    expect(find.text('Customer: Grace Njeri'), findsOneWidget);
  });

  testWidgets('receipt omits the customer section when the setting is off', (
    tester,
  ) async {
    await pumpReceipt(
      tester,
      customerName: 'Grace Njeri',
      showCustomerName: false,
    );

    expect(find.text('Customer: Grace Njeri'), findsNothing);
    await tester.tap(find.text('A4 Invoice'));
    await tester.pumpAndSettle();
    expect(find.text('Billed To / Customer:'), findsNothing);
  });

  testWidgets('receipt omits an empty customer name', (tester) async {
    await pumpReceipt(tester);

    expect(find.textContaining('Customer:'), findsNothing);
    expect(find.text('Billed To / Customer:'), findsNothing);
  });

  testWidgets('long customer names stay within thermal and A4 receipts', (
    tester,
  ) async {
    const longName =
        'Customer Name With A Very Long Family Name And Additional Details '
        'To Verify Receipt Wrapping On Narrow Paper';
    await pumpReceipt(tester, customerName: longName);

    expect(find.textContaining('Customer:'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('A4 Invoice'));
    await tester.pumpAndSettle();
    expect(find.text('Billed To / Customer:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
