import 'package:flutter/foundation.dart';
import 'auth_provider.dart';

/// La liste « À faire » : décisions à prendre, rapports en retard, personnes à
/// attribuer, contrôles à faire… Le serveur la calcule selon le rôle.
class TodoProvider extends ChangeNotifier {
  AuthProvider? _auth;

  List<Map<String, dynamic>> _items = [];
  String _summary = '';
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get items => _items;
  String get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Nombre affiché sur le badge (une ligne « fiches à compléter » en compte plusieurs).
  int get count => _items.fold(0, (sum, item) => sum + (item['count'] is int ? item['count'] as int : 1));

  String? _scope;

  /// Déconnexion ou autre église : ce qui est chargé appartient à l'ancien périmètre.
  void updateAuth(AuthProvider auth) {
    final scope = auth.sessionScope;
    final changed = _scope != null && _scope != scope;
    _scope = scope;
    _auth = auth;
    if (changed) {
      _items = [];
      _summary = '';
      _error = null;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _auth!.api.getTodo();
      final raw = result['items'];
      _items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
      _summary = (result['summary'] ?? '').toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
