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
      if (userData != null) {
        _currentUser = jsonDecode(userData);
        _isAuthenticated = true;
        _api.configure(baseUrl: _serverUrl, userId: _currentUser!['id'], token: token);
        unawaited(_registerDevice());
      }
    } catch (e) {
      debugPrint('Session load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> login({
    required String url,
    required String db,
    required String phone,
    required String pin,
  }) async {
    _serverUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _database = db;
    _api.configure(baseUrl: _serverUrl);

    try {
      final result = await _api.login(phone, pin, db);

      if (result['status'] == 'success') {
        _sessionMessage = null;
        _currentUser = Map<String, dynamic>.from(result['user']);
        final token = result['token'] as String?;
        _isAuthenticated = true;
        _api.configure(baseUrl: _serverUrl, userId: _currentUser!['id'], token: token);

        // Persist
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.keyServerUrl, _serverUrl);
        await prefs.setString(AppConstants.keyDatabase, _database);
        await prefs.setString(AppConstants.keyPhone, phone);
        await _secure.write(key: AppConstants.keyUserData, value: jsonEncode(_currentUser));
        if (token != null) {
          await _secure.write(key: 'auth_token', value: token);
        }

        notifyListeners();
        unawaited(_registerDevice());
        return {'success': true};
      }
      return {'success': false, 'message': result['message'] ?? 'Identifiants incorrects'};
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
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
    _api.configure(baseUrl: _serverUrl, userId: null, token: null);
    await _secure.delete(key: AppConstants.keyUserData);
    await _secure.delete(key: 'auth_token');
    notifyListeners();
  }

  Future<String> getLastPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyPhone) ?? '';
  }
}
