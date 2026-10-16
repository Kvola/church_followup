// Hors navigateur : pas de notifications web.
String webPushPermission() => 'unsupported';
Future<String?> webPushToken(String config, {required bool ask}) async => null;
