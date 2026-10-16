import 'dart:js_interop';

@JS('suiviPushPermission')
external JSString? _permission();

@JS('suiviWebPushToken')
external JSPromise<JSString?>? _token(JSString config, JSBoolean ask);

/// 'default', 'granted', 'denied' ou 'unsupported'.
String webPushPermission() {
  try {
    return _permission()?.toDart ?? 'unsupported';
  } catch (_) {
    return 'unsupported';
  }
}

/// Le jeton FCM de ce navigateur, ou null (refus, navigateur inapte, panne).
Future<String?> webPushToken(String config, {required bool ask}) async {
  try {
    final promise = _token(config.toJS, ask.toJS);
    if (promise == null) return null;
    return (await promise.toDart)?.toDart;
  } catch (_) {
    return null;
  }
}
