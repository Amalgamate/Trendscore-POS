import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'cart.dart';
import 'theme/tokens.dart';

/// Error with a message that is safe to show to the cashier as-is.
class PosException implements Exception {
  PosException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Icons a shop owner can pick for a category.
const Map<String, IconData> kCategoryIcons = {
  'box': Icons.inventory_2_outlined,
  'dairy': Icons.egg_outlined,
  'bakery': Icons.bakery_dining,
  'drink': Icons.local_drink_outlined,
  'produce': Icons.eco_outlined,
  'snack': Icons.fastfood_outlined,
  'home': Icons.home_outlined,
  'grain': Icons.grass_outlined,
  'health': Icons.health_and_safety_outlined,
  'clean': Icons.cleaning_services_outlined,
  'meat': Icons.set_meal_outlined,
  'basket': Icons.shopping_basket_outlined,
  'baby': Icons.child_care_outlined,
  'pet': Icons.pets_outlined,
  'tool': Icons.build_outlined,
  'beauty': Icons.spa_outlined,
};

/// Soft tint colours a shop owner can pick for a category.
const List<int> kCategoryColors = [
  0xFFEFF6FF, 0xFFFFFBEB, 0xFFF0FDF4, 0xFFFFF7ED, 0xFFF5F3FF, 0xFFFEFCE8,
  0xFFFFEFF2, 0xFFEEF2FF, 0xFFECFEFF, 0xFFFDF2F8, 0xFFF7FEE7, 0xFFF8FAFC,
];

/// A shop-defined product category.
class PosCategory {
  PosCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    this.iconKey = 'box',
  });

  final String id;
  String name;
  int colorValue;
  String iconKey;

  Color get color => Color(colorValue);
  IconData get icon => kCategoryIcons[iconKey] ?? Icons.inventory_2_outlined;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'icon': iconKey,
      };

  factory PosCategory.fromJson(Map<String, dynamic> json) => PosCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        colorValue: json['color'] as int? ?? 0xFFF8FAFC,
        iconKey: json['icon'] as String? ?? 'box',
      );
}

/// A product in the shop catalog.
///
/// A product with variants (e.g. milk in 500ml / 1L / 5L) is stored as several
/// PosProduct rows that share a [groupId]. Every variant is a real, separately
/// sellable item with its own SKU, barcode, price and stock, so the cart, sales
/// ledger, receipts and reports keep working per productId.
class PosProduct {
  PosProduct({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode,
    required this.category,
    required this.unitPrice,
    this.costPrice,
    required this.stock,
    this.lowStockThreshold = 10,
    required this.icon,
    required this.tint,
    this.taxRateBasisPoints = defaultVatRateBasisPoints,
    this.isActive = true,
    this.notes,
    this.imageBase64,
    this.groupId,
    this.variantLabel,
  });

  final String id;
  String name;
  String sku;
  String? barcode;
  String category;
  Money unitPrice;
  Money? costPrice;
  int stock;
  int lowStockThreshold;
  final IconData icon;
  final Color tint;
  final int taxRateBasisPoints;
  bool isActive;
  String? notes;
  /// Base64-encoded 1:1 JPEG product image (data URI), or null if none.
  String? imageBase64;

  /// Shared by all variants of one product; null for a standalone product.
  String? groupId;

  /// e.g. "500ml", "Strawberry", "6-pack". Null for a standalone product.
  String? variantLabel;

  /// Name shown on receipts and in the basket, e.g. "Fresh milk · 500ml".
  String get displayName =>
      (variantLabel == null || variantLabel!.isEmpty) ? name : '$name · $variantLabel';

  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock > 0 && stock <= lowStockThreshold;

  double? get marginPercent {
    if (costPrice == null || costPrice!.minorUnits == 0) return null;
    return ((unitPrice.minorUnits - costPrice!.minorUnits) / costPrice!.minorUnits) * 100;
  }

  PosProduct copyWith({
    String? id,
    String? name,
    String? sku,
    String? barcode,
    String? category,
    Money? unitPrice,
    Money? costPrice,
    int? stock,
    int? lowStockThreshold,
    IconData? icon,
    Color? tint,
    int? taxRateBasisPoints,
    bool? isActive,
    String? notes,
    Object? imageBase64 = _sentinel,
    Object? groupId = _sentinel,
    Object? variantLabel = _sentinel,
  }) {
    return PosProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      stock: stock ?? this.stock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      icon: icon ?? this.icon,
      tint: tint ?? this.tint,
      taxRateBasisPoints: taxRateBasisPoints ?? this.taxRateBasisPoints,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      imageBase64: imageBase64 == _sentinel ? this.imageBase64 : (imageBase64 as String?),
      groupId: groupId == _sentinel ? this.groupId : (groupId as String?),
      variantLabel: variantLabel == _sentinel ? this.variantLabel : (variantLabel as String?),
    );
  }

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sku': sku,
    'barcode': barcode,
    'category': category,
    'unitPriceMinor': unitPrice.minorUnits,
    'costPriceMinor': costPrice?.minorUnits,
    'stock': stock,
    'lowStockThreshold': lowStockThreshold,
    'iconCode': icon.codePoint,
    'iconFontFamily': icon.fontFamily,
    'tint': tint.toARGB32(),
    'taxRateBasisPoints': taxRateBasisPoints,
    'isActive': isActive,
    'notes': notes,
    'imageBase64': imageBase64,
    'groupId': groupId,
    'variantLabel': variantLabel,
  };

  factory PosProduct.fromJson(Map<String, dynamic> json) => PosProduct(
    id: json['id'] as String,
    name: json['name'] as String,
    sku: json['sku'] as String,
    barcode: json['barcode'] as String?,
    category: json['category'] as String,
    unitPrice: Money(json['unitPriceMinor'] as int? ?? 0),
    costPrice: json['costPriceMinor'] != null ? Money(json['costPriceMinor'] as int) : null,
    stock: json['stock'] as int? ?? 0,
    lowStockThreshold: json['lowStockThreshold'] as int? ?? 10,
    icon: _iconFromCode(json['iconCode'] as int?),
    tint: Color(json['tint'] as int? ?? 0xFFF1F5F9),
    taxRateBasisPoints: json['taxRateBasisPoints'] as int? ?? defaultVatRateBasisPoints,
    isActive: json['isActive'] as bool? ?? true,
    notes: json['notes'] as String?,
    imageBase64: json['imageBase64'] as String?,
    groupId: json['groupId'] as String?,
    variantLabel: json['variantLabel'] as String?,
  );

  static IconData _iconFromCode(int? code) {
    if (code == null) return Icons.inventory_2_outlined;
    for (final icon in kCategoryIcons.values) {
      if (icon.codePoint == code) return icon;
    }
    switch (code) {
      case 0xe6e8: return Icons.water_drop_outlined;
      case 0xe0d6: return Icons.bakery_dining_outlined;
      case 0xe21a: return Icons.egg_alt_outlined;
      case 0xe2e6: return Icons.grain;
      case 0xe5d2: return Icons.spa_outlined;
      case 0xe333: return Icons.icecream_outlined;
      case 0xe463: return Icons.oil_barrel_outlined;
      case 0xe206: return Icons.eco_outlined;
      case 0xe3a7: return Icons.local_drink_outlined;
      case 0xe532: return Icons.rice_bowl_outlined;
      default: return Icons.inventory_2_outlined;
    }
  }
}


/// A line item in a completed or printed sale.
class SaleRecordItem {
  const SaleRecordItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  final String productId;
  final String productName;
  final Money unitPrice;
  final int quantity;
  final Money lineTotal;
}

enum SaleStatus {
  completed('Completed', AppColors.status_success),
  reversed('Reversed', AppColors.status_danger);

  const SaleStatus(this.label, this.color);
  final String label;
  final Color color;
}

/// Completed sale record in the immutable sales ledger.
class SaleRecord {
  SaleRecord({
    required this.receiptNumber,
    required this.timestamp,
    required this.cashier,
    required this.items,
    required this.subtotal,
    required this.vatAmount,
    required this.paymentMethod,
    required this.paymentReference,
    this.customer,
    this.status = SaleStatus.completed,
    this.reversalReason,
    this.cashTendered,
    this.changeDue,
  });

