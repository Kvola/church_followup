import 'dart:convert';
import 'dart:typed_data';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/providers/dashboard_provider.dart';
import 'package:church_followup_mobile/providers/followup_provider.dart';
import 'package:church_followup_mobile/providers/member_provider.dart';
import 'package:church_followup_mobile/providers/organization_provider.dart';
import 'package:church_followup_mobile/providers/todo_provider.dart';
import 'package:church_followup_mobile/screens/followups/to_assign_screen.dart';
import 'package:church_followup_mobile/screens/imports/import_screen.dart';
import 'package:church_followup_mobile/screens/members/member_form_screen.dart';
import 'package:church_followup_mobile/screens/organization/unit_forms.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une vraie session de test : le rôle se lit là où l'app le lit.
AuthProvider _auth(ApiService api, String role) => AuthProvider(api: api)
  ..debugSignIn({'id': 1, 'name': 'Awa', 'role': role, 'church_id': 5, 'church_name': 'BNG Angré'});

/// `routes` : fin du chemin → réponse ; une liste de réponses est servie dans l'ordre.
Future<List<Map<String, dynamic>>> _pump(WidgetTester tester, Widget screen, Map<String, dynamic> routes,
    {String role = 'manager'}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final calls = <Map<String, dynamic>>[];
  final served = <String, int>{};
  final client = MockClient((request) async {
    final params = Map<String, dynamic>.from(jsonDecode(request.body)['params']);
    calls.add({'path': request.url.path, ...params});
    final key = routes.keys.firstWhere((k) => request.url.path.endsWith(k), orElse: () => '');
    var answer = routes[key] ?? {'status': 'success'};
    if (answer is List) {
      final i = served[key] = (served[key] ?? -1) + 1;
      answer = answer[i.clamp(0, answer.length - 1)];
    }
    return http.Response(jsonEncode({'result': answer}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final api = ApiService(client: client)..configure(baseUrl: 'https://test', token: 't');
  final auth = _auth(api, role);
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

const _kinds = {
  'status': 'success',
  'kinds': [
    {'kind': 'district', 'label': 'Quartiers', 'description': 'Les quartiers.'},
    {'kind': 'prayer_cell', 'label': 'Cellules de prière', 'description': 'Les cellules.'},
  ],
};

/// Fait défiler le formulaire jusqu'à l'élément (la liste ne construit que le visible).
Future<Finder> _reveal(WidgetTester tester, Finder finder, {double step = 150}) async {
  await tester.scrollUntilVisible(finder, step, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  return finder;
}

/// « Importer » sur une carte (bouton tonal) ou dans la confirmation.
final _importButton = find.ancestor(of: find.text('Importer'), matching: find.byWidgetPredicate((w) => w is FilledButton));

Future<PickedImportFile?> _xlsx() async => PickedImportFile('cellules.xlsx', Uint8List.fromList([80, 75, 3, 4]));

Future<void> _importCells(WidgetTester tester) async {
  await tester.tap(_importButton.last);
  await tester.pumpAndSettle();
  expect(find.text('Importer Cellules de prière ?'), findsOneWidget);
  expect(find.textContaining('« cellules.xlsx » dans BNG Angré'), findsOneWidget);
  await tester.tap(_importButton.last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un import refusé dit, ligne par ligne, quoi corriger', (tester) async {
    final calls = await _pump(tester, const ImportScreen(pickFile: _xlsx), {
      '/import/kinds': _kinds,
      '/import/run': {
        'status': 'error',
        'code': 'import_refused',
        'ok': false,
        'message': "Rien n'a été importé : 2 erreur(s) à corriger dans le fichier.",
        'errors': ['Ligne 4 — Jour de réunion : « Funday » n\'est pas une valeur permise.', 'Ligne 6 : même fiche que la ligne 2.'],
        'warnings': [],
      },
    });
    expect(find.text('Cellules de prière'), findsOneWidget);
    expect(find.text('Partager'), findsNWidgets(2), reason: 'Sur le téléphone, le modèle se partage');
    await _importCells(tester);
    final sent = calls.lastWhere((c) => '${c['path']}'.endsWith('/import/run'));
    expect(sent['kind'], 'prayer_cell');
    expect(sent['filename'], 'cellules.xlsx');
    expect(base64Decode(sent['content_base64']), [80, 75, 3, 4]);
    expect(find.text('Rien n\'a été importé'), findsOneWidget);
    expect(find.text('À corriger dans le fichier (2)'), findsOneWidget);
    expect(find.textContaining('Ligne 4 — Jour de réunion'), findsOneWidget);
  });

  testWidgets('un import réussi dit ce qui a été créé et ce qu\'il faut savoir', (tester) async {
    await _pump(tester, const ImportScreen(pickFile: _xlsx), {
      '/import/kinds': _kinds,
      '/import/run': {
        'status': 'success',
        'ok': true,
        'message': 'Cellules de prière : 3 créé(s), 1 complété(s), 0 déjà à jour.',
        'errors': [],
        'warnings': ['Quartiers créés : Angré Château.'],
      },
    });
    await _importCells(tester);
    expect(find.text('Import réussi'), findsOneWidget);
    expect(find.textContaining('3 créé(s)'), findsOneWidget);
    expect(find.text('Quartiers créés : Angré Château.'), findsOneWidget);
  });

  testWidgets('un fichier qui n\'est pas un classeur est écarté avant tout envoi', (tester) async {
    final calls = await _pump(
      tester,
      ImportScreen(pickFile: () async => PickedImportFile('photo.jpg', Uint8List(3))),
      {'/import/kinds': _kinds},
    );
    await tester.tap(_importButton.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('« photo.jpg » n\'en est pas un'), findsOneWidget);
    expect(calls.where((c) => '${c['path']}'.endsWith('/import/run')), isEmpty);
  });

  testWidgets('le responsable crée une cellule : nom, quartiers, horaire, responsable', (tester) async {
    final calls = await _pump(tester, const CellFormScreen(), {
      '/districts': {
        'status': 'success',
        'districts': [
          {'id': 3, 'name': 'Riviera', 'active': true},
        ],
      },
      '/cell/save': {'status': 'success', 'cell': {'id': 9, 'name': 'Cellule Riviera'}},
    });
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom de la cellule *'), 'Cellule Riviera');
    await tester.tap(find.text('Riviera'));
    await tester.enterText(await _reveal(tester, find.widgetWithText(TextFormField, 'Téléphone')), '07 00 05 05 05');
    await tester.tap(await _reveal(tester, find.text('Enregistrer')));
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => '${c['path']}'.endsWith('/cell/save'));
    expect(sent['name'], 'Cellule Riviera');
    expect(sent['district_ids'], [3]);
    expect(sent['meeting_day'], 'friday');
    expect(sent['meeting_time'], '19:00');
    expect(sent['leader_phone'], '07 00 05 05 05');
    expect(sent.containsKey('cell_id'), isFalse);
  });

  testWidgets('le responsable de cellule ne change que l\'horaire et le lieu de la sienne', (tester) async {
    final calls = await _pump(
      tester,
      const CellFormScreen(cell: {'id': 9, 'name': 'Mienne', 'meeting_day': 'friday', 'meeting_time': '19:00'}),
      {'/cell/save': {'status': 'success', 'cell': {'id': 9}}},
      role: 'cell_leader',
    );
    final name = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Nom de la cellule *'));
    expect(name.enabled, isFalse);
    expect(find.text('Responsable'), findsNothing);
    await tester.enterText(await _reveal(tester, find.widgetWithText(TextFormField, 'Lieu de réunion')), 'Chez nous');
    await tester.tap(await _reveal(tester, find.text('Enregistrer')));
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => '${c['path']}'.endsWith('/cell/save'));
    expect(sent['cell_id'], 9);
    expect(sent['meeting_location'], 'Chez nous');
    expect(sent.containsKey('name'), isFalse);
    expect(sent.containsKey('leader_phone'), isFalse);
  });

  testWidgets('un groupe d\'âge exige son type et son sexe avant tout envoi', (tester) async {
    final calls = await _pump(tester, const AgeGroupFormScreen(), {
      '/age_ranges': {'status': 'success', 'age_ranges': []},
    });
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom du groupe *'), 'Jeunes');
    await tester.tap(await _reveal(tester, find.text('Enregistrer')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => '${c['path']}'.endsWith('/age_group/save')), isEmpty);
    expect(await _reveal(tester, find.text('Le type est requis'), step: -150), findsOneWidget);
  });

  testWidgets('une personne peut-être déjà enregistrée : on la voit, ou on confirme une autre', (tester) async {
    final calls = await _pump(tester, const MemberFormScreen(), {
      '/member/create': [
        {
          'status': 'error',
          'code': 'duplicate_person',
          'message': 'Cette personne semble déjà enregistrée (même numéro) : KONAN Aya, Cellule Riviera.',
          'duplicate': {'id': 4, 'name': 'KONAN', 'first_name': 'Aya'},
        },
        {'status': 'success', 'member': {'id': 12}},
      ],
    });
    expect(find.text('Nouvelle personne'), findsOneWidget, reason: 'Le profil se choisit à l\'enregistrement');
    await tester.tap(find.text('Ancien membre'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom *'), 'Konan');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prénom *'), 'Aya');
    await tester.enterText(await _reveal(tester, find.widgetWithText(TextFormField, 'Téléphone *')), '0708091011');
    await tester.tap(await _reveal(tester, find.byType(DropdownButtonFormField<String>).first));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Femme').last);
    await tester.pumpAndSettle();
    await tester.tap(await _reveal(tester, find.text('Créer le membre')));
    await tester.pumpAndSettle();
    expect(find.text('Déjà enregistrée ?'), findsOneWidget);
    expect(find.textContaining('KONAN Aya, Cellule Riviera'), findsOneWidget);
    await tester.tap(find.text('C\'est une autre personne'));
    await tester.pumpAndSettle();
    final creates = calls.where((c) => '${c['path']}'.endsWith('/member/create')).toList();
    expect(creates, hasLength(2));
    expect(creates.first.containsKey('confirm_new'), isFalse);
    expect(creates.last['confirm_new'], isTrue);
    expect(creates.last['person_profile'], 'old_member');
  });

  testWidgets('« À attribuer » distingue nouvelles personnes et anciens membres', (tester) async {
    await _pump(tester, const ToAssignScreen(), {
      '/to_assign': {
        'status': 'success',
        'members': [
          {'id': 1, 'name': 'BAMBA', 'first_name': 'Ali', 'person_profile': 'new'},
          {'id': 2, 'name': 'YAO', 'first_name': 'Marc', 'person_profile': 'old_member'},
        ],
        'interrupted': [],
      },
    });
    expect(find.text('Nouvelle personne'), findsOneWidget);
    expect(find.text('Ancien membre'), findsOneWidget);
  });
}
