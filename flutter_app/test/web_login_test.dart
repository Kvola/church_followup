@TestOn('browser')
library;

import 'dart:convert';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/screens/auth/login_screen.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:church_followup_mobile/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPush extends PushService {
  @override
  Future<void> initialize() async {}
}

/// Version navigateur : l'adresse du serveur est vide (adresses relatives).
/// Un champ « URL du serveur » masqué mais présent dans le formulaire échouait
/// sa validation et bloquait l'envoi du code SANS RIEN AFFICHER (2026-10-16).
void main() {
  testWidgets('sur le web, « Recevoir un code » appelle le serveur, en relatif', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      return http.Response(jsonEncode({'result': {'status': 'success', 'identifier_masked': '+225 07 •• •• •• 05'}}),
          200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final auth = AuthProvider(api: ApiService(client: client), pushService: _NoPush());
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth, child: const MaterialApp(home: LoginScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Paramètres serveur'), findsNothing);
    expect(find.text('URL du serveur'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '07 00 05 05 05');
    await tester.tap(find.text('Recevoir un code'));
    await tester.pumpAndSettle();

    expect(urls.single.path, '/api/church/auth/request_otp');
    expect(urls.single.hasAuthority && urls.single.host != Uri.base.host, isFalse,
        reason: 'Aucune adresse de serveur compilée : la page appelle le serveur qui la sert');
    expect(find.textContaining('+225 07 •• •• •• 05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
