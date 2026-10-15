import 'dart:convert';

import 'package:church_followup_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Un serveur factice qui répond `result` et retient les paramètres reçus.
ApiService apiReplying(Map<String, dynamic> result, {List<Map<String, dynamic>>? sent}) {
  final client = MockClient((request) async {
    sent?.add(Map<String, dynamic>.from(jsonDecode(request.body)['params']));
    return http.Response(jsonEncode({'jsonrpc': '2.0', 'result': result}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  return ApiService(client: client)..configure(baseUrl: 'https://test', userId: 7, token: 'tok');
}

void main() {
  group('Session expirée', () {
    test('déclenche la déconnexion et lève une erreur au lieu de rendre une liste vide', () async {
      String? expired;
      final api = apiReplying({'status': 'error', 'code': 'auth_required', 'message': 'Session expirée'})
        ..onSessionExpired = (message) => expired = message;
      await expectLater(api.getMembers(), throwsA(isA<ApiException>().having((e) => e.isSessionExpired, 'expirée', true)));
      expect(expired, 'Session expirée');
    });

    test("ne déclenche rien avant la connexion (pas de jeton)", () async {
      var called = false;
      final client = MockClient((_) async => http.Response(
          jsonEncode({'result': {'status': 'error', 'code': 'auth_required', 'message': 'x'}}), 200));
      final api = ApiService(client: client)
        ..configure(baseUrl: 'https://test')
        ..onSessionExpired = (_) => called = true;
      await api.call('/api/church/auth/login', {});
      expect(called, isFalse);
    });
  });

  group('Refus du serveur', () {
    test('une liste refusée devient une erreur lisible', () async {
      final api = apiReplying({'status': 'error', 'code': 'forbidden', 'message': 'Action non autorisée pour votre rôle.'});
      await expectLater(
        api.getFollowups(),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Action non autorisée pour votre rôle.')
            .having((e) => e.code, 'code', 'forbidden')),
      );
    });

    test('une liste acceptée est rendue', () async {
      final api = apiReplying({
        'status': 'success',
        'members': [
          {'id': 1, 'name': 'Kone'}
        ]
      });
      expect((await api.getMembers()).single['name'], 'Kone');
    });
  });

  group('Paramètres envoyés', () {
    test("l'interruption envoie le motif et les précisions", () async {
      final sent = <Map<String, dynamic>>[];
      final api = apiReplying({'status': 'success'}, sent: sent);
      await api.followupAction(3, 'abandon', reason: 'moved', note: 'Parti à Bouaké');
      expect(sent.single, containsPair('reason', 'moved'));
      expect(sent.single, containsPair('note', 'Parti à Bouaké'));
      expect(sent.single, containsPair('token', 'tok'));
    });

    test('la prolongation envoie le nombre de semaines, la justification seulement si fournie', () async {
      final sent = <Map<String, dynamic>>[];
      final api = apiReplying({'status': 'success'}, sent: sent);
      await api.followupAction(3, 'extend', weeks: 6);
      await api.followupAction(3, 'integrate', cellId: 1, groupId: 2, justification: '');
      expect(sent[0], containsPair('weeks', 6));
      expect(sent[1].containsKey('justification'), isFalse);
    });
  });
}
