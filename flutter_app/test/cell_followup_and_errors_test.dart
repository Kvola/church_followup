import 'dart:async';
import 'dart:convert';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/providers/dashboard_provider.dart';
import 'package:church_followup_mobile/providers/followup_provider.dart';
import 'package:church_followup_mobile/providers/member_provider.dart';
import 'package:church_followup_mobile/providers/organization_provider.dart';
import 'package:church_followup_mobile/providers/todo_provider.dart';
import 'package:church_followup_mobile/screens/followups/followup_detail_screen.dart';
import 'package:church_followup_mobile/screens/followups/followup_form_screen.dart';
import 'package:church_followup_mobile/screens/home/home_screen.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:church_followup_mobile/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object result, {int status = 200}) => http.Response(jsonEncode(result), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Un ApiService devant un serveur qui répond toujours la même chose ; compte les appels.
(ApiService, List<String>) _api(FutureOr<http.Response> Function(http.Request) answer) {
  final calls = <String>[];
  final client = MockClient((request) async {
    calls.add(request.url.path);
    return answer(request);
  });
  return (ApiService(client: client)..configure(baseUrl: 'https://test', token: 't'), calls);
}

Future<ApiException> _failure(Future<dynamic> Function() run) async {
  try {
    await run();
  } on ApiException catch (e) {
    return e;
  }
  fail('Une ApiException était attendue');
}

// ─── Écrans ──────────────────────────────────────────────────────────

Future<List<Map<String, dynamic>>> _pump(WidgetTester tester, Widget screen, Map<String, dynamic> routes,
    {String role = 'manager', Map<String, dynamic> user = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final calls = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    final params = Map<String, dynamic>.from(jsonDecode(request.body)['params']);
    calls.add({'path': request.url.path, ...params});
    final key = routes.keys.firstWhere((k) => request.url.path.endsWith(k), orElse: () => '');
    return _json({'result': routes[key] ?? {'status': 'success'}});
  });
  final api = ApiService(client: client)..configure(baseUrl: 'https://test', token: 't');
  final auth = AuthProvider(api: api)
    ..debugSignIn({'id': 1, 'name': 'Fatou', 'role': role, 'church_id': 5, 'church_name': 'BNG Angré', ...user});
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => TodoProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => FollowupProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => MemberProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => OrganizationProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => DashboardProvider()..updateAuth(auth)),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
  return calls;
}

const _cells = {
  'status': 'success',
  'cells': [
    {'id': 1, 'name': 'Cellule Riviera', 'active': true, 'has_leader_account': true},
    {'id': 2, 'name': 'Cellule Château', 'active': true, 'has_leader_account': true},
    {'id': 3, 'name': 'Cellule Sans', 'active': true, 'has_leader_account': false},
  ],
};

final _oldMember = {
  'id': 7, 'name': 'YAO', 'first_name': 'Marc', 'person_profile': 'old_member', 'member_type': 'new',
  'prayer_cell_id': 2, 'proposed_followup_weeks': 6,
};

final _cellFollowup = {
  'id': 40, 'reference': 'SUV/40', 'member_name': 'YAO Marc', 'state': 'in_progress',
  'followed_by': 'cell', 'prayer_cell_id': 1, 'prayer_cell_name': 'Cellule Riviera',
  'followed_by_name': 'Cellule Riviera', 'evangelist_name': '', 'target_cell_id': 1,
  'total_weeks': 6, 'current_week': 1, 'progress': 16.7, 'average_score': 9.0,
  'weeks': [
    {'id': 1, 'week_number': 1, 'sunday_attendance': true, 'cell_attendance': true, 'call_made': true,
     'spiritual_state': 'good', 'score': 9, 'notes': '', 'reported_by_name': 'Fatou Cissé'},
  ],
};

