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
  DateTime? _authTokenExpiresAt;
  bool isConnected = false;
  String? lastError;
  bool get hasToken => _authToken != null && _authToken!.isNotEmpty;
  String? get authToken => _authToken;
  DateTime? get authTokenExpiresAt => _authTokenExpiresAt;

  void configure(String url) {
    baseUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  void setToken(String? token, {DateTime? expiresAt}) {
    _authToken = token;
    _authTokenExpiresAt = token == null
        ? null
        : expiresAt ?? _readTokenExpiry(token);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// Resolves a shop code to a server URL by treating the code as the
  /// subdomain slug on trendscore.co.ke.
  ///
  /// Examples:
  ///   gutagala  → https://www.gutagala.trendscore.co.ke/api
  ///   GUTAGALA  → https://www.gutagala.trendscore.co.ke/api  (lowercased)
  ///
  /// No lookup server needed — the code IS the subdomain.
  /// When the control-plane resolve API is ready this can be swapped in.
  Future<String> resolveShopCode(String code) async {
    lastError = null;
    final slug = code.toLowerCase().trim();
    if (slug.isEmpty) {
      lastError = 'Shop code cannot be empty.';
      return '';
    }
    return 'https://www.$slug.trendscore.co.ke/api';
  }

  /// Check server health
  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
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
    _authTokenExpiresAt = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone.replaceAll(RegExp(r'\D'), ''),
              'pin': pin,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic> ||
            decoded['token'] is! String ||
            _readTokenExpiry(decoded['token'] as String) == null) {
          lastError = 'The shop API returned an invalid login session.';
          return null;
        }
        final data = decoded;
        setToken(data['token'] as String);
        isConnected = true;
        return data;
      }
      isConnected = true;
      lastError =
          _messageFromResponse(res.body) ??
          'Shop API login failed (${res.statusCode}).';
      return null;
    } catch (e) {
      isConnected = false;
      lastError = 'Could not reach the shop API at $baseUrl.';
      debugPrint('API login failed: $e');
      return null;
    }
  }

  DateTime? _readTokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final expiry = payload is Map<String, dynamic> ? payload['exp'] : null;
      if (expiry is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        (expiry * 1000).round(),
        isUtc: true,
      );
    } on FormatException {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getStaffUsers() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/auth/users'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(
          decoded['data'] as List? ?? const [],
        );
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch staff accounts (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch staff accounts from the shop API.';
      debugPrint('API getStaffUsers error: $e');
    }
    return null;
  }

  Future<bool> changePin(String pin) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/change-pin'),
            headers: _headers,
            body: jsonEncode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not update PIN (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update PIN on the shop API.';
      debugPrint('API changePin error: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> createStaffUser(
    Map<String, dynamic> payload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/users'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 201 || res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not create staff account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create staff account on the shop API.';
      debugPrint('API createStaffUser error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateStaffUser(
    String id,
    Map<String, dynamic> payload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl/auth/users/$id'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not update staff account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update staff account on the shop API.';
      debugPrint('API updateStaffUser error: $e');
    }
    return null;
  }

  /// Fetch products catalog
  Future<List<Map<String, dynamic>>?> getProducts() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/products?limit=200&active=all'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        lastError = null;
        return List<Map<String, dynamic>>.from(json['data'] ?? []);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch products (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch products from the shop API.';
      debugPrint('API getProducts error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getCategories() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/categories'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        lastError = null;
        return List<Map<String, dynamic>>.from(jsonDecode(res.body));
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch categories (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch shop categories.';
      debugPrint('API getCategories error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> createCategory(String name) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/categories'),
            headers: _headers,
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 201)
        return Map<String, dynamic>.from(jsonDecode(res.body));
      lastError =
          _messageFromResponse(res.body) ??
          'Could not create category "$name" (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create category "$name".';
      debugPrint('API createCategory error: $e');
    }
    return null;
  }

  /// Create new product
  Future<Map<String, dynamic>?> createProduct(
    Map<String, dynamic> payload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/products'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 201) {
        return jsonDecode(res.body);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Product creation failed (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create the product on the shop API.';
      debugPrint('API createProduct error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> importProducts(
    List<Map<String, dynamic>> products,
  ) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/products/import'),
            headers: _headers,
            body: jsonEncode({'products': products}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          return List<Map<String, dynamic>>.from(decoded['data']);
        }
      }
      lastError =
          _messageFromResponse(res.body) ??
          'CSV import failed (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not import products on the shop API.';
      debugPrint('API importProducts error: $e');
    }
    return null;
  }

  /// Adjust product stock
  Future<bool> adjustStock(
    String productId,
    int delta,
    String type,
    String reason,
  ) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/products/$productId/adjust-stock'),
            headers: _headers,
            body: jsonEncode({'delta': delta, 'type': type, 'reason': reason}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Stock adjustment failed (${res.statusCode}).';
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
  Future<List<Map<String, dynamic>>?> getCustomers({
    String status = 'ACTIVE',
    String? search,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/customers').replace(
        queryParameters: {
          'status': status,
          'limit': '200',
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        lastError = null;
        return List<Map<String, dynamic>>.from(json['data'] ?? []);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch customer accounts (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch customer accounts from the shop API.';
      debugPrint('API getCustomers error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getCustomer(String customerId) async {
    lastError = null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/customers/$customerId'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return decoded;
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch customer account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch the customer account from the shop API.';
      debugPrint('API getCustomer error: $e');
    }
    return null;
  }

  /// Create customer
  Future<Map<String, dynamic>?> createCustomer(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/customers'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not create customer account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not create customer account on the shop API.';
      debugPrint('API createCustomer error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateCustomer(
    String customerId,
    Map<String, dynamic> payload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl/customers/$customerId'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not update customer account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update the customer account on the shop API.';
      debugPrint('API updateCustomer error: $e');
    }
    return null;
  }

  Future<bool> updateCustomerNotes(String customerId, String notes) async {
    lastError = null;
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl/customers/$customerId/notes'),
            headers: _headers,
            body: jsonEncode({'notes': notes}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not save customer notes (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not save customer notes on the shop API.';
      debugPrint('API updateCustomerNotes error: $e');
    }
    return false;
  }

  Future<bool> archiveCustomer(String customerId) async {
    lastError = null;
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/customers/$customerId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not archive customer (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not archive the customer on the shop API.';
      debugPrint('API archiveCustomer error: $e');
    }
    return false;
  }

  Future<bool> restoreCustomer(String customerId) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/customers/$customerId/restore'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not restore customer account (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not restore the customer account on the shop API.';
      debugPrint('API restoreCustomer error: $e');
    }
    return false;
  }

  Future<bool> permanentlyDeleteCustomer(String customerId) async {
    lastError = null;
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/customers/$customerId/permanent'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not permanently delete customer (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not permanently delete the customer on the shop API.';
      debugPrint('API permanentlyDeleteCustomer error: $e');
    }
    return false;
  }

  Future<List<Map<String, dynamic>>?> getCustomerDocuments(
    String customerId,
  ) async {
    lastError = null;
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/customers/$customerId/documents'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(res.body) as List);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch customer documents (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not fetch customer documents from the shop API.';
      debugPrint('API getCustomerDocuments error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> uploadCustomerDocument(
    String customerId, {
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/customers/$customerId/documents'),
            headers: _headers,
            body: jsonEncode({
              'fileName': fileName,
              'contentType': contentType,
              'contentBase64': base64Encode(bytes),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not upload customer document (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not upload the customer document to the shop API.';
      debugPrint('API uploadCustomerDocument error: $e');
    }
    return null;
  }

  Future<Uint8List?> downloadCustomerDocument(
    String customerId,
    String documentId,
  ) async {
    lastError = null;
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/customers/$customerId/documents/$documentId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return res.bodyBytes;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not download customer document (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not download the customer document from the shop API.';
      debugPrint('API downloadCustomerDocument error: $e');
    }
    return null;
  }

  Future<bool> deleteCustomerDocument(
    String customerId,
    String documentId,
  ) async {
    lastError = null;
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/customers/$customerId/documents/$documentId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not delete customer document (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not delete the customer document from the shop API.';
      debugPrint('API deleteCustomerDocument error: $e');
    }
    return false;
  }

  Future<List<Map<String, dynamic>>?> getSuppliers() async {
    lastError = null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/suppliers'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(
          decoded['data'] as List? ?? const [],
        );
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not fetch suppliers (${res.statusCode}).';
    } catch (error) {
      lastError = 'Could not fetch suppliers from the shop API.';
      debugPrint('API getSuppliers error: $error');
    }
    return null;
  }

  Future<Map<String, dynamic>?> createSupplier(
    Map<String, dynamic> payload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/suppliers'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 201) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not create supplier (${res.statusCode}).';
    } catch (error) {
      lastError = 'Could not create supplier on the shop API.';
      debugPrint('API createSupplier error: $error');
    }
    return null;
  }

  Future<bool> archiveSupplier(String supplierId) async {
    lastError = null;
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/suppliers/$supplierId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not remove supplier (${res.statusCode}).';
    } catch (error) {
      lastError = 'Could not remove supplier on the shop API.';
      debugPrint('API archiveSupplier error: $error');
    }
    return false;
  }

  /// Record customer debt payment
  Future<bool> recordCustomerPayment(
    String customerId,
    double amount,
    String method,
    String reference, {
    String? note,
  }) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/customers/$customerId/payments'),
            headers: _headers,
            body: jsonEncode({
              'amount': amount,
              'method': method,
              'reference': reference,
              if (note != null && note.isNotEmpty) 'note': note,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 201) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not record customer payment (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not record customer payment on the shop API.';
      debugPrint('API recordCustomerPayment error: $e');
    }
    return false;
  }

  /// Delete a customer (only succeeds if balance is zero)
  Future<({bool ok, String? error})> deleteCustomer(String customerId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/customers/$customerId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return (ok: true, error: null);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = (body['error'] as Map?)?.containsKey('message') == true
          ? body['error']['message'] as String
          : 'Could not delete customer.';
      return (ok: false, error: msg);
    } catch (e) {
      debugPrint('API deleteCustomer error: $e');
      return (ok: false, error: 'Could not reach the server.');
    }
  }

  /// Fetch sales
  Future<List<Map<String, dynamic>>?> getSales() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/sales?limit=50'), headers: _headers)
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
  Future<Map<String, dynamic>?> submitSale(
    Map<String, dynamic> salePayload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/sales'),
            headers: _headers,
            body: jsonEncode(salePayload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      }
      if (res.statusCode == 409) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> &&
            decoded['error'] is Map<String, dynamic>) {
          final error = decoded['error'] as Map<String, dynamic>;
          final details = error['details'];
          if (error['code'] == 'DUPLICATE_SALE' &&
              details is Map<String, dynamic> &&
              details['receiptNumber'] is String) {
            return {
              'data': {
                'receiptNumber': details['receiptNumber'],
                'saleId': details['saleId'],
                'total': details['total'],
                'customerId': details['customerId'],
              },
              'duplicate': true,
            };
          }
        }
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Could not record the sale (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not record the sale on the shop API.';
      debugPrint('API submitSale error: $e');
    }
    return null;
  }

  /// Reverse a sale (append-only reversing entries)
  Future<bool> reverseSale(String saleId, String reason) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/sales/$saleId/reverse'),
            headers: _headers,
            body: jsonEncode({'reason': reason}),
          )
          .timeout(const Duration(seconds: 5));
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
      final res = await http
          .delete(Uri.parse('$baseUrl/products/$productId'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Product deactivation failed (${res.statusCode}).';
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
      final res = await http
          .patch(
            Uri.parse('$baseUrl/products/$productId'),
            headers: _headers,
            body: jsonEncode({'active': active}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return true;
      lastError =
          _messageFromResponse(res.body) ??
          'Could not update product status (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update product status on the shop API.';
      debugPrint('API setProductActive error: $e');
    }
    return false;
  }

  /// Update an existing product (PATCH).
  /// Returns the decoded response map on success, or null on failure.
  Future<Map<String, dynamic>?> updateProduct(
    String productId,
    Map<String, dynamic> payload,
  ) async {
    lastError = null;
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl/products/$productId'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      lastError =
          _messageFromResponse(res.body) ??
          'Product update failed (${res.statusCode}).';
    } catch (e) {
      lastError = 'Could not update the product on the shop API.';
      debugPrint('API updateProduct error: $e');
    }
    return null;
  }

  /// Fetch analytics / dashboard summary
  Future<Map<String, dynamic>?> getDashboardReport() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/business/reports/dashboard'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('API getDashboardReport error: $e');
    }
    return null;
  }

  // ── Delivery config ─────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getDeliveryConfig() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/delivery/config'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('API getDeliveryConfig error: $e');
    }
    return null;
  }

  Future<bool> updateDeliveryConfig(double baseFee, double distanceTopupRate) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/delivery/config'),
        headers: _headers,
        body: jsonEncode({'baseFee': baseFee, 'distanceTopupRate': distanceTopupRate}),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('API updateDeliveryConfig error: $e');
      return false;
    }
  }

  // ── Delivery orders ─────────────────────────────────────────────────

  Future<Map<String, dynamic>?> createDeliveryOrder(Map<String, dynamic> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/delivery/orders'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 201) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('API createDeliveryOrder error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getDeliveryOrders({String? status, int page = 1}) async {
    try {
      final params = <String, String>{'page': '$page', 'limit': '50'};
      if (status != null) params['status'] = status;
      final uri = Uri.parse('$baseUrl/delivery/orders').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('API getDeliveryOrders error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> assignRider(String orderId, String riderId) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/delivery/orders/$orderId/assign'),
        headers: _headers,
        body: jsonEncode({'riderId': riderId}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('API assignRider error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateDeliveryStatus(
    String orderId,
    String status, {
    String? failureReason,
  }) async {
    try {
      final body = <String, dynamic>{'status': status};
      if (failureReason != null) body['failureReason'] = failureReason;
      final res = await http.patch(
        Uri.parse('$baseUrl/delivery/orders/$orderId/status'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('API updateDeliveryStatus error: $e');
    }
    return null;
  }

  Future<bool> cancelDeliveryOrder(String orderId, String reason) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/delivery/orders/$orderId/cancel'),
        headers: _headers,
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('API cancelDeliveryOrder error: $e');
      return false;
    }
  }

  // ── Rider management ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>?> getRiders() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/delivery/riders'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(res.body) as List);
      }
    } catch (e) {
      debugPrint('API getRiders error: $e');
    }
    return null;
  }

  Future<bool> initiateRiderPayout(String riderId, double amount, String mpesaPhone) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/delivery/riders/$riderId/payout'),
        headers: _headers,
        body: jsonEncode({'amount': amount, 'mpesaPhone': mpesaPhone}),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 201;
    } catch (e) {
      debugPrint('API initiateRiderPayout error: $e');
      return false;
    }
  }

  // ── Rider-scoped endpoints ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>?> getRiderOrders() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/delivery/rider/orders'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(res.body) as List);
      }
    } catch (e) {
      debugPrint('API getRiderOrders error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getRiderEarnings() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/delivery/rider/earnings'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('API getRiderEarnings error: $e');
    }
    return null;
  }
}
