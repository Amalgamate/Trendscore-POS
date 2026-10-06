import 'package:flutter_test/flutter_test.dart';

import 'package:shop_pos/cart.dart';

void main() {
  CartLine milk({int stock = 3, String price = '65.00'}) => CartLine(
        productId: 'milk',
        name: 'Fresh milk 500ml',
        unitPrice: Money.parse(price),
        stock: stock,
      );

  group('Money', () {
    test('parses shillings and cents as exact integers', () {
      expect(Money.parse('65.00').minorUnits, 6500);
      expect(Money.parse('65').minorUnits, 6500);
      expect(Money.parse('0.50').minorUnits, 50);
    });

    test('rejects malformed amounts rather than coercing them to zero', () {
      // A price the API cannot parse must fail loudly. Falling back to 0.00
      // would quietly sell stock for free.
      expect(() => Money.parse('12.345'), throwsFormatException);
      expect(() => Money.parse(''), throwsFormatException);
      expect(() => Money.parse('-5.00'), throwsFormatException);
    });

    test('never loses a cent to binary floating point', () {
      // 0.1 + 0.2 != 0.3 in double arithmetic — the classic drift that makes a
      // till disagree with its own drawer. Integer cents cannot do this.
      final sum = Money.parse('0.10') + Money.parse('0.20');
      expect(sum.minorUnits, 30);
      expect(sum.formatted, '0.30');
    });

    test('multiplies a line without rounding', () {
      expect((Money.parse('480.00') * 3).formatted, '1,440.00');
    });

    test('formats with grouping and exactly two decimals', () {
      expect(Money.parse('1234567.89').formatted, '1,234,567.89');
      expect(Money.parse('900').formatted, '900.00');
    });

    test('divides VAT back out of an inclusive shelf price', () {
      // Shelves in Kenya show tax-inclusive prices, so the VAT is contained
      // in what the customer paid and must be extracted, never added.
      final gross = Money.parse('116.00');
      final vat = gross.vatIncludedAt(1600);
      expect(vat.minorUnits, 1600);

      // The split must re-add to the gross exactly — no cent invented or lost.
      // A tautology (a - v + v == a) would prove nothing, so assert on the
      // two independently derived halves.
      final net = gross.minorUnits - vat.minorUnits;
      expect(net + vat.minorUnits, gross.minorUnits);
      expect(net, 10000); // 116.00 gross at 16% is 100.00 net
    });

    test('VAT split reconciles for odd totals', () {
      // 16% of 100.00 is not whole cents. floor() on the net portion means the
      // remainder lands in VAT, so net + vat re-adds to the gross exactly:
      //   net = floor(10000 * 10000 / 11600) = 8620
      //   vat = 10000 - 8620                 = 1380
      final gross = Money.parse('100.00');
      final vat = gross.vatIncludedAt(1600);
      expect(vat.minorUnits, 1380);
      expect(gross.minorUnits - vat.minorUnits, 8620);
    });
  });
  group('Cart stock enforcement', () {
    test('adds an in-stock product and counts the unit', () {
      final cart = Cart();
      expect(cart.add(milk()), isTrue);
      expect(cart.itemCount, 1);
      expect(cart.lines.single.quantity, 1);
    });

    test('refuses to sell stock the shop does not have', () {
      final cart = Cart();
      final shortStock = milk(stock: 2);

      cart.add(shortStock);
      cart.add(shortStock);
      expect(cart.itemCount, 2);

      // The third tap must change nothing. Before this guard the header badge
      // kept counting past the shelf count and the oversell surfaced days
      // later at stock-take, unexplained.
      String? reason;
      expect(cart.add(shortStock, onRefused: (r) => reason = r), isFalse);
      expect(cart.itemCount, 2);
      expect(reason, Cart.alreadyComplete);
    });

    test('refuses a product with zero stock and explains why', () {
      final cart = Cart();
      String? reason;
      expect(cart.add(milk(stock: 0), onRefused: (r) => reason = r), isFalse);
      expect(cart.isEmpty, isTrue);
      expect(reason, Cart.outOfStock);
    });

    test('clamps an increase that would exceed stock', () {
      final cart = Cart();
      final line = milk(stock: 2);
      cart.add(line);
      cart.add(line);

      String? reason;
      cart.changeQuantity('milk', 1, onRefused: (r) => reason = r);

      // The whole jump is refused rather than silently topping up to stock:
      // a cashier who pressed + twice should not end up with three of them.
      expect(cart.lines.single.quantity, 2);
      expect(reason, Cart.alreadyComplete);
    });

    test('drops the line entirely when quantity reaches zero', () {
      final cart = Cart();
      final line = milk();
      cart.add(line);

      cart.changeQuantity('milk', -1);
      expect(cart.isEmpty, isTrue);
      // A leftover zero-quantity line would read as "0 × item" and still
      // make the basket look non-empty.
      expect(cart.lines, isEmpty);
    });

    test('clear empties the whole basket', () {
      final cart = Cart();
      cart.add(milk());
      cart.add(CartLine(productId: 'bread', name: 'White bread', unitPrice: Money.parse('75.00'), stock: 18));
      expect(cart.itemCount, 2);

      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.itemCount, 0);
    });
  });

  group('Cart totals', () {
    test('sums lines in integer minor units', () {
      final cart = Cart();
      final line = milk();
      cart.add(line);
      cart.changeQuantity('milk', 1); // two at 65.00

      expect(cart.subtotal.minorUnits, 13000);
      expect(cart.subtotal.formatted, '130.00');
    });

    test('reports the Kenyan VAT contained in the basket', () {
      final cart = Cart();
      cart.add(milk()); // 65.00 inclusive at 16%
      expect(cart.vatAmount.minorUnits, 897);
    });

    test('counts units, not distinct lines', () {
      final cart = Cart();
      final line = milk(stock: 5);
      cart.add(line);
      cart.add(line);
      cart.add(line);
      expect(cart.lines.length, 1);
      expect(cart.itemCount, 3);
    });

    test('blocks checkout on an empty basket', () {
      // Nothing to charge means the payment prompt must never open.
      expect(Cart().canCheckout, isFalse);
    });

    test('allows checkout for a basket within stock', () {
      final cart = Cart();
      cart.add(milk(stock: 3));
      expect(cart.canCheckout, isTrue);
    });

    test('the payment methods offered are the ones the schema can store', () {
      // The schema enum is CASH | MPESA | CREDIT, with card deliberately
      // absent in v1. A Card button here would write a row Postgres rejects.
      expect(SalePaymentMethod.values.map((m) => m.apiValue),
          ['CASH', 'MPESA', 'CREDIT']);
      expect(SalePaymentMethod.values.map((m) => m.label), ['Cash', 'M-Pesa', 'Credit']);
    });
  });
}
