import 'dart:convert';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/providers/followup_provider.dart';
import 'package:church_followup_mobile/providers/member_provider.dart';
import 'package:church_followup_mobile/providers/organization_provider.dart';
import 'package:church_followup_mobile/providers/todo_provider.dart';
import 'package:church_followup_mobile/screens/checkpoints/checkpoint_list_screen.dart';
import 'package:church_followup_mobile/screens/followups/to_assign_screen.dart';
import 'package:church_followup_mobile/screens/members/member_form_screen.dart';
import 'package:church_followup_mobile/screens/todo/todo_screen.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Monte un écran devant un serveur factice : `routes` associe la fin du
/// chemin appelé à la réponse ; les appels sont retenus dans `calls`.
Future<List<Map<String, dynamic>>> pump(WidgetTester tester, Widget screen, Map<String, Map<String, dynamic>> routes,
    {bool authenticated = true}) async {
  SharedPreferences.setMockInitialValues({});
  final calls = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    final params = Map<String, dynamic>.from(jsonDecode(request.body)['params']);
    calls.add({'path': request.url.path, ...params});
    final key = routes.keys.firstWhere((k) => request.url.path.endsWith(k), orElse: () => '');
    return http.Response(jsonEncode({'result': routes[key] ?? {'status': 'success'}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final api = ApiService(client: client)..configure(baseUrl: 'https://test', token: 't');
  final auth = _AuthForTest(api: api);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => TodoProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => FollowupProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => MemberProvider()..updateAuth(auth)),
      ChangeNotifierProvider(create: (_) => OrganizationProvider()..updateAuth(auth)),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
  return calls;
}

/// Un responsable connecté, sans passer par le stockage sécurisé.
class _AuthForTest extends AuthProvider {
  _AuthForTest({required super.api});
  @override
  bool get isAuthenticated => true;
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Awa Kone', 'role': 'manager', 'default_followup_weeks': 6};
}

void main() {
  testWidgets('« À faire » liste les tâches avec leur résumé et mène à « À attribuer »', (tester) async {
    await pump(tester, const TodoScreen(), {
      '/todo': {
        'status': 'success',
        'count': 3,
        'summary': '1 décision(s) à prendre, 1 personne(s) à attribuer, 4 fiche(s) à compléter',
        'items': [
          {'kind': 'decision_due', 'followup_id': 5, 'title': 'Décision à prendre : Yao Konan', 'detail': 'Suivi arrivé à terme'},
          {'kind': 'to_assign', 'member_id': 9, 'title': 'À attribuer : Aya Bla', 'detail': '8 semaines — Événement d\'origine'},
          {'kind': 'to_complete', 'count': 4, 'title': '4 fiche(s) à compléter', 'detail': 'Le sexe manque'},
        ],
      },
      '/to_assign': {'status': 'success', 'members': [], 'interrupted': []},
    });
    expect(find.text('Décision à prendre : Yao Konan'), findsOneWidget);
    expect(find.textContaining('4 fiche(s) à compléter'), findsNWidgets(2));
    await tester.tap(find.text('À attribuer : Aya Bla'));
    await tester.pumpAndSettle();
    expect(find.byType(ToAssignScreen), findsOneWidget);
  });

  testWidgets('« À faire » vide félicite au lieu d\'afficher une liste blanche', (tester) async {
    await pump(tester, const TodoScreen(), {
      '/todo': {'status': 'success', 'count': 0, 'summary': '', 'items': []},
    });
    expect(find.text('Rien à faire pour l\'instant'), findsOneWidget);
  });

  testWidgets('« À attribuer » sépare nouvelles personnes et suivis interrompus', (tester) async {
    await pump(tester, const ToAssignScreen(), {
      '/to_assign': {
        'status': 'success',
        'members': [
          {'id': 9, 'name': 'Bla', 'first_name': 'Aya', 'proposed_followup_label': '8 semaines — Événement d\'origine (Camp)'}
        ],
        'interrupted': [
          {'id': 10, 'name': 'Toure', 'first_name': 'Ali', 'abandon_reason_label': 'A déménagé', 'abandon_note': 'Bouaké'}
        ],
      },
    });
    expect(find.text('À confier à un évangéliste (1)'), findsOneWidget);
    expect(find.text('8 semaines — Événement d\'origine (Camp)'), findsOneWidget);
    expect(find.text('Suivis interrompus (1)'), findsOneWidget);
    expect(find.text('A déménagé — Bouaké'), findsOneWidget);
    expect(find.text('Reprendre'), findsOneWidget);
  });

  testWidgets('un contrôle exige un résultat et envoie résultat et observations', (tester) async {
    final calls = await pump(
      tester,
      const CheckpointScreen(checkpoint: {
        'id': 3, 'member_name': 'Aya Bla', 'milestone': '3m', 'is_catchup': false,
        'service_count': 9, 'cell_count': 7, 'baptized': false, 'has_mentor': true,
      }),
      {'/checkpoint/save': {'status': 'success', 'member_type': 'integrated'}},
    );
    expect(find.text('9'), findsOneWidget, reason: 'Cultes des 90 derniers jours');
    final save = find.widgetWithText(FilledButton, 'Enregistrer le contrôle');
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(save, 200, scrollable: scrollable);
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'Pas de résultat, pas d\'enregistrement');
    await tester.ensureVisible(find.text('Oui, elle tient'));
    await tester.tap(find.text('Oui, elle tient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Assidue');
    await tester.scrollUntilVisible(save, 200, scrollable: scrollable);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final sent = calls.firstWhere((c) => c['path'].toString().endsWith('/checkpoint/save'));
    expect(sent['checkpoint_id'], 3);
    expect(sent['result'], 'favorable');
    expect(sent['notes'], 'Assidue');
  });

  testWidgets('la fiche membre s\'ouvre (listes vides comprises) et se verrouille sans charge', (tester) async {
    await pump(tester, const MemberFormScreen(memberId: 4), {
      '/member/detail': {
        'status': 'success',
        'member': {
          'id': 4, 'name': 'Bla', 'first_name': 'Aya', 'gender': '', 'to_complete': true,
          'marital_status': 'single', 'can_edit': false, 'journey': [], 'checkpoints': [],
        },
      },
      '/districts': {'status': 'success', 'districts': []},
      '/cells': {'status': 'success', 'cells': []},
      '/age_groups': {'status': 'success', 'age_groups': []},
      '/members': {'status': 'success', 'members': []},
    });
    expect(tester.takeException(), isNull, reason: 'Aucune erreur de rendu (clés en double, valeur hors liste)');
    expect(find.text('Fiche du membre'), findsOneWidget);
    expect(find.textContaining('Consultation seulement'), findsOneWidget);
  });
}
