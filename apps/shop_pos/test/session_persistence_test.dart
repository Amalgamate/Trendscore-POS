import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiService.instance.setToken(null);
  });

  test(
    'an authenticated session survives app reload until its expiry',
    () async {
      final expiry = DateTime.now().toUtc().add(const Duration(hours: 8));
      const token = 'test.jwt.token';
      ApiService.instance.setToken(token, expiresAt: expiry);
      final state = PosState(includeDemoProducts: false);
      final user = PosUser(
        id: 'user-1',
        fullName: 'Shop Owner',
        phone: '254700000001',
        role: PosUserRole.owner,
      );

      await state.persistSession(user, tabIndex: 3);
      final reloadedState = PosState(includeDemoProducts: false);
      await reloadedState.loadInitialState();

      expect(reloadedState.currentLoggedInUser?.id, user.id);
      expect(reloadedState.savedTabIndex, 3);
      expect(ApiService.instance.authToken, token);
      expect(
        reloadedState.sessionExpiresAt,
        DateTime.fromMillisecondsSinceEpoch(
          expiry.millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      expect(PosState.sessionDurationMinutes, 480);

      await reloadedState.logout();
      expect(ApiService.instance.hasToken, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session_token'), isNull);
      expect(prefs.getString('session_user_json'), isNull);
      expect(prefs.getInt('session_expires_at'), isNull);
    },
  );

  test('an expired session is cleared when the app starts', () async {
    final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    const token = 'expired.jwt.token';
    ApiService.instance.setToken(token, expiresAt: expiry);
    final state = PosState(includeDemoProducts: false);
    await state.persistSession(
      PosUser(
        id: 'user-1',
        fullName: 'Shop Owner',
        phone: '254700000001',
        role: PosUserRole.owner,
      ),
    );

    final reloadedState = PosState(includeDemoProducts: false);
    await reloadedState.loadInitialState();

    expect(reloadedState.currentLoggedInUser, isNull);
    expect(ApiService.instance.hasToken, isFalse);
    expect(reloadedState.sessionExpiresAt, isNull);
  });

  test('API token expiry is read from its JWT payload', () {
    final expirySeconds =
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url
        .encode(utf8.encode('{"exp":$expirySeconds}'))
        .replaceAll('=', '');
    ApiService.instance.setToken('e30.$payload.signature');

    expect(
      ApiService.instance.authTokenExpiresAt?.millisecondsSinceEpoch,
      expirySeconds * 1000,
    );
  });
}