void main() {
  // ─── Les erreurs, en mots de tous les jours ─────────────────────────
  test('un serveur en maintenance est dit tel quel, code compris, et une lecture est retentée', () async {
    final (api, calls) = _api((_) => http.Response('<html>Maintenance</html>', 503));
    final e = await _failure(() => api.call('/api/church/followups', {}));
    expect(e.message, contains('momentanément indisponible'));
    expect(e.message, contains('(erreur 503)'));
    expect(e.kind, ApiErrorKind.server);
    expect(calls, hasLength(3), reason: 'Une lecture est retentée');
  });

  test('une écriture n\'est jamais rejouée : le serveur a pu l\'enregistrer', () async {
    final (api, calls) = _api((_) => http.Response('', 503));
    await _failure(() => api.call('/api/church/followup/week/save', {}));
    expect(calls, hasLength(1));
    final (slow, _) = _api((_) => Completer<http.Response>().future);
    final e = await _failure(() => slow.call('/api/church/member/create', {}, timeout: const Duration(milliseconds: 20)));
    expect(e.message, ApiException.unsureWriteMessage);
  });

  test('pas de réseau, réponse inattendue, service absent, erreur technique', () async {
    final (offline, _) = _api((_) => throw http.ClientException('Failed host lookup: test'));
    expect((await _failure(() => offline.call('/api/church/member/create', {}))).message, ApiException.offlineMessage);
    final (html, _) = _api((_) => http.Response('<html>Portail Wi-Fi</html>', 200));
    expect((await _failure(() => html.call('/api/church/todo/x/save', {}))).message, ApiException.badResponseMessage);
    final (missing, _) = _api((_) => http.Response('Not Found', 404));
    final notFound = await _failure(() => missing.call('/api/church/cell/save', {}));
    expect(notFound.kind, ApiErrorKind.notFound);
    expect(notFound.message, contains('Mettez l\'application à jour'));
    final (crash, _) = _api((_) => _json({
          'error': {'data': {'name': 'builtins.KeyError', 'message': 'Traceback… KeyError: \'x\''}}
        }));
    final technical = await _failure(() => crash.call('/api/church/cell/save', {}));
    expect(technical.message, ApiException.serverMessage, reason: 'Pas de trace Python à l\'écran');
    final (refused, _) = _api((_) => _json({
          'error': {'data': {'name': 'odoo.exceptions.UserError', 'message': 'Cellule introuvable.'}}
        }));
    expect((await _failure(() => refused.call('/api/church/cell/save', {}))).message, 'Cellule introuvable.');
  });

  testWidgets('l\'écran d\'erreur montre « hors réseau » quand le réseau manque', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ErrorState(message: ApiException.offlineMessage))));
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
  });

  // ─── Le suivi par une cellule ──────────────────────────────────────
  testWidgets('le responsable de cellule a son onglet « Suivis »', (tester) async {
    await _pump(tester, const HomeScreen(), {}, role: 'cell_leader', user: {'prayer_cell_id': 1});
    expect(find.text('Suivis'), findsOneWidget);
    expect(find.text('Ma cellule'), findsOneWidget);
  });

  testWidgets('un ancien membre se confie à une cellule, la sienne proposée', (tester) async {
    final calls = await _pump(tester, FollowupFormScreen(initialMember: _oldMember), {
      '/cells': _cells,
      '/followup/create': {'status': 'success', 'followup': {'id': 41}},
    });
    expect(find.text('Cellule qui suit'), findsOneWidget);
    expect(find.text('Évangéliste'), findsNothing);
    expect(find.text('Cellule Château'), findsOneWidget, reason: 'Sa cellule, proposée');
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    expect(find.text('Cellule Sans — sans responsable connecté'), findsWidgets);
    await tester.tap(find.text('Cellule Riviera').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouvrir le suivi'));
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => '${c['path']}'.endsWith('/followup/create'));
    expect(sent['prayer_cell_id'], 1);
    expect(sent.containsKey('evangelist_id'), isFalse);
  });

  testWidgets('le rapport d\'une cellule demande la présence en cellule et dit qui l\'a rédigé', (tester) async {
    final calls = await _pump(tester, const FollowupDetailScreen(followupId: 40), {
      '/followup/detail': {'status': 'success', 'followup': _cellFollowup},
      '/followup/week/save': {'status': 'success', 'week': {'id': 2, 'score': 8}},
    }, role: 'cell_leader', user: {'prayer_cell_id': 1});
    expect(find.text('Suivi par : Cellule Riviera'), findsOneWidget);
    expect(find.text('Rédigé par Fatou Cissé'), findsOneWidget);
    expect(find.text('Cellule'), findsWidgets, reason: 'La présence en cellule de la semaine 1');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Présence en cellule'), findsOneWidget);
    await tester.tap(find.text('Présence en cellule'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => '${c['path']}'.endsWith('/week/save'));
    expect(sent['cell_attendance'], isTrue);
  });
}
