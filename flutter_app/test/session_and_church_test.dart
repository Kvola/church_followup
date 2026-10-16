import 'dart:async';
import 'dart:convert';

import 'package:church_followup_mobile/main.dart';
import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/screens/auth/login_screen.dart';
import 'package:church_followup_mobile/screens/settings/settings_screen.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:church_followup_mobile/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPush extends PushService {
  @override
  Future<void> initialize() async {}
  @override
  String get deviceLabel => 'Test';
}

/// L'app entière, devant un serveur factice. `hang` : routes qui ne répondent
/// jamais (réseau perdu).
Future<({AuthProvider auth, List<String> calls})> _app(WidgetTester tester, Map<String, dynamic> user,
    {Set<String> hang = const {}, Map<String, Map<String, dynamic>> routes = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final calls = <String>[];
  final client = MockClient((request) async {
    calls.add(request.url.path);
    if (hang.any(request.url.path.endsWith)) return Completer<http.Response>().future;
    final key = routes.keys.firstWhere((k) => request.url.path.endsWith(k), orElse: () => '');
    return http.Response(jsonEncode({'result': routes[key] ?? {'status': 'success'}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final api = ApiService(client: client);
  final auth = AuthProvider(api: api, pushService: _NoPush());
  await tester.pumpWidget(ChurchFollowupApp(auth: auth));
  await tester.pumpAndSettle();
  api.configure(baseUrl: 'https://test', token: 'jeton-de-session-assez-long-pour-etre-accepte');
  auth.debugSignIn(user);
  await tester.pumpAndSettle();
  return (auth: auth, calls: calls);
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Plus'));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(GridView), const Offset(0, -1000));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Paramètres'));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsScreen), findsOneWidget);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
  await tester.pumpAndSettle();
}

const _manager = {'id': 3, 'name': 'Awa Kone', 'role': 'manager', 'church_id': 5, 'church_name': 'BNG Angré'};
const _admin = {'id': 1, 'name': 'Admin', 'role': 'super_admin', 'church_id': false, 'church_name': ''};

void main() {
  testWidgets('se déconnecter depuis Paramètres ramène à la connexion, même sans réseau', (tester) async {
    final app = await _app(tester, _manager, hang: {'/auth/logout', '/device/unregister'});
    await _openSettings(tester);
    await _scrollToEnd(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Déconnexion'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Déconnexion'));
    // Le serveur ne répond pas : quelques secondes au plus, pas plusieurs minutes.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(app.auth.isAuthenticated, isFalse);
    expect(app.calls, contains('/api/church/auth/logout'));
    expect(find.byType(SettingsScreen), findsNothing, reason: 'Paramètres ne reste pas affiché');
    expect(find.byType(LoginScreen), findsOneWidget);
    // Les requêtes restées sans réponse finissent par expirer d'elles-mêmes.
    await tester.pump(const Duration(seconds: 120));
  });

  testWidgets('seul l\'administrateur se voit proposer « Changer d\'église »', (tester) async {
    await _app(tester, _manager);
    await _openSettings(tester);
    expect(find.text('Changer d\'église'), findsNothing);
  });

  testWidgets('l\'administrateur choisit une église et revient à l\'accueil de celle-ci', (tester) async {
    final app = await _app(tester, _admin, routes: {
      '/churches': {
        'status': 'success',
        'churches': [
          {'id': 5, 'name': 'BNG Angré', 'region': 'Abidjan', 'active': true},
        ],
      },
      '/auth/set_church': {
        'status': 'success',
        'message': 'Vous gérez BNG Angré',
        'user': {..._admin, 'church_id': 5, 'church_name': 'BNG Angré'},
      },
    });
    await _openSettings(tester);
    await tester.tap(find.text('Changer d\'église'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BNG Angré'));
    await tester.pumpAndSettle();

    expect(app.calls, contains('/api/church/auth/set_church'));
    expect(app.auth.churchId, 5);
    expect(find.byType(SettingsScreen), findsNothing, reason: 'retour à l\'accueil de la nouvelle église');
  });

  testWidgets('rien ne passe sous la barre de navigation du téléphone', (tester) async {
    // Android 15 : l'app est dessinée sous une barre système de 48 points.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 144);
    tester.view.viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);
    const visibleBottom = 2340 / 3 - 48;

    await _app(tester, _manager);
    expect(tester.getRect(find.byType(NavigationBar)).bottom, lessThanOrEqualTo(visibleBottom));
    await _openSettings(tester);
    await _scrollToEnd(tester);
    expect(tester.getRect(find.widgetWithText(OutlinedButton, 'Déconnexion')).bottom,
        lessThanOrEqualTo(visibleBottom));
  });
}
