import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'dart:async';

import '../services/api_service.dart';
import '../services/push_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api;
  final PushService push;
  StreamSubscription<String>? _tokenRefreshSub;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool _isAuthenticated = false;
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;
  String _serverUrl = AppConstants.defaultUrl;
  String _database = '';

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  Map<String, dynamic>? get currentUser => _currentUser;
  ApiService get api => _api;
  String get serverUrl => _serverUrl;
  String get database => _database;

  String get userRole => _currentUser?['role'] ?? '';
  int get userId => _currentUser?['id'] ?? 0;
  int get churchId => _currentUser?['church_id'] ?? 0;
  String get churchName => _currentUser?['church_name'] ?? '';
  String get userName => _currentUser?['name'] ?? '';
  bool get isMultiChurch => _currentUser?['is_multi_church'] == true;

  /// Les comptes de la personne, un par église (au moins le sien).
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> get accounts => _accounts;
  bool get hasSeveralAccounts => _accounts.length > 1;

  /// Le numéro ou l'adresse en cours de connexion (entre l'envoi du code et sa saisie).
  String _pendingIdentifier = '';
  String get pendingIdentifier => _pendingIdentifier;

  bool get isManager => userRole == 'manager' || userRole == 'super_admin';
  bool get isSuperAdmin => userRole == 'super_admin';
  bool get isEvangelist => userRole == 'evangelist';
  bool get isCellLeader => userRole == 'cell_leader';
  bool get isGroupLeader => userRole == 'group_leader';

  // Ce que le serveur autorise à chaque rôle : l'app ne propose rien d'autre.
  bool get canSeeFollowups => isManager || isEvangelist;
  bool get canPointSunday => isManager || isEvangelist || isGroupLeader;
  bool get canPointCell => isManager || isCellLeader;
  bool get canDoCheckpoints => isManager || isCellLeader;

  /// Durée de suivi par défaut de l'église (semaines), donnée à la connexion.
  int get defaultFollowupWeeks {
    final value = _currentUser?['default_followup_weeks'];
    return value is int && value > 0 ? value : 4;
  }

  /// Message à montrer sur l'écran de connexion (ex. session expirée).
  String? _sessionMessage;
  String? get sessionMessage => _sessionMessage;

  AuthProvider({ApiService? api, PushService? pushService})
      : _api = api ?? ApiService(),
        push = pushService ?? PushService() {
    _api.onSessionExpired = (message) {
      if (_isAuthenticated) _endSession(message: message);
    };
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString(AppConstants.keyServerUrl) ?? AppConstants.defaultUrl;
      _database = prefs.getString(AppConstants.keyDatabase) ?? '';

      final userData = await _secure.read(key: AppConstants.keyUserData);
      final token = await _secure.read(key: 'auth_token');
      final accounts = await _secure.read(key: _keyAccounts);
      // Sans jeton, pas de session : l'ancienne app (PIN) en gardait un autre.
      if (userData != null && token != null) {
        _currentUser = jsonDecode(userData);
        _accounts = _asList(accounts == null ? null : jsonDecode(accounts));
        _isAuthenticated = true;
        _api.configure(baseUrl: _serverUrl, token: token);
        unawaited(_registerDevice());
      }
    } catch (e) {
      debugPrint('Session load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  static const _keyAccounts = 'accounts';

  static List<Map<String, dynamic>> _asList(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  String get _deviceLabel {
    try {
      return push.deviceLabel;
    } catch (_) {
      return 'Téléphone';
    }
  }

  /// Étape 1 : demande un code pour ce numéro ou cette adresse.
  ///
  /// Rend `{success, message, masked, debugOtp}`. Le serveur répond pareil
  /// qu'un compte existe ou non : l'app ne peut pas dire « inconnu ».
  Future<Map<String, dynamic>> requestOtp({
    required String url,
    required String db,
    required String identifier,
  }) async {
    _serverUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _database = db;
    _api.configure(baseUrl: _serverUrl);
    try {
      final result = await _api.requestOtp(identifier);
      _pendingIdentifier = identifier;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyServerUrl, _serverUrl);
      await prefs.setString(AppConstants.keyDatabase, _database);
      await prefs.setString(AppConstants.keyPhone, identifier);
      return {
        'success': true,
        'message': result['message'] ?? '',
        'masked': result['identifier_masked'] ?? identifier,
        'debugOtp': result['debug_otp'],
      };
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Étape 2 : vérifie le code reçu et ouvre la session.
  Future<Map<String, dynamic>> verifyOtp(String code) async {
    try {
      final result = await _api.verifyOtp(_pendingIdentifier, code, _deviceLabel);
      await _openSession(result);
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Passe sur le compte de la même personne dans une autre église.
  Future<Map<String, dynamic>> switchAccount(int accountId) async {
    try {
      final result = await _api.switchAccount(accountId, _deviceLabel);
      await _openSession(result);
      return {'success': true, 'message': result['message'] ?? ''};
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<void> _openSession(Map<String, dynamic> result) async {
    final token = result['token'] as String?;
    if (token == null || result['user'] is! Map) {
      throw ApiException('Réponse de connexion incomplète');
    }
    _sessionMessage = null;
    _currentUser = Map<String, dynamic>.from(result['user']);
    _accounts = _asList(result['accounts']);
    _isAuthenticated = true;
    _api.configure(baseUrl: _serverUrl, token: token);
    await _secure.write(key: AppConstants.keyUserData, value: jsonEncode(_currentUser));
    await _secure.write(key: _keyAccounts, value: jsonEncode(_accounts));
    await _secure.write(key: 'auth_token', value: token);
    notifyListeners();
    unawaited(_registerDevice());
  }

  /// Ouvre une session sans serveur : réservé aux tests et aux captures de
  /// formation (données de démonstration).
  @visibleForTesting
  void debugSignIn(Map<String, dynamic> user, {List<Map<String, dynamic>> accounts = const []}) {
    _currentUser = Map<String, dynamic>.from(user);
    _accounts = accounts;
    _isAuthenticated = true;
    _isLoading = false;
    notifyListeners();
  }

  /// Déconnexion voulue : le téléphone cesse de recevoir les relances de ce
  /// compte, et la session est fermée côté serveur.
  Future<void> logout() async {
    final token = push.token;
    if (token != null) await _api.unregisterDevice(token);
    await _api.logout();
    await _endSession();
  }

  /// Enregistre ce téléphone pour les notifications push. Ne lève jamais :
  /// sans push, l'application fonctionne, elle ne sonne simplement pas.
  Future<void> _registerDevice() async {
    try {
      await push.initialize();
      final token = push.token;
      if (token == null || !_isAuthenticated) return;
      await _api.registerDevice(token, push.platform, push.deviceLabel);
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = push.tokenRefresh.listen((fresh) {
        if (_isAuthenticated) {
          _api.registerDevice(fresh, push.platform, push.deviceLabel).catchError((_) {});
        }
      });
    } catch (e) {
      debugPrint('[push] enregistrement impossible : $e');
    }
  }

  Future<void> _endSession({String? message}) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _sessionMessage = message;
    _isAuthenticated = false;
    _currentUser = null;
    _accounts = [];
    _api.configure(baseUrl: _serverUrl);
    await _secure.delete(key: AppConstants.keyUserData);
    await _secure.delete(key: _keyAccounts);
    await _secure.delete(key: 'auth_token');
    notifyListeners();
  }

  Future<String> getLastPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyPhone) ?? '';
  }
}
