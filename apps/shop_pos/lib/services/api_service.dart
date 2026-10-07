import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for communicating with the Retail OS shop-api.
/// Supports online/offline detection, JWT auth headers, and fallback.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String baseUrl = 'http://localhost:4000';
  String? _authToken;
  bool isConnected = false;
  String? lastError;
  bool get hasToken => _authToken != null && _authToken!.isNotEmpty;

  void configure(String url) {
    baseUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  void setToken(String? token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Check server health
  Future<bool> checkHealth() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
      isConnected = (res.statusCode == 200);
      return isConnected;
    } catch (_) {
      isConnected = false;
      return false;
    }
  }

  /// Cashier login with PIN
  Future<Map<String, dynamic>?> login(String phone, String pin) async {
    lastError = null;
    _authToken = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone.replaceAll(RegExp(r'\D'), ''), 'pin': pin}),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _authToken = data['token'];
        isConnected = true;
        return data;
      }
      isConnected = true;
      lastError = _messageFromResponse(res.body) ?? 'Shop API login failed (${res.statusCode}).';
      return null;
    } catch (e) {
      isConnected = false;
      lastError = 'Could not reach the shop API at $baseUrl.';
      debugPrint('API login failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getStaffUsers() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/auth/users'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(decoded['data'] as List? ?? const []);
      }
      lastError = _messageFromResponse(res.body) ?? 'Could not fetch staff accounts (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch staff accounts from the shop API.';
      debugPrint('API getStaffUsers error: $e');
    }
    return null;
  }

  Future<bool> changePin(String pin) async {
    lastError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/change-pin'),
        headers: _headers,
        body: jsonEncode({'pin': pin}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return true;
      lastError = _messageFromResponse(res.body) ?? 'Could not update PIN (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update PIN on the shop API.';
      debugPrint('API changePin error: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> createStaffUser(Map<String, dynamic> payload) async {
    lastError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/users'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 201 || res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      lastError = _messageFromResponse(res.body) ?? 'Could not create staff account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create staff account on the shop API.';
      debugPrint('API createStaffUser error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateStaffUser(String id, Map<String, dynamic> payload) async {
    lastError = null;
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/auth/users/$id'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      lastError = _messageFromResponse(res.body) ?? 'Could not update staff account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update staff account on the shop API.';
      debugPrint('API updateStaffUser error: $e');
    }
    return null;
  }

  /// Fetch products catalog
  Future<List<Map<String, dynamic>>?> getProducts() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/products?limit=200&active=all'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        lastError = null;
        return List<Map<String, dynamic>>.from(json['data'] ?? []);
      }
      lastError = _messageFromResponse(res.body) ?? 'Could not fetch products (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch products from the shop API.';
      debugPrint('API getProducts error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getCategories() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/categories'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        lastError = null;
        return List<Map<String, dynamic>>.from(jsonDecode(res.body));
      }
      lastError = _messageFromResponse(res.body) ?? 'Could not fetch categories (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch shop categories.';
      debugPrint('API getCategories error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> createCategory(String name) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/categories'),
        headers: _headers,
        body: jsonEncode({'name': name}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 201) return Map<String, dynamic>.from(jsonDecode(res.body));
      lastError = _messageFromResponse(res.body) ?? 'Could not create category "$name" (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create category "$name".';
      debugPrint('API createCategory error: $e');
    }
    return null;
  }

  /// Create new product
  Future<Map<String, dynamic>?> createProduct(Map<String, dynamic> payload) async {
    lastError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/products'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 201) {
        return jsonDecode(res.body);
      }
      lastError = _messageFromResponse(res.body) ?? 'Product creation failed (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create the product on the shop API.';
      debugPrint('API createProduct error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> importProducts(List<Map<String, dynamic>> products) async {
    lastError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/products/import'),
        headers: _headers,
        body: jsonEncode({'products': products}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          return List<Map<String, dynamic>>.from(decoded['data']);
        }
      }
      lastError = _messageFromResponse(res.body) ?? 'CSV import failed (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not import products on the shop API.';
      debugPrint('API importProducts error: $e');
    }
    return null;
  }

  /// Adjust product stock
  Future<bool> adjustStock(String productId, int delta, String type, String reason) async {
    lastError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/products/$productId/adjust-stock'),
        headers: _headers,
        body: jsonEncode({'delta': delta, 'type': type, 'reason': reason}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError = _messageFromResponse(res.body) ?? 'Stock adjustment failed (${res.statusCode}).';
      return false;
    } catch (e) {
      lastError = 'Could not adjust product stock on the shop API.';
      debugPrint('API adjustStock error: $e');
      return false;
    }
  }

  String? _messageFromResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) return error['message'] as String?;
        return decoded['message'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch customers
  Future<List<Map<String, dynamic>>?> getCustomers() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/customers'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(json['data'] ?? []);
      }
    } catch (e) {
      debugPrint('API getCustomers error: $e');
    }
    return null;
  }

  /// Create customer
  Future<Map<String, dynamic>?> createCustomer(Map<String, dynamic> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/customers'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 201) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('API createCustomer error: $e');
    }
    return null;
  }

  /// Record customer debt payment
  Future<bool> recordCustomerPayment(String customerId, double amount, String method, String reference) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/customers/$customerId/payments'),
        headers: _headers,
        body: jsonEncode({
          'amount': amount,
          'method': method,
          'reference': reference,
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 201;
    } catch (e) {
      debugPrint('API recordCustomerPayment error: $e');
      return false;
    }
  }

  /// Fetch sales
  Future<List<Map<String, dynamic>>?> getSales() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sales?limit=50'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(json['data'] ?? []);
      }
    } catch (e) {
      debugPrint('API getSales error: $e');
    }
    return null;
  }

  /// Submit completed sale
  Future<Map<String, dynamic>?> submitSale(Map<String, dynamic> salePayload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sales'),
        headers: _headers,
        body: jsonEncode(salePayload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('API submitSale error: $e');
    }
    return null;
  }

  /// Reverse a sale (append-only reversing entries)
  Future<bool> reverseSale(String saleId, String reason) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sales/$saleId/reverse'),
        headers: _headers,
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('API reverseSale error: $e');
      return false;
    }
  }

  /// Soft-delete a product (sets active=false on the API).
  /// Returns true if the server responded 200.
  Future<bool> deactivateProduct(String productId) async {
    lastError = null;
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/products/$productId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError = _messageFromResponse(res.body) ?? 'Product deactivation failed (${res.statusCode}).';
      return false;
    } catch (e) {
      lastError = 'Could not deactivate the product on the shop API.';
      debugPrint('API deactivateProduct error: $e');
      return false;
    }
  }

  Future<bool> setProductActive(String productId, bool active) async {
    lastError = null;
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/products/$productId'),
        headers: _headers,
        body: jsonEncode({'active': active}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError = _messageFromResponse(res.body) ?? 'Could not update product status (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update product status on the shop API.';
      debugPrint('API setProductActive error: $e');
    }
    return false;
  }

  /// Update an existing product (PATCH).
  /// Returns the decoded response map on success, or null on failure.
  Future<Map<String, dynamic>?> updateProduct(
      String productId, Map<String, dynamic> payload) async {
    lastError = null;
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/products/$productId'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      lastError = _messageFromResponse(res.body) ?? 'Product update failed (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update the product on the shop API.';
      debugPrint('API updateProduct error: $e');
    }
    return null;
  }

  /// Fetch analytics / dashboard summary
  Future<Map<String, dynamic>?> getDashboardReport() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/business/reports/dashboard'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('API getDashboardReport error: $e');
    }
    return null;
  }
}
