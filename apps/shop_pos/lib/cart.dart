/// Cart domain logic, deliberately free of any Flutter import so it can be
/// unit-tested without a widget harness.
///
/// It exists because two of this project's rules are easy to violate inside a
/// widget tree and impossible to notice there:
///
/// 1. **Money is never a float.** `README.md` says so, and migration
///    `0001_immutable_ledgers` fails the build if any financial column becomes
///    a float. Accumulating `price * quantity` in a `double` would reintroduce
///    exactly the drift the database is guarding against — 0.1 + 0.2 !== 0.3
///    is the classic case, and a till that is off by a cent is a till that
///    cannot be reconciled at close of day. Every amount here is an `int` of
///    minor units (fielde): KES 65.00 is `6500`.
///
/// 2. **Stock is a hard constraint.** A POS must not be able to sell what the
///    shop does not have. Showing "24 left" while happily accepting 25 taps on
///    "+" is worse than useless: the oversell is discovered at stock-take, days
///    later, by someone who cannot explain it.
library;

/// Kenyan VAT rate. Stored per-business and per-product in the schema; this is
/// the default a shop starts with.
const int defaultVatRateBasisPoints = 1600; // 16.00%, in basis points

/// An amount of Kenyan shillings held as an integer number of minor units.
///
/// Integer-only by construction: there is no way to hold a fractional cent,
/// so rounding happens once, explicitly, at the points where it is defined.
class Money {
  const Money(this.minorUnits) : assert(minorUnits >= 0, 'a negative amount needs a sign');

  /// Builds an amount from a whole-shilling count, e.g. `Money.shillings(65)`.
  const Money.shillings(int whole) : minorUnits = whole * 100, assert(whole >= 0);

  final int minorUnits;

  bool get isZero => minorUnits == 0;

  /// Parses a major-unit string such as `"65.00"` or `"65"` into minor units.
  ///
  /// Goes through the *text* rather than a double on purpose. `double.parse("65.10")`
  /// cannot represent 65.10 exactly, and that error is inherited forever once
  /// the value becomes a subtotal. Splitting on the decimal point keeps every
  /// cent exactly as the cashier typed it.
  ///
  /// Throws [FormatException] on anything that is not a plain positive decimal,
  /// so a malformed price from an API fails loudly instead of becoming 0.00.
  factory Money.parse(String text) {
    final trimmed = text.trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(trimmed);
    if (match == null) {
      throw FormatException('Not a valid KES amount: "$text"', text);
    }
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return Money(whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction)));
  }

  /// Converts a double that arrived from JSON, rounding half away from zero.
  ///
  /// This is the single point where binary floating point is allowed to exist.
  /// Everything downstream is an integer.
  factory Money.fromDouble(double value) {
    return Money((value * 100).round());
  }

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);

  Money operator *(int quantity) {
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'must not be negative');
    return Money(minorUnits * quantity);
  }

  bool operator >(Money other) => minorUnits > other.minorUnits;

  /// Formats as major units with two decimals and thousands separators,
  /// e.g. `"1,234.50"`. Delegates to the shared token helper so the POS and
  /// the receipt cannot drift apart.
  String get formatted => _group(minorUnits);

  /// The VAT portion already contained in this VAT-inclusive amount.
  ///
  /// Kenyan retail displays VAT-inclusive shelf prices, so the total a customer
  /// pays already contains the tax. To report it we divide out, never add on:
  ///
  ///     net   = gross / (1 + rate)
  ///     vat   = gross - net
  ///
  /// This is the inverse of the usual "add tax on top" calculation and is the
  /// one that matches what the customer was actually charged. Worked in integer
  /// minor units so a 16% split of an odd number of cents still reconciles
  /// exactly: net + vat === gross, always.
  Money vatIncludedAt(int rateBasisPoints) {
    final divisor = 10000 + rateBasisPoints;
    // floor division: net is the tax-exclusive portion; VAT is the remainder,
    // so the two always re-add to the gross with no lost or invented cent.
    final net = (minorUnits * 10000) ~/ divisor;
    return Money(minorUnits - net);
  }

  static String _group(int minorUnits) {
    final whole = minorUnits ~/ 100;
    final cents = (minorUnits % 100).toString().padLeft(2, '0');
    final buf = StringBuffer();
    final digits = whole.toString();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    buf.write('.$cents');
    return buf.toString();
  }

  @override
  bool operator ==(Object other) => other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => 'KES $formatted';
}

