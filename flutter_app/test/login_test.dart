import 'dart:convert';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/screens/auth/login_screen.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:church_followup_mobile/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sans Firebase : la connexion ne doit pas dépendre des notifications.
class _NoPush extends PushService {
  @override
  Future<void> initialize() async {}
  @override
  String get deviceLabel => 'Test';
}

void main() {
  testWidgets('numéro, puis code : la session s\'ouvre et propose les deux églises', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final params = Map<String, dynamic>.from(jsonDecode(request.body)['params']);
      calls.add({'path': request.url.path, 'auth': request.headers['Authorization'], ...params});
      final Map<String, dynamic> result;
      if (request.url.path.endsWith('/auth/request_otp')) {
        result = {'status': 'success', 'identifier_masked': '+225 07 •• •• •• 01', 'debug_otp': '123456'};
      } else if (request.url.path.endsWith('/auth/verify_otp')) {
        result = params['code'] == '123456'
            ? {
                'status': 'success',
                'token': 'jeton-de-session-assez-long-pour-etre-accepte',
                'user': {'id': 7, 'name': 'Awa Kone', 'role': 'evangelist', 'church_name': 'BNG Angré'},
                'accounts': [
                  {'id': 7, 'church_name': 'BNG Angré', 'role_label': 'Évangéliste'},
                  {'id': 9, 'church_name': 'BNG Yopougon', 'role_label': 'Responsable des évangélistes'},
                ],
              }
            : {'status': 'error', 'code': 'auth_failed', 'message': 'Code incorrect ou expiré.'};
      } else {
        result = {'status': 'success'};
      }
      return http.Response(jsonEncode({'result': result}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final auth = AuthProvider(api: ApiService(client: client), pushService: _NoPush());

    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.pumpAndSettle();

    // Build de test : aucune adresse compilée, l'écran montre donc d'emblée
    // les paramètres du serveur (c'est voulu) et l'on y saisit l'adresse.
    expect(find.text('URL du serveur'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'URL du serveur'), 'https://test');
    await tester.enterText(find.byType(TextFormField).first, '07 00 00 00 01');
    await tester.ensureVisible(find.text('Recevoir un code'));
    await tester.tap(find.text('Recevoir un code'));
    await tester.pumpAndSettle();
    expect(calls.last['path'], '/api/church/auth/request_otp');
    expect(calls.last['auth'], isNull, reason: 'Pas de session avant le code');
    expect(find.textContaining('+225 07 •• •• •• 01'), findsOneWidget);

    // Un mauvais code laisse sur l'écran, message à l'appui.
    await tester.enterText(find.byType(TextFormField).first, '000000');
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, isFalse);
    expect(find.text('Code incorrect ou expiré.'), findsOneWidget);

    // Le bon code ouvre la session dès le sixième chiffre.
    await tester.enterText(find.byType(TextFormField).first, '123456');
    await tester.pumpAndSettle();
    expect(calls.last['identifier'], '07 00 00 00 01');
    expect(auth.isAuthenticated, isTrue);
    expect(auth.userName, 'Awa Kone');
    expect(auth.hasSeveralAccounts, isTrue);

    // La suite des appels porte le jeton dans l'en-tête.
    await auth.api.call('/api/church/dashboard', {});
    expect(calls.last['auth'], 'Bearer jeton-de-session-assez-long-pour-etre-accepte');

    // Le compte à rebours de renvoi ne doit pas survivre à l'écran.
    await tester.pumpWidget(const SizedBox());
  });
}
