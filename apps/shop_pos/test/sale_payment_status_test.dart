import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/cart.dart';
import 'package:shop_pos/pos_state.dart';

void main() {
  Map<String, dynamic> saleWithPayment(
    Map<String, dynamic> payment, {
    String id = 'sale-1',
  }) => {
    'id': id,
    'receiptNumber': 'REC-TEST-0001',
    'status': 'COMPLETED',
    'subtotal': 100,
    'vatAmount': 13.79,
    'createdAt': '2026-10-10T10:00:00.000Z',
    'items': <Map<String, dynamic>>[],
    'payments': <Map<String, dynamic>>[payment],
  };

  test('pending M-Pesa sale exposes its ID, reference and pending status', () {
    final sale = SaleRecord.fromApi(
      saleWithPayment({
        'method': 'MPESA',
        'status': 'PENDING',
        'reference': 'TILL: 123456',
        'amount': 100,
      }),
    );

    expect(sale.saleId, 'sale-1');
    expect(sale.paymentMethod, SalePaymentMethod.mpesa);
    expect(sale.paymentReference, 'TILL: 123456');
    expect(sale.paymentPending, isTrue);
  });

  test('reconciled M-Pesa sale ignores its superseded pending payment', () {
    final json = saleWithPayment({
      'method': 'MPESA',
      'status': 'REVERSED',
      'reference': 'TILL: 123456',
    });
    (json['payments'] as List<Map<String, dynamic>>).add({
      'method': 'MPESA',
      'status': 'SUCCESS',
      'reference': 'QGH7X2P9',
      'amount': 100,
    });

    final sale = SaleRecord.fromApi(json);

    expect(sale.paymentMethod, SalePaymentMethod.mpesa);
    expect(sale.paymentReference, 'QGH7X2P9');
    expect(sale.paymentPending, isFalse);
  });

  test('cash payment details survive loading from the API', () {
    final sale = SaleRecord.fromApi(
      saleWithPayment({
        'method': 'CASH',
        'status': 'SUCCESS',
        'reference': 'CASH',
        'amount': 100,
        'cashTendered': 120,
        'changeDue': 20,
      }),
    );

    expect(sale.cashTendered?.minorUnits, 12000);
    expect(sale.changeDue?.minorUnits, 2000);
  });
}
