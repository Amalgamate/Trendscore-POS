import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiService.instance.setToken(null);
    ApiService.instance.configure('http://localhost:4000');
  });

  test('local stock adjustments persist across app reloads', () async {
    final state = PosState(includeDemoProducts: true);
    final product = state.products.first;
    final expectedStock = product.stock + 4;

    await state.adjustStock(product.id, 4, 'Local stock receipt');

    final reloadedState = PosState(includeDemoProducts: true);
    await reloadedState.loadInitialState();

    expect(
      reloadedState.products.firstWhere((item) => item.id == product.id).stock,
      expectedStock,
    );
  });

  test('remote stock adjustments update the API and persist locally', () async {
    const productId = '11111111-1111-4111-8111-111111111111';
    ApiService.instance
      ..configure('https://shop.example.test/api')
      ..setToken(
        'test-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

    final product = PosState(
      includeDemoProducts: true,
    ).products.first.copyWith(id: productId, stock: 2);
    final state = PosState(includeDemoProducts: false)..products = [product];

    await http.runWithClient(
      () => state.adjustStock(productId, 5, 'Stock delivery'),
      () => MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/products/$productId/adjust-stock');
        expect(jsonDecode(request.body), {
          'delta': 5,
          'type': 'ADJUSTMENT_IN',
          'reason': 'Stock delivery',
        });
        return http.Response(
          jsonEncode({'productId': productId, 'newStock': 8, 'delta': 5}),
          200,
        );
      }),
    );
    expect(state.products.single.stock, 8);

    final reloadedState = PosState(includeDemoProducts: false);
    await reloadedState.loadInitialState();
    expect(reloadedState.products.single.stock, 8);
  });

  test('failed remote adjustments leave local stock unchanged', () async {
    const productId = '22222222-2222-4222-8222-222222222222';
    ApiService.instance
      ..configure('https://shop.example.test/api')
      ..setToken(
        'test-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

    final product = PosState(
      includeDemoProducts: true,
    ).products.first.copyWith(id: productId, stock: 2);
    final state = PosState(includeDemoProducts: false)..products = [product];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('products_json', jsonEncode([product.toJson()]));

    await expectLater(
      http.runWithClient(
        () => state.adjustStock(productId, 5, 'Stock delivery'),
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Shop API unavailable'}),
            503,
          ),
        ),
      ),
      throwsA(isA<PosException>()),
    );

    expect(state.products.single.stock, 2);
    final reloadedState = PosState(includeDemoProducts: false);
    await reloadedState.loadInitialState();
    expect(reloadedState.products.single.stock, 2);
  });
}
