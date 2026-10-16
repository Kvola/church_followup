import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'web_push/web_push.dart' as web_push;

/// Notifications push : personne confiée, décision à prendre, récapitulatif
/// du lundi, contrôle défavorable.
///
/// TOUT ÉCHOUE EN SILENCE, ET C'EST VOULU. Firebase peut manquer
/// (configuration absente, téléphone sans services Google, permission
/// refusée) : l'application fonctionne alors normalement — la liste
/// « À faire » se lit à l'ouverture, elle ne sait simplement pas sonner.
/// Le serveur double d'ailleurs le récapitulatif par WhatsApp ou SMS.
class PushService {
  String? _token;
  bool _ready = false;

  /// Le jeton de l'appareil, ou `null` si le push n'est pas disponible.
  String? get token => _token;

  // `defaultTargetPlatform` plutôt que `dart:io` : il existe aussi sur le web.
  String get platform =>
      kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  String get deviceLabel => kIsWeb ? 'Navigateur' : defaultTargetPlatform.name;

  // ── Notifications web ─────────────────────────────────────────────
  // Identifiants PUBLICS de l'app Web Firebase, compilés par build_pwa.sh.
  // Absents : la PWA fonctionne, sans notifications.
  static const _webAppId = String.fromEnvironment('FCM_WEB_APP_ID');
  static const _webVapidKey = String.fromEnvironment('FCM_VAPID_KEY');
  static const _webApiKey = String.fromEnvironment('FCM_WEB_API_KEY');

  /// La version navigateur sait-elle recevoir des notifications ?
  bool get webPushConfigured =>
      kIsWeb && _webAppId.isNotEmpty && _webVapidKey.isNotEmpty && _webApiKey.isNotEmpty;

  /// 'default' (pas encore demandé), 'granted', 'denied' ou 'unsupported'.
  String get webPermission => webPushConfigured ? web_push.webPushPermission() : 'unsupported';

  String get _webConfig => jsonEncode({'apiKey': _webApiKey, 'appId': _webAppId, 'vapidKey': _webVapidKey});

  /// Active les notifications de ce navigateur : DEMANDE la permission. À
  /// n'appeler que sur un geste de l'utilisateur (Safari l'exige).
  Future<bool> enableWebNotifications() async {
    if (!webPushConfigured) return false;
    _token = await web_push.webPushToken(_webConfig, ask: true);
    return _token != null;
  }

  /// Prépare Firebase et demande la permission. Ne lève jamais.
  ///
  /// Sur le web, rien n'est demandé ici : le jeton n'est repris que si la
  /// permission a déjà été donnée (un navigateur refuse une demande qui ne
  /// suit pas un geste, et ne la repose plus).
  Future<void> initialize() async {
    if (kIsWeb) {
      if (webPushConfigured && web_push.webPushPermission() == 'granted') {
        _token = await web_push.webPushToken(_webConfig, ask: false);
      }
      return;
    }
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      // Android 13+ : sans cette autorisation, le message arrive et rien ne
      // s'affiche. Refusée, on ne la redemande pas : insister agace.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] permission refusée : pas de notification.');
        return;
      }
      _token = await messaging.getToken();
      _ready = true;
    } catch (error) {
      debugPrint('[push] indisponible ($error).');
      _token = null;
      _ready = false;
    }
  }

  /// FCM change le jeton sans prévenir (réinstallation, données effacées) ; un
  /// jeton périmé ne lève aucune erreur, les messages se perdent. Seule parade :
  /// réenregistrer à chaque rotation.
  Stream<String> get tokenRefresh {
    if (!_ready) return const Stream<String>.empty();
    try {
      return FirebaseMessaging.instance.onTokenRefresh;
    } catch (_) {
      return const Stream<String>.empty();
    }
  }

  /// Notification reçue application ouverte.
  Stream<RemoteMessage> get onForegroundMessage =>
      _ready ? FirebaseMessaging.onMessage : const Stream<RemoteMessage>.empty();

  /// Notification touchée alors que l'application était en arrière-plan.
  Stream<RemoteMessage> get onOpenedFromNotification =>
      _ready ? FirebaseMessaging.onMessageOpenedApp : const Stream<RemoteMessage>.empty();

  /// Notification qui a lancé l'application, s'il y en a une.
  Future<RemoteMessage?> initialMessage() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getInitialMessage();
    } catch (_) {
      return null;
    }
  }
}
