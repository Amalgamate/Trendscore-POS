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
  bool get hasToken => _authToken != null && _authToken!.isNotEmpty;

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
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'pin': pin}),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _authToken = data['token'];
        isConnected = true;
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('API login failed: $e');
      return null;
    }
  }

  /// Fetch products catalog
  Future<List<Map<String, dynamic>>?> getProducts() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/products?limit=200'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(json['data'] ?? []);
      }
    } catch (e) {
      debugPrint('API getProducts error: $e');
    }
    return null;
  }

  /// Create new product
  Future<Map<String, dynamic>?> createProduct(Map<String, dynamic> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/products'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 201) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('API createProduct error: $e');
    }
    return null;
  }

  /// Adjust product stock
  Future<bool> adjustStock(String productId, int delta, String type, String reason) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/products/$productId/adjust-stock'),
        headers: _headers,
        body: jsonEncode({'delta': delta, 'type': type, 'reason': reason}),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('API adjustStock error: $e');
      return false;
    }
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
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/products/$productId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('API deactivateProduct error: $e');
      return false;
    }
  }

  /// Update an existing product (PATCH).
  /// Returns the decoded response map on success, or null on failure.
  Future<Map<String, dynamic>?> updateProduct(
      String productId, Map<String, dynamic> payload) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/products/$productId'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
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