  final String receiptNumber;
  final DateTime timestamp;
  final String cashier;
  final List<SaleRecordItem> items;
  final Money subtotal;
  final Money vatAmount;
  final SalePaymentMethod paymentMethod;
  final String paymentReference;
  final PosCustomer? customer;
  SaleStatus status;
  String? reversalReason;
  final Money? cashTendered;
  final Money? changeDue;

  int get totalUnits => items.fold(0, (sum, i) => sum + i.quantity);
  bool get isReversed => status == SaleStatus.reversed;
}

enum LedgerEntryType {
  saleDebit('Goods on Credit', true),
  paymentCredit('Debt Payment', false),
  reversal('Reversal Entry', false);

  const LedgerEntryType(this.label, this.isDebit);
  final String label;
  final bool isDebit;
}

/// An entry in a customer's immutable credit ledger.
class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.amount,
    required this.reference,
    required this.runningBalance,
  });

  final String id;
  final DateTime timestamp;
  final LedgerEntryType type;
  final Money amount;
  final String reference;
  final Money runningBalance;
}

/// A registered customer with credit account.
class PosCustomer {
  PosCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.creditLimit,
    required this.currentBalance,
    List<CustomerLedgerEntry>? history,
  }) : ledger = history ?? [];

  final String id;
  final String name;
  final String phone;
  final Money creditLimit;
  Money currentBalance;
  final List<CustomerLedgerEntry> ledger;

  Money get availableCredit =>
      creditLimit > currentBalance ? Money(creditLimit.minorUnits - currentBalance.minorUnits) : const Money(0);
}

enum CashMovementType {
  floatIn('Opening Float', true),
  saleCash('Cash Sale', true),
  expenseOut('Expense Out', false),
  dropOut('Cash Drop', false);

  const CashMovementType(this.label, this.isInflow);
  final String label;
  final bool isInflow;
}

class CashMovement {
  const CashMovement({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.amount,
    required this.reason,
    required this.cashier,
  });

  final String id;
  final DateTime timestamp;
  final CashMovementType type;
  final Money amount;
  final String reason;
  final String cashier;
}

/// A till shift with cash drawer management and reconciliation.
class CashShift {
  CashShift({
    required this.shiftId,
    required this.openedAt,
    required this.openingFloat,
    required this.cashier,
  })  : cashSales = const Money(0),
        cashPaidIn = const Money(0),
        cashPaidOut = const Money(0),
        movements = [
          CashMovement(
            id: 'mov_init',
            timestamp: openedAt,
            type: CashMovementType.floatIn,
            amount: openingFloat,
            reason: 'Opening till float',
            cashier: cashier,
          ),
        ];

  final String shiftId;
  final DateTime openedAt;
  final Money openingFloat;
  final String cashier;
  Money cashSales;
  Money cashPaidIn;
  Money cashPaidOut;
  final List<CashMovement> movements;
  bool isClosed = false;
  Money? closingCounted;
  Money? variance;

  Money get expectedCash => Money(
        openingFloat.minorUnits + cashSales.minorUnits + cashPaidIn.minorUnits - cashPaidOut.minorUnits,
      );
}

enum PosUserRole {
  owner,
  manager,
  cashier,
  stockClerk,
}

class PosUser {
  PosUser({
    required this.id,
    required this.fullName,
    required this.phone,
    this.pin = '',
    required this.role,
    this.active = true,
    this.color = const Color(0xFF10B981),
  });

  final String id;
  String fullName;
  String phone;
  String pin;
  PosUserRole role;
  bool active;
  Color color;

  String get roleDisplay {
    switch (role) {
      case PosUserRole.owner:
        return 'Owner';
      case PosUserRole.manager:
        return 'Manager';
      case PosUserRole.cashier:
        return 'Cashier';
      case PosUserRole.stockClerk:
        return 'Stock Clerk';
    }
  }

  String get rolePermissions {
    switch (role) {
      case PosUserRole.owner:
        return 'Full System & Business Owner Access';
      case PosUserRole.manager:
        return 'Supervisory: Till drops, reversals, stock variance';
      case PosUserRole.cashier:
        return 'POS Counter: Ring sales, cash drawer, receipts';
      case PosUserRole.stockClerk:
        return 'Stockroom: Inventory counts, shelf stock, receiving';
    }
  }

  String get firstName => fullName.trim().split(' ').first;

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.substring(0, math.min(2, fullName.length)).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'phone': phone,
    'role': role.index,
    'color': color.toARGB32(),
    'active': active,
  };

  Map<String, dynamic> toApiJson({bool includePin = false}) => {
    'fullName': fullName,
    'phone': phone,
    'role': switch (role) {
      PosUserRole.owner => 'OWNER',
      PosUserRole.manager => 'MANAGER',
      PosUserRole.cashier => 'CASHIER',
      PosUserRole.stockClerk => 'STOCK_CLERK',
    },
    if (includePin && pin.isNotEmpty) 'pin': pin,
    if (id.isNotEmpty) 'active': active,
  };

  factory PosUser.fromApi(Map<String, dynamic> json) {
    final role = switch (json['role'] as String? ?? 'CASHIER') {
      'OWNER' => PosUserRole.owner,
      'MANAGER' => PosUserRole.manager,
      'STOCK_CLERK' => PosUserRole.stockClerk,
      _ => PosUserRole.cashier,
    };
    final color = switch (role) {
      PosUserRole.owner => const Color(0xFFD97706),
      PosUserRole.manager => const Color(0xFF7C3AED),
      PosUserRole.cashier => const Color(0xFF10B981),
      PosUserRole.stockClerk => const Color(0xFF2563EB),
    };
    return PosUser(
      id: json['id'] as String,
      fullName: json['fullName'] as String? ?? 'Staff',
      phone: json['phone'] as String? ?? '',
      role: role,
      active: json['active'] as bool? ?? true,
      color: color,
    );
  }

  factory PosUser.fromJson(Map<String, dynamic> json) => PosUser(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    phone: json['phone'] as String,
    // Migrate old browser records without restoring plaintext PINs.
    pin: '',
    role: PosUserRole.values[(json['role'] as int? ?? 2).clamp(0, PosUserRole.values.length - 1)],
    color: Color(json['color'] as int? ?? 0xFF10B981),
    active: json['active'] as bool? ?? true,
  );
}

/// Global reactive state for the Retail OS POS.
class PosState extends ChangeNotifier {
  PosState({bool? includeDemoProducts})
      : _includeDemoProducts = includeDemoProducts ?? _defaultIncludeDemoProducts {
    _initSampleData(includeProducts: _includeDemoProducts);
  }

  static const bool _defaultIncludeDemoProducts = bool.fromEnvironment(
    'POS_DEMO_DATA',
    defaultValue: false,
  );
  final bool _includeDemoProducts;

  final Cart cart = Cart();
  String activeCashier = 'John Mwangi';
  String get activeCashierName => activeCashier;
  set activeCashierName(String name) {
    activeCashier = name;
    notifyListeners();
  }

  // ─── Customizable Brand & Store Identity ───────────────────────────────
  String shopName = 'ShopSmart POS';
  String storeBranch = 'Kilimani Market · Counter 01';
  String tillId = 'TILL-01';
  String brandLogoUrl = '';
  /// Uploaded brand logo as base64 data URI (overrides brandLogoUrl when set).
  String? brandLogoBase64;
  String heroImageUrl = 'cashier_banner.jpg';
  String brandTagline = 'Your shop. Your customers. Everything in one place.';

  // ─── Hardware & Peripherals ─────────────────────────────────────────────
  bool autoPrintReceipt = true;
  bool cashDrawerKick = true;
  bool requirePinForReversal = true;
  String printerPaperSize = '80mm';
  String serverUrl = 'http://localhost:4000';

  late List<PosUser> users;
  PosUser? currentLoggedInUser;

  /// True once the async _loadFromStorage() has completed.
  bool sessionLoaded = false;

  List<PosUser> get activeUsers => users.where((u) => u.active).toList();

  Future<void> addUser(PosUser user) async {
    if (!ApiService.instance.hasToken || currentLoggedInUser?.role != PosUserRole.owner) {
      throw PosException('Only an online owner can create a staff account.');
    }
    final response = await ApiService.instance.createStaffUser(user.toApiJson(includePin: true));
    if (response == null) {
      throw PosException(ApiService.instance.lastError ?? 'Could not create staff account.');
    }
    users.add(PosUser.fromApi(response));
    user.pin = '';
    notifyListeners();
    await _persistAll();
  }

