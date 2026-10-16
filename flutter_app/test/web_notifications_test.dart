import 'dart:convert';

import 'package:church_followup_mobile/providers/auth_provider.dart';
import 'package:church_followup_mobile/services/api_service.dart';
import 'package:church_followup_mobile/services/push_service.dart';
import 'package:church_followup_mobile/widgets/web_notifications_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un navigateur configuré pour les notifications, permission pas encore demandée.
class _WebPush extends PushService {
  String permission = 'default';
  String? _fake;
  @override
  bool get webPushConfigured => true;
  @override
  String get webPermission => permission;
  @override
  String get platform => 'web';
  @override
  String? get token => _fake;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> enableWebNotifications() async {
    permission = 'granted';
    _fake = 'jeton-web';
    return true;
  }
}

Future<(List<Map<String, dynamic>>, _WebPush)> _pump(WidgetTester t, {String permission = 'default'}) async {
  SharedPreferences.setMockInitialValues({});
  final sent = <Map<String, dynamic>>[];
  final client = MockClient((r) async {
    sent.add({'path': r.url.path, ...Map<String, dynamic>.from(jsonDecode(r.body)['params'])});
    return http.Response(jsonEncode({'result': {'status': 'success'}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final push = _WebPush()..permission = permission;
  final auth = AuthProvider(api: ApiService(client: client)..configure(baseUrl: '', token: 't'), pushService: push)
    ..debugSignIn({'id': 1, 'name': 'Awa', 'role': 'evangelist'});
  await t.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth, child: const MaterialApp(home: Scaffold(body: Column(children: [WebNotificationsBanner()])))));
  await t.pumpAndSettle();
  return (sent, push);
}

void main() {
  testWidgets('« Activer » obtient un jeton et enregistre ce navigateur', (t) async {
    final (sent, push) = await _pump(t);
    expect(find.text('Recevez les relances sur ce navigateur'), findsOneWidget);
    await t.tap(find.text('Activer'));
    await t.pumpAndSettle();
    final register = sent.firstWhere((c) => c['path'] == '/api/church/device/register');
    expect(register['device_token'], 'jeton-web');
    expect(register['platform'], 'web');
    expect(find.text('Recevez les relances sur ce navigateur'), findsNothing);
    expect(push.permission, 'granted');
  });

  testWidgets('déjà décidé (accordé ou refusé) : on ne redemande pas', (t) async {
    for (final p in ['granted', 'denied', 'unsupported']) {
      await _pump(t, permission: p);
      expect(find.text('Recevez les relances sur ce navigateur'), findsNothing, reason: p);
    }
  });
}
