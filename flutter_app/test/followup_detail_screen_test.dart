import 'dart:convert';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/providers/followup_provider.dart';
import 'package:church_followup_mobile/providers/organization_provider.dart';
import 'package:church_followup_mobile/screens/followups/followup_detail_screen.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Détail renvoyé par /api/church/followup/detail pour un suivi PROLONGÉ.
Map<String, dynamic> extendedFollowup() => {
      'id': 5,
      'reference': 'SUV/2026/0005',
      'evangelist_name': 'Awa Kone',
      'member_name': 'Yao Konan',
      'state': 'extended',
      'current_week': 2,
      'total_weeks': 8,
      'duration_origin': 'event',
      'average_score': 6.5,
      'elapsed_weeks': 4,
      'attendance_weeks': 2,
      'attendance_rate': 50,
      'attendance_threshold': 75,
      'below_threshold': true,
      'weeks': [
        {'id': 1, 'week_number': 1, 'sunday_attendance': true, 'roll_call_present': true, 'call_made': true,
         'visit_made': false, 'spiritual_state': 'good', 'score': 9, 'notes': ''},
        {'id': 2, 'week_number': 2, 'sunday_attendance': false, 'roll_call_present': false, 'call_made': true,
         'visit_made': false, 'spiritual_state': 'average', 'score': 5, 'notes': 'Malade'},
      ],
    };

void main() {
  late List<Map<String, dynamic>> calls;

  Future<void> pumpDetail(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    final client = MockClient((request) async {
      final params = Map<String, dynamic>.from(jsonDecode(request.body)['params']);
      calls.add({'path': request.url.path, ...params});
      final result = request.url.path.endsWith('/followup/detail')
          ? {'status': 'success', 'followup': extendedFollowup()}
          : {'status': 'success', 'week': {'id': 9, 'score': 3}};
      return http.Response(jsonEncode({'result': result}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final api = ApiService(client: client)..configure(baseUrl: 'https://test', userId: 1, token: 't');
    final auth = AuthProvider(api: api);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => FollowupProvider()..updateAuth(auth)),
        ChangeNotifierProvider(create: (_) => OrganizationProvider()..updateAuth(auth)),
      ],
      child: const MaterialApp(home: FollowupDetailScreen(followupId: 5)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('un suivi prolongé garde ses actions et affiche sa vraie durée', (tester) async {
    await pumpDetail(tester);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget, reason: 'Prolongé = encore actif');
    expect(find.text('8 sem.'), findsOneWidget);
    expect(find.text('2 / 8'), findsOneWidget);
    expect(find.textContaining('Événement d\'origine'), findsOneWidget);
    expect(find.textContaining('2 semaine(s) sur 4 (50 %)'), findsOneWidget);
    expect(find.text('Pointé(e) au culte'), findsOneWidget);
    expect(find.text('Ajouter'), findsOneWidget);
  });

  testWidgets('un nouveau rapport envoie son numéro de semaine et ses notes', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Semaine 3'), findsOneWidget, reason: 'Première semaine sans rapport');
    await tester.enterText(find.widgetWithText(TextFormField, 'Notes (facultatives)'), 'Visite prévue');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final save = calls.firstWhere((c) => c['path'].toString().endsWith('/week/save'));
    expect(save['week_number'], 3);
    expect(save['notes'], 'Visite prévue');
  });

  testWidgets("interrompre exige un motif", (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interrompre').last);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Interrompre');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'Pas de motif, pas de bouton');
    await tester.tap(find.text('A déménagé'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });
}