  Future<void> updateUser(PosUser updated) async {
    if (!ApiService.instance.hasToken || currentLoggedInUser?.role != PosUserRole.owner) {
      throw PosException('Only an online owner can update staff accounts.');
    }
    final payload = updated.toApiJson(includePin: true)..remove('active');
    final response = await ApiService.instance.updateStaffUser(updated.id, payload);
    if (response == null) {
      throw PosException(ApiService.instance.lastError ?? 'Could not update staff account.');
    }
    final saved = PosUser.fromApi(response);
    updated.pin = '';
    final idx = users.indexWhere((u) => u.id == updated.id);
    if (idx != -1) {
      users[idx] = saved;
      if (currentLoggedInUser?.id == updated.id) {
        currentLoggedInUser = saved;
        activeCashier = saved.fullName;
      }
      notifyListeners();
      await _persistAll();
    }
  }

  Future<void> deleteUser(String id) async {
    if (!ApiService.instance.hasToken || currentLoggedInUser?.role != PosUserRole.owner) {
      throw PosException('Only an online owner can deactivate staff accounts.');
    }
    if (currentLoggedInUser?.id == id) {
      throw PosException('Your active owner account cannot be deactivated here.');
    }
    final response = await ApiService.instance.updateStaffUser(id, {'active': false});
    if (response == null) {
      throw PosException(ApiService.instance.lastError ?? 'Could not deactivate staff account.');
    }
    users.removeWhere((u) => u.id == id);
    notifyListeners();
    await _persistAll();
  }

  Future<PosUser?> authenticateShopUser(String phone, String pin) async {
    ApiService.instance.configure(serverUrl);
    final auth = await ApiService.instance.login(phone, pin);
    if (auth == null) {
      catalogueSyncMessage = ApiService.instance.lastError ?? 'The shop API could not authenticate this account.';
      notifyListeners();
      return null;
    }

    final userJson = Map<String, dynamic>.from(auth['user'] as Map);
    final user = PosUser.fromApi(userJson);
    currentLoggedInUser = user;
    activeCashier = user.fullName;
    catalogueSyncMessage = 'Signed in as ${user.roleDisplay}. Refreshing shop data…';
    if (user.role == PosUserRole.owner) {
      final remoteUsers = await ApiService.instance.getStaffUsers();
      if (remoteUsers != null) {
        users = remoteUsers.map(PosUser.fromApi).toList();
      }
    }
    notifyListeners();
    await syncCatalogueFromApi();
    await persistSession(user);
    return user;
  }

  Future<void> toggleUserActive(String id) async {
    final idx = users.indexWhere((u) => u.id == id);
    if (idx == -1) return;
    final response = await ApiService.instance.updateStaffUser(
      id,
      {'active': !users[idx].active},
    );
    if (response == null) {
      throw PosException(ApiService.instance.lastError ?? 'Could not update staff status.');
    }
    users[idx] = PosUser.fromApi(response);
    notifyListeners();
    await _persistAll();
  }

  late List<PosProduct> products;
  late List<PosCategory> categories;
  String? catalogueSyncMessage;
  bool catalogueSyncing = false;
  late List<PosCustomer> customers;
  late List<SaleRecord> sales;
  List<SaleRecord> get salesLedger => sales;
  late CashShift shift;
  Money get expectedDrawerCash => shift.expectedCash;
  PosCustomer? selectedCustomer;

  void addProduct(PosProduct p) {
    products.insert(0, p);
    notifyListeners();
    _persistAll();
  }

  void updateProduct(PosProduct updated) {
    final idx = products.indexWhere((p) => p.id == updated.id);
    if (idx != -1) {
      products[idx] = updated;
      notifyListeners();
      _persistAll();
    }
  }