/// Mirrors `PaymentMethod` in `apps/shop-api/prisma/schema.prisma`.
///
/// The POS must not offer methods the schema cannot store. `CARD` is
/// deliberately absent from both — see the comment on the schema enum and the
/// "Card payments" entry under Open items in the README: no third-party money
/// in flight for v1. Offering a Card button that writes a row the database
/// rejects would be a silent sale failure at the till.
enum SalePaymentMethod {
  cash('Cash', 'CASH'),
  mpesa('M-Pesa', 'MPESA'),
  credit('Credit', 'CREDIT');

  const SalePaymentMethod(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

/// One line in a sale: a product and how many of it the cashier wants.
class CartLine {
  CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.stock,
    this.quantity = 1,
  }) : assert(quantity > 0, 'a line must request at least one unit');

  final String productId;
  final String name;

  /// Unit price in minor units. Held as [Money], never a double.
  final Money unitPrice;

  /// Units the shop actually has on the shelf.
  final int stock;

  int quantity;

  Money get lineTotal => unitPrice * quantity;

  /// Units still available before hitting the shelf count.
  int get remaining => stock - quantity;

  bool get isAtStockLimit => quantity >= stock;
}

/// A sale being assembled. Owns the rules the grid of buttons must obey.
///
/// Deliberately holds no widget references, so the logic that decides whether a
/// till can oversell is testable directly rather than only through taps.
class Cart {
  final Map<String, CartLine> _lines = {};

  /// Why the UI shows a refusal. Named so tests assert on intent, not prose.
  static const String outOfStock = 'No stock left for this item.';
  static const String alreadyComplete = 'Only part of this quantity is in stock.';

  Iterable<CartLine> get lines => _lines.values;
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  /// Units the customer walks away with — not the number of distinct lines.
  int get itemCount => _lines.values.fold(0, (sum, line) => sum + line.quantity);

  /// VAT-exclusive value of the basket.
  Money get subtotal => _lines.values.fold(const Money(0), (sum, line) => sum + line.lineTotal);

  /// The Kenyan VAT already inside that shelf price.
  Money get vatAmount => subtotal.vatIncludedAt(defaultVatRateBasisPoints);

  void clear() => _lines.clear();

  void remove(String productId) => _lines.remove(productId);

  /// True when there is something to charge and every line is within stock.
  ///
  /// Checked before the payment prompt rather than after, so an oversell is
  /// caught at the button instead of at the ledger.
  bool get canCheckout =>
      isNotEmpty && _lines.values.every((line) => line.quantity <= line.stock && line.quantity > 0);
  /// Changes a line's quantity by [delta]. Negative deltas remove units.
  ///
  /// Clamped rather than trusted: a held-down `+`, a double-tap, or a stale
  /// widget can all request more than exists. Going to zero or below drops the
  /// line entirely — a zero-quantity line would render as "0 × item" and leave
  /// checkout believing the basket had content.
  void changeQuantity(String productId, int delta, {void Function(String reason)? onRefused}) {
    final line = _lines[productId];
    if (line == null) return;

    if (delta > 0 && line.quantity + delta > line.stock) {
      // Refuse the whole jump instead of silently topping up to stock: a
      // cashier who pressed + three times should not get two of them.
      onRefused?.call(alreadyComplete);
      return;
    }

    final next = line.quantity + delta;
    if (next <= 0) {
      _lines.remove(productId);
    } else {
      line.quantity = next;
    }
  }


  /// Adds one unit, refusing to exceed what is on the shelf.
  ///
  /// Returns `true` if the basket changed. Returns `false` — changing nothing —
  /// when the cashier already has every unit in stock. That guard is what keeps
  /// a label reading "24 left" from ever going negative underneath it.
  ///
  /// [onRefused] tells the caller *why*. Without it a guard is
  /// indistinguishable from a button that stopped working.
  bool add(CartLine incoming, {void Function(String reason)? onRefused}) {
    final existing = _lines[incoming.productId];
    if (existing != null) {
      if (existing.isAtStockLimit) {
        onRefused?.call(existing.stock <= 0 ? outOfStock : alreadyComplete);
        return false;
      }
      existing.quantity++;
      return true;
    }
    if (incoming.stock <= 0) {
      onRefused?.call(outOfStock);
      return false;
    }
    _lines[incoming.productId] = CartLine(
      productId: incoming.productId,
      name: incoming.name,
      unitPrice: incoming.unitPrice,
      stock: incoming.stock,
      quantity: 1,
    );
    return true;
  }
}

