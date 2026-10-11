import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shop_pos/pos_state.dart';
import 'package:shop_pos/services/api_service.dart';
import 'package:shop_pos/theme/app_theme.dart';
import 'package:shop_pos/views/delivery_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const transparentPng = <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    13,
    73,
    68,
    65,
    84,
    8,
    215,
    99,
    248,
    207,
    192,
    240,
    31,
    0,
    5,
    0,
    1,
    255,
    137,
    153,
    61,
    29,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];

  Map<String, dynamic> location({
    required DateTime recordedAt,
    double accuracy = 12,
  }) => {
    'latitude': -1.286389,
    'longitude': 36.817223,
    'accuracy': accuracy,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };

  testWidgets('puts consented stale fixes first and shows GPS accuracy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final activeDeliveries = [
      {
        'id': 'fresh',
        'status': 'ASSIGNED',
        'recipientName': 'Fresh delivery',
        'deliveryAddress': 'Westlands',
        'sharingEnabled': true,
        'rider': {'fullName': 'Fresh Rider'},
        'location': location(recordedAt: now, accuracy: 18),
      },
      {
        'id': 'stale',
        'status': 'IN_TRANSIT',
        'recipientName': 'Stale delivery',
        'deliveryAddress': 'Kilimani',
        'sharingEnabled': true,
        'rider': {'fullName': 'Stale Rider'},
        'location': location(
          recordedAt: now.subtract(const Duration(minutes: 4)),
          accuracy: 42,
        ),
      },
      {
        'id': 'no-fix',
        'status': 'ASSIGNED',
        'recipientName': 'Waiting delivery',
        'deliveryAddress': 'Parklands',
        'sharingEnabled': true,
        'rider': {'fullName': 'Waiting Rider'},
        'location': null,
      },
      {
        'id': 'private',
        'status': 'ASSIGNED',
        'recipientName': 'Private delivery',
        'deliveryAddress': 'CBD',
        'sharingEnabled': false,
        'rider': {'fullName': 'Private Rider'},
        'location': null,
      },
    ];

    ApiService.instance
      ..configure('https://shop.example.test/api')
      ..setToken(
        'test-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

    final state = PosState()
      ..currentLoggedInUser = PosUser(
        id: 'manager',
        fullName: 'Shop Manager',
        phone: '254700000000',
        role: PosUserRole.manager,
      );

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildRetailOsTheme(),
            home: DeliveryView(state: state),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Live map'));
        await tester.pumpAndSettle();

        expect(find.text('4 active'), findsOneWidget);
        expect(find.text('2 need attention'), findsOneWidget);
        expect(find.text('GPS accuracy ±42 m'), findsOneWidget);
        expect(find.text('Needs update'), findsOneWidget);

        final stalePosition = tester.getTopLeft(find.text('Stale delivery'));
        final waitingPosition = tester.getTopLeft(
          find.text('Waiting delivery'),
        );
        final freshPosition = tester.getTopLeft(find.text('Fresh delivery'));
        final privatePosition = tester.getTopLeft(
          find.text('Private delivery'),
        );
        expect(stalePosition.dy, lessThan(waitingPosition.dy));
        expect(waitingPosition.dy, lessThan(freshPosition.dy));
        expect(freshPosition.dy, lessThan(privatePosition.dy));

        await tester.tap(find.text('Fresh delivery'));
        await tester.pumpAndSettle();
        expect(find.text('Fresh Rider · Assigned'), findsNWidgets(2));
        expect(find.textContaining('±18 m'), findsNWidgets(2));

        await tester.tap(find.text('Waiting delivery'));
        await tester.pumpAndSettle();
        expect(find.text('Waiting for first fix'), findsOneWidget);

        await tester.tap(find.text('Private delivery'));
        await tester.pumpAndSettle();
        expect(find.text('Location sharing off'), findsNWidgets(2));

        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildRetailOsTheme(),
            home: DeliveryView(state: state),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Live map'));
        await tester.pumpAndSettle();
        final mobileLayoutError = tester.takeException();
        expect(
          mobileLayoutError,
          isNull,
          reason: mobileLayoutError is FlutterError
              ? mobileLayoutError.toStringDeep()
              : '$mobileLayoutError',
        );
        expect(find.text('2 need attention'), findsOneWidget);
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('.png')) {
          return http.Response.bytes(transparentPng, 200);
        }
        if (request.url.path.endsWith('/delivery/locations/active')) {
          return http.Response(jsonEncode(activeDeliveries), 200);
        }
        if (request.url.path.endsWith('/delivery/orders')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.url.path.endsWith('/delivery/riders')) {
          return http.Response('[]', 200);
        }
        return http.Response('Not found', 404);
      }),
    );
  });
}