  /// Persist a product image and its product record before reporting success.
  /// Unlike the general background save, this surfaces browser quota/storage
  /// errors so the editor can remain open and tell the user what happened.
  Future<void> saveProduct(PosProduct product, {required bool isNew}) async {
    final index = products.indexWhere((item) => item.id == product.id);
    final previous = index == -1 ? null : products[index];
    if (!isNew && index == -1) {
      throw StateError('This product is no longer in the catalogue. Refresh and try again.');
    }
    if (!isNew && _isRemoteProductId(product.id) && !ApiService.instance.hasToken) {
      throw PosException('Sign in to the shop API before editing a server product.');
    }

    var savedProduct = product;
    if (ApiService.instance.hasToken) {
      final remote = isNew || !_isRemoteProductId(product.id)
          ? await _createRemoteProduct(product)
          : await _updateRemoteProduct(product, previous!);
      savedProduct = _productFromApi(remote, fallback: product);
    }
    if (isNew) {
      products.insert(0, savedProduct);
    } else {
      products[index] = savedProduct;
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        'products_json',
        jsonEncode(products.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw StateError('The browser declined to save the product.');
    } catch (error) {
      if (isNew) {
        products.removeWhere((item) => item.id == savedProduct.id);
      } else if (previous != null) {
        final savedIndex = products.indexWhere((item) => item.id == savedProduct.id);
        if (savedIndex != -1) products[savedIndex] = previous;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteProduct(String productId) async {
    // Keep the older delete entry point safe too: product history is retained
    // by the API, and local-only products are hidden rather than erased.
    await deactivateProduct(productId);
  }

  Future<void> deactivateProduct(String productId) async {
    final index = products.indexWhere((product) => product.id == productId);
    if (index == -1) return;
    final previous = products[index];
    final isApiProduct = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(productId);
    if (isApiProduct && !ApiService.instance.hasToken) {
      throw PosException('Sign in to the shop API before deactivating a server product.');
    }
    if (ApiService.instance.hasToken && isApiProduct) {
      final ok = await ApiService.instance.deactivateProduct(productId);
      if (!ok) throw PosException(ApiService.instance.lastError ?? 'The shop API could not deactivate this product.');
    }
    products[index] = previous.copyWith(isActive: false);
    notifyListeners();
    await _persistAll();
  }

  Future<int> importProducts(List<PosProduct> imported) async {
    final existingSkus = products.map((product) => product.sku.toLowerCase()).toSet();
    final rows = <PosProduct>[];
    for (final product in imported) {
      if (existingSkus.contains(product.sku.toLowerCase())) continue;
      existingSkus.add(product.sku.toLowerCase());
      rows.add(product);
    }
    if (ApiService.instance.hasToken && rows.isNotEmpty) {
      final remoteRows = await ApiService.instance.importProducts(rows.map(_productPayload).toList());
      if (remoteRows == null) {
        throw PosException(ApiService.instance.lastError ?? 'The shop API could not import these products.');
      }
      rows
        ..clear()
        ..addAll(remoteRows.map((remote) => _productFromApi(remote)));
    }
    final backup = List<PosProduct>.from(products);
    products.insertAll(0, rows);
    _syncCategoriesWithProducts();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        'products_json',
        jsonEncode(products.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw PosException('The browser declined to save imported products.');
      await prefs.setString('categories_json', jsonEncode(categories.map((item) => item.toJson()).toList()));
      return rows.length;
    } catch (_) {
      products
        ..clear()
        ..addAll(backup);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setProductActive(String productId, bool active) async {
    final index = products.indexWhere((product) => product.id == productId);
    if (index == -1) return;
    final product = products[index];
    if (_isRemoteProductId(productId)) {
      if (!ApiService.instance.hasToken) {
        throw PosException('Sign in to the shop API before changing a server product.');
      }
      final ok = await ApiService.instance.setProductActive(productId, active);
      if (!ok) throw PosException(ApiService.instance.lastError ?? 'The shop API could not update this product.');
    }
    products[index] = product.copyWith(isActive: active);
    notifyListeners();
    await _persistAll();
  }

  Future<void> syncCatalogueFromApi() async {
    if (!ApiService.instance.hasToken) return;
    catalogueSyncing = true;
    catalogueSyncMessage = 'Refreshing shop catalogue…';
    notifyListeners();
    try {
      final remoteCategories = await ApiService.instance.getCategories();
      if (remoteCategories == null) {
        throw PosException(ApiService.instance.lastError ?? 'Could not refresh shop categories.');
      }
      final remoteProducts = await ApiService.instance.getProducts();
      if (remoteProducts == null) {
        throw PosException(ApiService.instance.lastError ?? 'Could not refresh shop products.');
      }

      final oldById = {for (final product in products) product.id: product};
      final syncedCategories = <PosCategory>[];
      for (final remote in remoteCategories) {
        final name = remote['name'] as String? ?? 'Other';
        final existing = categories.where((item) => item.name.toLowerCase() == name.toLowerCase()).firstOrNull;
        syncedCategories.add(PosCategory(
          id: remote['id'] as String,
          name: name,
          colorValue: _colorFromHex(remote['colorHex'] as String?) ?? existing?.colorValue ?? 0xFFF8FAFC,
          iconKey: existing?.iconKey ?? _iconKeyForCategory(name),
        ));
      }
      // Make remote category IDs available while uploading local-only products.
      // Otherwise an existing category may be needlessly POSTed before the
      // final category list is assigned below.
      final remoteNames = syncedCategories.map((item) => item.name.toLowerCase()).toSet();
      final localCategories = categories.where((item) => !remoteNames.contains(item.name.toLowerCase()));
      categories = [...syncedCategories, ...localCategories];

      final syncedProducts = remoteProducts.map((remote) {
        final id = remote['id'] as String;
        return _productFromApi(remote, fallback: oldById[id]);
      }).toList();
      final serverSkus = syncedProducts.map((product) => product.sku.toLowerCase()).toSet();
      final localOnly = products.where((product) => !_isRemoteProductId(product.id)).toList();
      final remainingLocal = <PosProduct>[];
      for (final local in localOnly) {
        if (!local.isActive || _isBundledDemoProduct(local.id)) continue;
        if (serverSkus.contains(local.sku.toLowerCase())) continue;
        try {
          final created = await _createRemoteProduct(local);
          final synced = _productFromApi(created, fallback: local);
          syncedProducts.add(synced);
          serverSkus.add(synced.sku.toLowerCase());
        } catch (error) {
          debugPrint('Could not sync local product ${local.sku}: $error');
          remainingLocal.add(local);
        }
      }

      products = [...syncedProducts, ...remainingLocal];
      _syncCategoriesWithProducts();
      await _persistAll();
      catalogueSyncMessage = remainingLocal.isEmpty
          ? 'Catalogue is up to date.'
          : '${remainingLocal.length} local product(s) could not sync. Check the shop API connection.';
    } catch (error) {
      catalogueSyncMessage = 'Catalogue sync failed: $error';
    } finally {
      catalogueSyncing = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _createRemoteProduct(PosProduct product) async {
    if (!ApiService.instance.hasToken) throw PosException('Sign in to the shop API first.');
    final categoryId = await _ensureRemoteCategory(product.category);
    final response = await ApiService.instance.createProduct({
      ..._productPayload(product),
      'categoryId': categoryId,
    });
    if (response == null) throw PosException(ApiService.instance.lastError ?? 'The shop API did not create the product.');
    return response;
  }

  Future<Map<String, dynamic>> _updateRemoteProduct(PosProduct product, PosProduct previous) async {
    final categoryId = await _ensureRemoteCategory(product.category);
    final payload = _productPayload(product)
      ..remove('category')
      ..remove('initialStock')
      ..['categoryId'] = categoryId;
    final response = await ApiService.instance.updateProduct(product.id, payload);
    if (response == null) throw PosException(ApiService.instance.lastError ?? 'The shop API did not update the product.');
    if (product.stock != previous.stock) {
      final changed = await ApiService.instance.adjustStock(
        product.id,
        product.stock - previous.stock,
        product.stock >= previous.stock ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
        'POS product edit',
      );
      if (!changed) throw PosException(ApiService.instance.lastError ?? 'Product details saved, but stock adjustment failed. Refresh before retrying.');
      response['stock'] = product.stock;
    }
    return response;
  }

  Future<String?> _ensureRemoteCategory(String name) async {
    final existing = categories.where((item) => item.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (existing != null && _isRemoteProductId(existing.id)) return existing.id;
    final created = await ApiService.instance.createCategory(name);
    if (created != null && created['id'] is String) {
      final category = PosCategory(
        id: created['id'] as String,
        name: created['name'] as String? ?? name,
        colorValue: existing?.colorValue ?? 0xFFF8FAFC,
        iconKey: existing?.iconKey ?? _iconKeyForCategory(name),
      );
      categories.removeWhere((item) => item.name.toLowerCase() == name.toLowerCase());
      categories.add(category);
      return category.id;
    }
    final remoteCategories = await ApiService.instance.getCategories();
    final match = remoteCategories?.where((item) => (item['name'] as String?)?.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (match?['id'] is String) return match!['id'] as String;
    throw PosException(ApiService.instance.lastError ?? 'Could not prepare category "$name" on the shop API.');
  }

  Map<String, dynamic> _productPayload(PosProduct product) => {
        'name': product.name,
        'sku': product.sku,
        if (product.barcode != null && product.barcode!.isNotEmpty) 'barcode': product.barcode,
        'category': product.category,
        'salePrice': product.unitPrice.minorUnits / 100,
        'costPrice': (product.costPrice ?? const Money(0)).minorUnits / 100,
        'vatRate': product.taxRateBasisPoints / 10000,
        'unit': 'pc',
        'initialStock': product.stock,
        'lowStockThreshold': product.lowStockThreshold,
      };

  PosProduct _productFromApi(Map<String, dynamic> remote, {PosProduct? fallback}) {
    final categoryValue = remote['category'];
    final categoryName = categoryValue is Map<String, dynamic>
        ? (categoryValue['name'] as String? ?? fallback?.category ?? 'Other')
        : (categoryValue as String? ?? fallback?.category ?? 'Other');
    final categoryColor = categoryValue is Map<String, dynamic>
        ? _colorFromHex(categoryValue['colorHex'] as String?)
        : null;
    final localCategory = categories.where((item) => item.name.toLowerCase() == categoryName.toLowerCase()).firstOrNull;
    final price = remote['salePrice'] as num;
    final cost = remote['costPrice'] as num?;
    final vat = remote['vatRate'] as num?;
    return PosProduct(
      id: remote['id'] as String,
      name: remote['name'] as String? ?? fallback?.name ?? '',
      sku: remote['sku'] as String? ?? fallback?.sku ?? '',
      barcode: remote['barcode'] as String? ?? fallback?.barcode,
      category: categoryName,
      unitPrice: Money.parse(price.toString()),
      costPrice: cost == null || cost == 0 ? null : Money.parse(cost.toString()),
      stock: (remote['stock'] as num? ?? fallback?.stock ?? 0).toInt(),
      lowStockThreshold: (remote['lowStockThreshold'] as num? ?? fallback?.lowStockThreshold ?? 10).toInt(),
      icon: localCategory?.icon ?? fallback?.icon ?? Icons.inventory_2_outlined,
      tint: categoryColor != null ? Color(categoryColor) : localCategory?.color ?? fallback?.tint ?? const Color(0xFFF8FAFC),
      taxRateBasisPoints: vat == null ? (fallback?.taxRateBasisPoints ?? defaultVatRateBasisPoints) : (vat * 10000).round(),
      isActive: remote['active'] as bool? ?? fallback?.isActive ?? true,
      notes: fallback?.notes,
      imageBase64: fallback?.imageBase64,
      groupId: fallback?.groupId,
      variantLabel: fallback?.variantLabel,
    );
  }

  int? _colorFromHex(String? value) {
    if (value == null) return null;
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6) return null;
    final color = int.tryParse(hex, radix: 16);
    return color == null ? null : 0xFF000000 | color;
  }

  String _iconKeyForCategory(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('dairy')) return 'dairy';
    if (normalized.contains('bakery')) return 'bakery';
    if (normalized.contains('drink') || normalized.contains('beverage')) return 'drink';
    if (normalized.contains('produce')) return 'produce';
    if (normalized.contains('snack')) return 'snack';
    if (normalized.contains('health') || normalized.contains('personal care')) return 'health';
    if (normalized.contains('clean')) return 'clean';
    if (normalized.contains('house')) return 'home';
    if (normalized.contains('grain') || normalized.contains('food')) return 'grain';
    return 'box';
  }

  bool _isRemoteProductId(String id) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(id);

  // ─── Variants ──────────────────────────────────────────────────────────────────────

  /// [p] plus its sibling variants (catalogue order). A standalone product
  /// returns just itself.
  List<PosProduct> variantsOf(PosProduct p) {
    final gid = p.groupId;
    if (gid == null) return [p];
    final list = products.where((x) => x.groupId == gid).toList();
    return list.isEmpty ? [p] : list;
  }

  /// One entry per catalogue item: standalone products as-is, and the first
  /// variant of each variant group.
  List<PosProduct> get catalogueRepresentatives {
    final seen = <String>{};
    final out = <PosProduct>[];
    for (final p in products) {
      final gid = p.groupId;
      if (gid == null) {
        out.add(p);
      } else if (seen.add(gid)) {
        out.add(p);
      }
    }
    return out;
  }

  /// Saves all variants of one product in a single step.
  ///
  /// [variants] is the desired final set (existing ids are updated in place,
  /// unknown ids are added). Variants in [originalIds] that are no longer in
  /// [variants] are deactivated, not deleted, so past sales, receipts and
  /// reversals that point at them keep working. Rolls back and rethrows if the
  /// browser refuses to store the data.
  Future<void> saveVariantGroup({
    required String groupId,
    required List<PosProduct> variants,
    required Set<String> originalIds,
  }) async {
    final backup = List<PosProduct>.from(products);
    final keepIds = variants.map((v) => v.id).toSet();

    final fresh = <PosProduct>[];
    for (final v in variants) {
      final idx = products.indexWhere((p) => p.id == v.id);
      if (idx == -1) {
        fresh.add(v);
      } else {
        products[idx] = v;
      }
    }

    for (var i = 0; i < products.length; i++) {
      final p = products[i];
      if (originalIds.contains(p.id) && !keepIds.contains(p.id) && p.isActive) {
        products[i] = p.copyWith(isActive: false);
      }
    }

    if (fresh.isNotEmpty) {
      final lastSibling = products.lastIndexWhere((p) => p.groupId == groupId);
      products.insertAll(lastSibling == -1 ? 0 : lastSibling + 1, fresh);
    }

    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        'products_json',
        jsonEncode(products.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw StateError('The browser declined to save the product.');
    } catch (_) {
      products
        ..clear()
        ..addAll(backup);
      notifyListeners();
      rethrow;
    }
  }

  // ─── Categories ───────────────────────────────────────────────────────────────────

  PosCategory? categoryByName(String name) {
    final key = name.trim().toLowerCase();
    for (final c in categories) {
      if (c.name.toLowerCase() == key) return c;
    }
    return null;
  }

  Color categoryColor(String name) =>
      categoryByName(name)?.color ?? const Color(0xFFF8FAFC);

  IconData categoryIcon(String name) =>
      categoryByName(name)?.icon ?? Icons.inventory_2_outlined;

  /// Number of sellable items (each variant counts) in a category.
  int productCountIn(String categoryName) =>
      products.where((p) => p.category == categoryName).length;

  Future<PosCategory> addCategory(
    String name, {
    int? colorValue,
    String iconKey = 'box',
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw PosException('Category name is required.');
    if (categoryByName(clean) != null) {
      throw PosException('A category called "$clean" already exists.');
    }
    final cat = PosCategory(
      id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
      name: clean,
      colorValue: colorValue ?? kCategoryColors[categories.length % kCategoryColors.length],
      iconKey: iconKey,
    );
    categories.add(cat);
    notifyListeners();
    await _persistAll();
    return cat;
  }

  /// Renames / recolours a category. Products in it follow the rename.
  Future<void> updateCategory(
    String id, {
    String? name,
    int? colorValue,
    String? iconKey,
  }) async {
    final cat = categories.firstWhere((c) => c.id == id);
    final oldName = cat.name;

    if (name != null) {
      final clean = name.trim();
      if (clean.isEmpty) throw PosException('Category name is required.');
      final clash = categoryByName(clean);
      if (clash != null && clash.id != id) {
        throw PosException('A category called "$clean" already exists.');
      }
      cat.name = clean;
    }
    if (colorValue != null) cat.colorValue = colorValue;
    if (iconKey != null) cat.iconKey = iconKey;

    for (var i = 0; i < products.length; i++) {
      final p = products[i];
      if (p.category == oldName) {
        p.category = cat.name;
        products[i] = p.copyWith(icon: cat.icon, tint: cat.color);
      }
    }
    notifyListeners();
    await _persistAll();
  }

  /// Deletes a category. If products use it, [moveProductsTo] (another
  /// category's name) is required and they are moved there.
  Future<void> deleteCategory(String id, {String? moveProductsTo}) async {
    final cat = categories.firstWhere((c) => c.id == id);
    final inUse = productCountIn(cat.name);
    if (categories.length <= 1) {
      throw PosException('Keep at least one category.');
    }
    if (inUse > 0) {
      final target = moveProductsTo == null ? null : categoryByName(moveProductsTo);
      if (target == null || target.id == id) {
        throw PosException('Choose a category to move its $inUse products to.');
      }
      for (var i = 0; i < products.length; i++) {
        final p = products[i];
        if (p.category == cat.name) {
          p.category = target.name;
          products[i] = p.copyWith(icon: target.icon, tint: target.color);
        }
      }
    }
    categories.removeWhere((c) => c.id == id);
    notifyListeners();
    await _persistAll();
  }

  void _initDefaultCategories() {
    categories = [
      PosCategory(id: 'cat_dairy', name: 'Dairy', colorValue: 0xFFEFF6FF, iconKey: 'dairy'),
      PosCategory(id: 'cat_bakery', name: 'Bakery', colorValue: 0xFFFFFBEB, iconKey: 'bakery'),
      PosCategory(id: 'cat_beverages', name: 'Beverages', colorValue: 0xFFF0FDF4, iconKey: 'drink'),
      PosCategory(id: 'cat_produce', name: 'Produce', colorValue: 0xFFF7FEE7, iconKey: 'produce'),
      PosCategory(id: 'cat_groceries', name: 'Groceries', colorValue: 0xFFFEFCE8, iconKey: 'grain'),
      PosCategory(id: 'cat_snacks', name: 'Snacks', colorValue: 0xFFFFF7ED, iconKey: 'snack'),
      PosCategory(id: 'cat_household', name: 'Household', colorValue: 0xFFF5F3FF, iconKey: 'home'),
      PosCategory(id: 'cat_health', name: 'Health', colorValue: 0xFFFFEFF2, iconKey: 'health'),
      PosCategory(id: 'cat_cleaning', name: 'Cleaning', colorValue: 0xFFEEF2FF, iconKey: 'clean'),
      PosCategory(id: 'cat_other', name: 'Other', colorValue: 0xFFF8FAFC, iconKey: 'box'),
    ];
  }

  /// Any category name used by a product but missing from [categories]
  /// (older saved data, or the sample "Groceries") is added automatically.
  void _syncCategoriesWithProducts() {
    for (final p in products) {
      if (categoryByName(p.category) == null) {
        categories.add(PosCategory(
          id: 'cat_${DateTime.now().microsecondsSinceEpoch}_${categories.length}',
          name: p.category,
          colorValue: p.tint.toARGB32(),
          iconKey: 'box',
        ));
      }
    }
  }

  void addCustomer(PosCustomer c) {
    customers.insert(0, c);
    notifyListeners();
  }


  int savedTabIndex = 0;
  static const int sessionTimeoutMinutes = 60; // 1 hour unattended session threshold

  void setActiveTab(int index) {
    savedTabIndex = index;
    touchSession();
    _saveActiveTab(index);
  }

  Future<void> _saveActiveTab(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('session_active_tab', index);
    } catch (_) {}
  }

  /// Touch session on any user action so the 1-hour unattended window rolls forward
  Future<void> touchSession() async {
    if (currentLoggedInUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('session_last_active', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> logout() async {
    await persistSession(null);
  }

  // ─── Persistence Methods ───────────────────────────────────────────────
  Future<void> loadInitialState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      shopName = prefs.getString('shop_name') ?? shopName;
      storeBranch = prefs.getString('store_branch') ?? storeBranch;
      tillId = prefs.getString('till_id') ?? tillId;
      brandLogoUrl = prefs.getString('brand_logo_url') ?? brandLogoUrl;
      brandLogoBase64 = prefs.getString('brand_logo_base64');
      heroImageUrl = prefs.getString('hero_image_url') ?? heroImageUrl;
      brandTagline = prefs.getString('brand_tagline') ?? brandTagline;

      autoPrintReceipt = prefs.getBool('auto_print_receipt') ?? autoPrintReceipt;
      cashDrawerKick = prefs.getBool('cash_drawer_kick') ?? cashDrawerKick;
      requirePinForReversal = prefs.getBool('require_pin_reversal') ?? requirePinForReversal;
      printerPaperSize = prefs.getString('printer_paper_size') ?? printerPaperSize;
      serverUrl = prefs.getString('server_url') ?? serverUrl;
      if (serverUrl == 'http://localhost:3000') {
        serverUrl = 'http://localhost:4000';
      }

      final usersJson = prefs.getString('users_json');
      if (usersJson != null) {
        try {
          final list = jsonDecode(usersJson) as List;
          users = list.map((item) => PosUser.fromJson(item as Map<String, dynamic>)).toList();
          // Rewrite legacy browser records immediately; older versions stored
          // staff PINs in plaintext inside users_json.
          await prefs.setString('users_json', jsonEncode(users.map((u) => u.toJson()).toList()));
        } catch (e) {
          debugPrint('Error parsing users_json: $e');
        }
      }

      final productsJson = prefs.getString('products_json');
      if (productsJson != null) {
        try {
          final list = jsonDecode(productsJson) as List;
          products = list.map((item) => PosProduct.fromJson(item as Map<String, dynamic>)).toList();
        } catch (e) {
          debugPrint('Error parsing products_json: $e');
        }
      }
      if (!_includeDemoProducts) {
        products.removeWhere((product) => _isBundledDemoProduct(product.id));
      }

      final categoriesJson = prefs.getString('categories_json');
      if (categoriesJson != null) {
        try {
          final list = jsonDecode(categoriesJson) as List;
          final loaded = list.map((item) => PosCategory.fromJson(item as Map<String, dynamic>)).toList();
          if (loaded.isNotEmpty) categories = loaded;
        } catch (e) {
          debugPrint('Error parsing categories_json: $e');
        }
      }
      _syncCategoriesWithProducts();
      if (!_includeDemoProducts && productsJson == null) {
        await prefs.setString('products_json', jsonEncode(<dynamic>[]));
      } else if (!_includeDemoProducts && productsJson != null) {
        await prefs.setString('products_json', jsonEncode(products.map((item) => item.toJson()).toList()));
      }

      // The JWT is intentionally memory-only. A cached user object is not an
      // authentication credential, so every browser restart requires a PIN.
      currentLoggedInUser = null;
      savedTabIndex = prefs.getInt('session_active_tab') ?? 0;
      await prefs.remove('session_user_id');
      await prefs.remove('session_user_json');
      await prefs.remove('session_last_active');

      sessionLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading saved settings from storage: $e');
      sessionLoaded = true;
      notifyListeners();
    }
  }

  static bool _isBundledDemoProduct(String id) =>
      RegExp(r'^prod_(?:[1-9]|10)$').hasMatch(id);

  Future<void> _persistAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shop_name', shopName);
      await prefs.setString('store_branch', storeBranch);
      await prefs.setString('till_id', tillId);
      await prefs.setString('brand_logo_url', brandLogoUrl);
      if (brandLogoBase64 != null) {
        await prefs.setString('brand_logo_base64', brandLogoBase64!);
      } else {
        await prefs.remove('brand_logo_base64');
      }
      await prefs.setString('hero_image_url', heroImageUrl);
      await prefs.setString('brand_tagline', brandTagline);

      await prefs.setBool('auto_print_receipt', autoPrintReceipt);
      await prefs.setBool('cash_drawer_kick', cashDrawerKick);
      await prefs.setBool('require_pin_reversal', requirePinForReversal);
      await prefs.setString('printer_paper_size', printerPaperSize);
      await prefs.setString('server_url', serverUrl);

      final usersList = users.map((u) => u.toJson()).toList();
      await prefs.setString('users_json', jsonEncode(usersList));

      final productsList = products.map((p) => p.toJson()).toList();
      await prefs.setString('products_json', jsonEncode(productsList));
      await prefs.setString('categories_json', jsonEncode(categories.map((c) => c.toJson()).toList()));

      // Persist session if active
      if (currentLoggedInUser != null) {
        await prefs.setString('session_user_id', currentLoggedInUser!.id);
        await prefs.setString('session_user_json', jsonEncode(currentLoggedInUser!.toJson()));
        await prefs.setInt('session_last_active', DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('session_active_tab', savedTabIndex);
      }
    } catch (e) {
      debugPrint('Error persisting settings: $e');
    }
  }

  /// Call when a user logs in or out to immediately persist/clear the session.
  Future<void> persistSession(PosUser? user, {int? tabIndex}) async {
    if (user == null) ApiService.instance.setToken(null);
    currentLoggedInUser = user;
    if (user != null) activeCashier = user.fullName;
    if (tabIndex != null) savedTabIndex = tabIndex;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user != null) {
        await prefs.setString('session_user_id', user.id);
        await prefs.setString('session_user_json', jsonEncode(user.toJson()));
        await prefs.setInt('session_last_active', DateTime.now().millisecondsSinceEpoch);
        if (tabIndex != null) {
          await prefs.setInt('session_active_tab', tabIndex);
        }
      } else {
        await prefs.remove('session_user_id');
        await prefs.remove('session_user_json');
        await prefs.remove('session_last_active');
      }
    } catch (e) {
      debugPrint('Error persisting session: $e');
    }
  }

  Future<void> saveSettings({
    String? newShopName,
    String? newStoreBranch,
    String? newTillId,
    String? newBrandLogoUrl,
    String? newBrandLogoBase64,
    bool clearLogoBase64 = false,
    String? newHeroImageUrl,
    String? newBrandTagline,
    bool? newAutoPrintReceipt,
    bool? newCashDrawerKick,
    bool? newRequirePinForReversal,
    String? newPrinterPaperSize,
    String? newServerUrl,
  }) async {
    if (newShopName != null) shopName = newShopName;
    if (newStoreBranch != null) storeBranch = newStoreBranch;
    if (newTillId != null) tillId = newTillId;
    if (newBrandLogoUrl != null) brandLogoUrl = newBrandLogoUrl;
    if (newBrandLogoBase64 != null) brandLogoBase64 = newBrandLogoBase64;
    if (clearLogoBase64) brandLogoBase64 = null;
    if (newHeroImageUrl != null) heroImageUrl = newHeroImageUrl;
    if (newBrandTagline != null) brandTagline = newBrandTagline;
    if (newAutoPrintReceipt != null) autoPrintReceipt = newAutoPrintReceipt;
    if (newCashDrawerKick != null) cashDrawerKick = newCashDrawerKick;
    if (newRequirePinForReversal != null) requirePinForReversal = newRequirePinForReversal;
    if (newPrinterPaperSize != null) printerPaperSize = newPrinterPaperSize;
    if (newServerUrl != null) serverUrl = newServerUrl;

    notifyListeners();
    await _persistAll();
  }

  Future<void> resetCatalogueToDefaults() async {
    _initDefaultCategories();
    _initDefaultProducts();
    notifyListeners();
    await _persistAll();
  }

  Future<void> resetUsersToDefaults() async {
    _initDefaultUsers();
    notifyListeners();
    await _persistAll();
  }

  int _receiptCounter = 1042;

  void _initDefaultUsers() {
    users = [
      PosUser(
        id: 'usr_1',
        fullName: 'John Mwangi',
        phone: '+254 712 345 678',
        pin: '1234',
        role: PosUserRole.cashier,
        color: const Color(0xFF10B981),
      ),
      PosUser(
        id: 'usr_2',
        fullName: 'Wanjiku Karanja',
        phone: '+254 722 987 654',
        pin: '2222',
        role: PosUserRole.cashier,
        color: const Color(0xFF0D9488),
      ),
      PosUser(
        id: 'usr_3',
        fullName: 'Amina Hassan',
        phone: '+254 701 555 777',
        pin: '9999',
        role: PosUserRole.manager,
        color: const Color(0xFF7C3AED),
      ),
      PosUser(
        id: 'usr_4',
        fullName: 'Otieno Juma',
        phone: '+254 733 111 222',
        pin: '3333',
        role: PosUserRole.stockClerk,
        color: const Color(0xFF2563EB),
      ),
      PosUser(
        id: 'usr_5',
        fullName: 'David Kamau',
        phone: '+254 720 000 111',
        pin: '0000',
        role: PosUserRole.owner,
        color: const Color(0xFFD97706),
      ),
    ];

  }

  void _initDefaultProducts() {
    products = [
      PosProduct(
        id: 'prod_1',
        name: 'Fresh milk 500ml',
        sku: 'MLK-500',
        category: 'Dairy',
        unitPrice: const Money.shillings(65),
        stock: 24,
        lowStockThreshold: 10,
        icon: Icons.water_drop_outlined,
        tint: const Color(0xFFE9F2FF),
      ),
      PosProduct(
        id: 'prod_2',
        name: 'White bread 400g',
        sku: 'BRD-400',
        category: 'Bakery',
        unitPrice: const Money.shillings(75),
        stock: 18,
        lowStockThreshold: 8,
        icon: Icons.bakery_dining_outlined,
        tint: const Color(0xFFFFF3DF),
      ),
      PosProduct(
        id: 'prod_3',
        name: 'Farm eggs (tray of 30)',
        sku: 'EGG-TR30',
        category: 'Dairy',
        unitPrice: const Money.shillings(480),
        stock: 8,
        lowStockThreshold: 10,
        icon: Icons.egg_alt_outlined,
        tint: const Color(0xFFFFF1D6),
      ),
      PosProduct(
        id: 'prod_4',
        name: 'Supa maize flour 2kg',
        sku: 'MZE-2KG',
        category: 'Groceries',
        unitPrice: const Money.shillings(185),
        stock: 31,
        lowStockThreshold: 12,
        icon: Icons.grain,
        tint: const Color(0xFFEAF5E9),
      ),
      PosProduct(
        id: 'prod_5',
        name: 'Fresh tomatoes 1kg',
        sku: 'TOM-1KG',
        category: 'Produce',
        unitPrice: const Money.shillings(120),
        stock: 14,
        lowStockThreshold: 6,
        icon: Icons.spa_outlined,
        tint: const Color(0xFFFFE9E5),
      ),
      PosProduct(
        id: 'prod_6',
        name: 'Long-life yoghurt 250ml',
        sku: 'YGT-250',
        category: 'Dairy',
        unitPrice: const Money.shillings(55),
        stock: 16,
        lowStockThreshold: 10,
        icon: Icons.icecream_outlined,
        tint: const Color(0xFFF3EAFE),
      ),
      PosProduct(
        id: 'prod_7',
        name: 'Cooking oil 1L bottle',
        sku: 'OIL-1L',
        category: 'Groceries',
        unitPrice: const Money.shillings(320),
        stock: 5,
        lowStockThreshold: 10,
        icon: Icons.oil_barrel_outlined,
        tint: const Color(0xFFFFF5D9),
      ),
      PosProduct(
        id: 'prod_8',
        name: 'Sweet Bananas (bunch)',
        sku: 'BAN-BNCH',
        category: 'Produce',
        unitPrice: const Money.shillings(90),
        stock: 20,
        lowStockThreshold: 8,
        icon: Icons.eco_outlined,
        tint: const Color(0xFFF4F5D9),
      ),
      PosProduct(
        id: 'prod_9',
        name: 'Kenya Cane 250ml',
        sku: 'KC-250',
        category: 'Beverages',
        unitPrice: const Money.shillings(260),
        stock: 12,
        lowStockThreshold: 6,
        icon: Icons.local_drink_outlined,
        tint: const Color(0xFFE5F7ED),
      ),
      PosProduct(
        id: 'prod_10',
        name: 'Basmati Rice 2kg',
        sku: 'RCE-2KG',
        category: 'Groceries',
        unitPrice: const Money.shillings(390),
        stock: 19,
        lowStockThreshold: 8,
        icon: Icons.rice_bowl_outlined,
        tint: const Color(0xFFF0FDF4),
      ),
    ];

  }

  void _initSampleData({required bool includeProducts}) {
    if (includeProducts) {
      _initDefaultUsers();
    } else {
      users = <PosUser>[];
    }
    _initDefaultCategories();
    if (includeProducts) {
      _initDefaultProducts();
    } else {
      products = <PosProduct>[];
    }
    customers = [
      PosCustomer(
        id: 'cust_1',
        name: 'Mama Oliech Kitchen',
        phone: '+254 722 102 304',
        creditLimit: const Money.shillings(25000),
        currentBalance: const Money.shillings(4200),
        history: [
          CustomerLedgerEntry(
            id: 'led_1',
            timestamp: DateTime.now().subtract(const Duration(days: 2)),
            type: LedgerEntryType.saleDebit,
            amount: const Money.shillings(5200),
            reference: 'RCP-2026-1039',
            runningBalance: const Money.shillings(5200),
          ),
          CustomerLedgerEntry(
            id: 'led_2',
            timestamp: DateTime.now().subtract(const Duration(days: 1)),
            type: LedgerEntryType.paymentCredit,
            amount: const Money.shillings(1000),
            reference: 'MPESA: QCG928A81K',
            runningBalance: const Money.shillings(4200),
          ),
        ],
      ),
      PosCustomer(
        id: 'cust_2',
        name: 'Kariuki Hardware Supplies',
        phone: '+254 733 456 789',
        creditLimit: const Money.shillings(40000),
        currentBalance: const Money.shillings(12500),
        history: [
          CustomerLedgerEntry(
            id: 'led_3',
            timestamp: DateTime.now().subtract(const Duration(days: 3)),
            type: LedgerEntryType.saleDebit,
            amount: const Money.shillings(12500),
            reference: 'RCP-2026-1025',
            runningBalance: const Money.shillings(12500),
          ),
        ],
      ),
      PosCustomer(
        id: 'cust_3',
        name: 'Teacher Wanjiku',
        phone: '+254 710 987 654',
        creditLimit: const Money.shillings(10000),
        currentBalance: const Money.shillings(850),
        history: [
          CustomerLedgerEntry(
            id: 'led_4',
            timestamp: DateTime.now().subtract(const Duration(hours: 18)),
            type: LedgerEntryType.saleDebit,
            amount: const Money.shillings(850),
            reference: 'RCP-2026-1040',
            runningBalance: const Money.shillings(850),
          ),
        ],
      ),
    ];

    sales = [
      SaleRecord(
        receiptNumber: 'RCP-2026-1040',
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 24)),
        cashier: activeCashier,
        items: [
          SaleRecordItem(
            productId: 'prod_1',
            productName: 'Fresh milk 500ml',
            unitPrice: const Money.shillings(65),
            quantity: 2,
            lineTotal: const Money.shillings(130),
          ),
          SaleRecordItem(
            productId: 'prod_4',
            productName: 'Supa maize flour 2kg',
            unitPrice: const Money.shillings(185),
            quantity: 1,
            lineTotal: const Money.shillings(185),
          ),
        ],
        subtotal: const Money.shillings(315),
        vatAmount: const Money.shillings(315).vatIncludedAt(defaultVatRateBasisPoints),
        paymentMethod: SalePaymentMethod.mpesa,
        paymentReference: 'MPESA: QDH189XP01',
      ),
      SaleRecord(
        receiptNumber: 'RCP-2026-1041',
        timestamp: DateTime.now().subtract(const Duration(minutes: 42)),
        cashier: activeCashier,
        items: [
          SaleRecordItem(
            productId: 'prod_7',
            productName: 'Cooking oil 1L bottle',
            unitPrice: const Money.shillings(320),
            quantity: 1,
            lineTotal: const Money.shillings(320),
          ),
          SaleRecordItem(
            productId: 'prod_2',
            productName: 'White bread 400g',
            unitPrice: const Money.shillings(75),
            quantity: 2,
            lineTotal: const Money.shillings(150),
          ),
        ],
        subtotal: const Money.shillings(470),
        vatAmount: const Money.shillings(470).vatIncludedAt(defaultVatRateBasisPoints),
        paymentMethod: SalePaymentMethod.cash,
        paymentReference: 'CASH',
        cashTendered: const Money.shillings(500),
        changeDue: const Money.shillings(30),
      ),
    ];

    shift = CashShift(
      shiftId: 'SHIFT-20261006-01',
      openedAt: DateTime.now().subtract(const Duration(hours: 4)),
      openingFloat: const Money.shillings(5000),
      cashier: activeCashier,
    );

    // Record the past cash sale in the shift
    shift.cashSales = shift.cashSales + const Money.shillings(470);
    shift.movements.add(
      CashMovement(
        id: 'mov_sale_1041',
        timestamp: DateTime.now().subtract(const Duration(minutes: 42)),
        type: CashMovementType.saleCash,
        amount: const Money.shillings(470),
        reason: 'Sale RCP-2026-1041',
        cashier: activeCashier,
      ),
    );
  }

  // --- Cart Actions ---

  bool addToCart(PosProduct product, {void Function(String reason)? onRefused}) {
    final line = CartLine(
      productId: product.id,
      name: product.displayName,
      unitPrice: product.unitPrice,
      stock: product.stock,
    );
    final added = cart.add(line, onRefused: onRefused);
    if (added) notifyListeners();
    return added;
  }

  void changeQuantity(String productId, int delta, {void Function(String reason)? onRefused}) {
    cart.changeQuantity(productId, delta, onRefused: onRefused);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    selectedCustomer = null;
    notifyListeners();
  }

  void selectCustomer(PosCustomer? customer) {
    selectedCustomer = customer;
    notifyListeners();
  }

  // --- Sale Checkout ---

  SaleRecord completeSale({
    required SalePaymentMethod method,
    required String paymentReference,
    Money? cashTendered,
    Money? changeDue,
  }) {
    assert(cart.canCheckout, 'Cart must be non-empty and within stock limits');

    _receiptCounter++;
    final receiptNum = 'RCP-2026-$_receiptCounter';
    final now = DateTime.now();

    final items = cart.lines
        .map((l) => SaleRecordItem(
              productId: l.productId,
              productName: l.name,
              unitPrice: l.unitPrice,
              quantity: l.quantity,
              lineTotal: l.lineTotal,
            ))
        .toList();

    final saleSubtotal = cart.subtotal;
    final saleVat = cart.vatAmount;

    // 1. Deduct shelf stock
    for (final line in cart.lines) {
      final product = products.firstWhere((p) => p.id == line.productId);
      product.stock -= line.quantity;
    }

    // 2. If Credit, append to Customer Credit Ledger
    if (method == SalePaymentMethod.credit && selectedCustomer != null) {
      final newBalance = selectedCustomer!.currentBalance + saleSubtotal;
      selectedCustomer!.currentBalance = newBalance;
      selectedCustomer!.ledger.insert(
        0,
        CustomerLedgerEntry(
          id: 'led_sale_${now.millisecondsSinceEpoch}',
          timestamp: now,
          type: LedgerEntryType.saleDebit,
          amount: saleSubtotal,
          reference: receiptNum,
          runningBalance: newBalance,
        ),
      );
    }

    // 3. If Cash, append to Shift Cash movements
    if (method == SalePaymentMethod.cash) {
      shift.cashSales = shift.cashSales + saleSubtotal;
      shift.movements.insert(
        0,
        CashMovement(
          id: 'mov_$receiptNum',
          timestamp: now,
          type: CashMovementType.saleCash,
          amount: saleSubtotal,
          reason: 'Sale $receiptNum',
          cashier: activeCashier,
        ),
      );
    }

    // 4. Create Immutable Sale Record
    final record = SaleRecord(
      receiptNumber: receiptNum,
      timestamp: now,
      cashier: activeCashier,
      items: items,
      subtotal: saleSubtotal,
      vatAmount: saleVat,
      paymentMethod: method,
      paymentReference: paymentReference,
      customer: selectedCustomer,
      cashTendered: cashTendered,
      changeDue: changeDue,
    );

    sales.insert(0, record);

    // 5. Clear cart
    cart.clear();
    selectedCustomer = null;

    notifyListeners();
    return record;
  }

  // --- Sale Reversal (ADR-0001 & ADR-0002) ---

  void reverseSale(SaleRecord sale, String reason) {
    if (sale.isReversed) return;

    sale.status = SaleStatus.reversed;
    sale.reversalReason = reason;

    // 1. Return stock to shelf
    for (final item in sale.items) {
      final p = products.firstWhere((prod) => prod.id == item.productId, orElse: () => products.first);
      p.stock += item.quantity;
    }

    // 2. Reverse customer debit if credit
    if (sale.paymentMethod == SalePaymentMethod.credit && sale.customer != null) {
      final cust = sale.customer!;
      final newBal = Money(
        cust.currentBalance.minorUnits >= sale.subtotal.minorUnits
            ? cust.currentBalance.minorUnits - sale.subtotal.minorUnits
            : 0,
      );
      cust.currentBalance = newBal;
      cust.ledger.insert(
        0,
        CustomerLedgerEntry(
          id: 'rev_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: DateTime.now(),
          type: LedgerEntryType.reversal,
          amount: sale.subtotal,
          reference: 'Reversal: ${sale.receiptNumber}',
          runningBalance: newBal,
        ),
      );
    }

    // 3. Reverse cash in shift if cash
    if (sale.paymentMethod == SalePaymentMethod.cash) {
      shift.cashPaidOut = shift.cashPaidOut + sale.subtotal;
      shift.movements.insert(
        0,
        CashMovement(
          id: 'rev_mov_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: DateTime.now(),
          type: CashMovementType.expenseOut,
          amount: sale.subtotal,
          reason: 'Refund Reversal: ${sale.receiptNumber}',
          cashier: activeCashier,
        ),
      );
    }

    notifyListeners();
  }

  // --- Inventory Adjustments ---

  void adjustStock(String productId, int delta, String reason) {
    final prod = products.firstWhere((p) => p.id == productId);
    final newStock = prod.stock + delta;
    if (newStock < 0) return;
    prod.stock = newStock;
    notifyListeners();
  }

  // --- Customer Credit Payment ---

  void recordCustomerPayment(String customerId, Money amount, String reference) {
    final cust = customers.firstWhere((c) => c.id == customerId);
    final newBal = Money(
      cust.currentBalance.minorUnits >= amount.minorUnits ? cust.currentBalance.minorUnits - amount.minorUnits : 0,
    );
    cust.currentBalance = newBal;
    cust.ledger.insert(
      0,
      CustomerLedgerEntry(
        id: 'pmt_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        type: LedgerEntryType.paymentCredit,
        amount: amount,
        reference: reference,
        runningBalance: newBal,
      ),
    );

    // If payment was cash, it goes into till
    if (reference.toUpperCase().contains('CASH')) {
      shift.cashPaidIn = shift.cashPaidIn + amount;
      shift.movements.insert(
        0,
        CashMovement(
          id: 'mov_debt_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: DateTime.now(),
          type: CashMovementType.floatIn,
          amount: amount,
          reason: 'Debt payment from ${cust.name}',
          cashier: activeCashier,
        ),
      );
    }

    notifyListeners();
  }

  // --- Cash Drawer Drops & Expenses ---

  void recordCashDrop(Money amount, String reason, bool isCashIn) {
    if (isCashIn) {
      shift.cashPaidIn = shift.cashPaidIn + amount;
      shift.movements.insert(
        0,
        CashMovement(
          id: 'drop_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: DateTime.now(),
          type: CashMovementType.floatIn,
          amount: amount,
          reason: reason,
          cashier: activeCashier,
        ),
      );
    } else {
      shift.cashPaidOut = shift.cashPaidOut + amount;
      shift.movements.insert(
        0,
        CashMovement(
          id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: DateTime.now(),
          type: CashMovementType.expenseOut,
          amount: amount,
          reason: reason,
          cashier: activeCashier,
        ),
      );
    }
    notifyListeners();
  }

  // --- Shift Close ---

  void closeShift(Money countedCash) {
    shift.isClosed = true;
    shift.closingCounted = countedCash;
    shift.variance = Money(countedCash.minorUnits - shift.expectedCash.minorUnits);
    notifyListeners();
  }
}
