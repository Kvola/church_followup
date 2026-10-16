import 'dart:convert';

import 'package:church_followup_mobile/core/theme.dart';
import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/providers/dashboard_provider.dart';
import 'package:church_followup_mobile/providers/followup_provider.dart';
import 'package:church_followup_mobile/providers/member_provider.dart';
import 'package:church_followup_mobile/providers/organization_provider.dart';
import 'package:church_followup_mobile/providers/todo_provider.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'capture_theme.dart';
import 'demo_server.dart';

/// Photographier un écran de l'application, connecté sous [role], devant le
/// serveur de démonstration — avec le thème de production, des polices
/// réelles, les ombres rétablies et la densité ×3 d'un téléphone.
///
/// [role] vide : personne n'est connecté (écran de connexion).
Future<void> shoot(
  WidgetTester tester, {
  required String name,
  required Widget screen,
  String role = 'evangelist',
  Size size = const Size(390, 844),
  Future<void> Function(WidgetTester tester)? avantLaPhoto,
}) async {
  // Ombres rétablies pour la photo ; le harnais exige qu'on remette la
  // valeur d'origine AVANT la fin du test (d'où le finally, pas un tearDown).
  debugDisableShadows = false;
  try {
    await _shoot(tester, name: name, screen: screen, role: role, size: size, avantLaPhoto: avantLaPhoto);
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _shoot(
  WidgetTester tester, {
  required String name,
  required Widget screen,
  required String role,
  required Size size,
  Future<void> Function(WidgetTester tester)? avantLaPhoto,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  final client = MockClient((request) async {
    final params = Map<String, dynamic>.from(jsonDecode(request.body)['params'] as Map);
    return http.Response(jsonEncode({'result': demoResponse(request.url.path, params, role)}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final api = ApiService(client: client)..configure(baseUrl: 'https://demo', token: 'demo');
  final auth = AuthProvider(api: api);
  await tester.pump();
  if (role.isNotEmpty) auth.debugSignIn(demoUser(role));

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => DashboardProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => FollowupProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => MemberProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => OrganizationProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => TodoProvider()..updateAuth(auth)),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: captureTheme(AppTheme.light),
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
  // Les images d'assets ne sont décodées sous `flutter test` que si on le
  // demande, hors de l'horloge factice : sans cela le logo sort vide.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
  if (avantLaPhoto != null) {
    await avantLaPhoto(tester);
    await tester.pumpAndSettle();
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('formation/$name.png'));
}
