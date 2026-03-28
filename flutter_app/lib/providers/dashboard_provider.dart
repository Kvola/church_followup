import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import 'auth_provider.dart';

class DashboardProvider extends ChangeNotifier {
  AuthProvider? _auth;
  final CacheService _cache = CacheService();

  Map<String, dynamic>? _dashboard;
  bool _isLoading = false;
  String? _error;

  Map<String, dynamic>? get dashboard => _dashboard;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ApiService get _api => _auth!.api;

  void updateAuth(AuthProvider auth) {
    final wasAuthenticated = _auth?.isAuthenticated ?? false;
    _auth = auth;
    if (wasAuthenticated && !auth.isAuthenticated) {
      clear();
    }
  }

  void clear() {
    _dashboard = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (_auth == null || !_auth!.isAuthenticated) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (!forceRefresh) {
        final cached = await _cache.get('dashboard');
        if (cached != null) {
          _dashboard = Map<String, dynamic>.from(cached);
          _isLoading = false;
          notifyListeners();
          // Still refresh in background
          _refreshInBackground();
          return;
        }
      }

      _dashboard = await _api.getDashboard();
      await _cache.put('dashboard', _dashboard);
    } catch (e) {
      _error = e.toString();
      // Try cache fallback
      final cached = await _cache.get('dashboard', maxAgeMinutes: 1440);
      if (cached != null) {
        _dashboard = Map<String, dynamic>.from(cached);
        _error = null;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final fresh = await _api.getDashboard();
      _dashboard = fresh;
      await _cache.put('dashboard', _dashboard);
      notifyListeners();
    } catch (_) {}
  }

  // Helpers
  int get totalMembers => _dashboard?['total_members'] ?? 0;
  int get totalEvangelists => _dashboard?['total_evangelists'] ?? 0;
  int get totalCells => _dashboard?['total_cells'] ?? 0;
  int get totalGroups => _dashboard?['total_groups'] ?? 0;
  int get activeFollowups => _dashboard?['active_followups'] ?? 0;
  int get integratedCount => _dashboard?['integrated_count'] ?? 0;
  int get abandonedCount => _dashboard?['abandoned_count'] ?? 0;

  double get integrationRate {
    final total = integratedCount + abandonedCount;
    if (total == 0) return 0;
    return (integratedCount / total * 100);
  }
}
