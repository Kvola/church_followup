import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class FollowupProvider extends ChangeNotifier {
  AuthProvider? _auth;

  List<Map<String, dynamic>> _followups = [];
  Map<String, dynamic>? _currentDetail;
  List<Map<String, dynamic>> _evangelists = [];
  bool _isLoading = false;
  String? _error;
  String? _stateFilter;

  List<Map<String, dynamic>> get followups => _followups;
  Map<String, dynamic>? get currentDetail => _currentDetail;
  List<Map<String, dynamic>> get evangelists => _evangelists;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get stateFilter => _stateFilter;

  ApiService get _api => _auth!.api;

  void updateAuth(AuthProvider auth) {
    final wasAuthenticated = _auth?.isAuthenticated ?? false;
    _auth = auth;
    if (wasAuthenticated && !auth.isAuthenticated) {
      clear();
    }
  }

  void clear() {
    _followups = [];
    _currentDetail = null;
    _evangelists = [];
    _isLoading = false;
    _error = null;
    _stateFilter = null;
    notifyListeners();
  }

  void setStateFilter(String? state) {
    _stateFilter = state;
    loadFollowups();
  }

  Future<void> loadFollowups() async {
    if (_auth == null || !_auth!.isAuthenticated) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final myOnly = _auth!.isEvangelist;
      _followups = await _api.getFollowups(state: _stateFilter, myOnly: myOnly);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDetail(int followupId) async {
    _isLoading = true;
    _error = null;
    _currentDetail = null;
    notifyListeners();

    try {
      _currentDetail = await _api.getFollowupDetail(followupId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createFollowup(Map<String, dynamic> data) async {
    try {
      final result = await _api.createFollowup(data);
      if (result['status'] == 'success') {
        await loadFollowups();
      }
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> saveWeek(Map<String, dynamic> data) async {
    try {
      final result = await _api.saveFollowupWeek(data);
      if (result['status'] == 'success' && _currentDetail != null) {
        await loadDetail(_currentDetail!['id']);
      }
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> performAction(
    int followupId,
    String action, {
    int? evangelistId,
    int? cellId,
    int? groupId,
  }) async {
    try {
      final result = await _api.followupAction(
        followupId,
        action,
        evangelistId: evangelistId,
        cellId: cellId,
        groupId: groupId,
      );
      if (result['status'] == 'success') {
        await loadFollowups();
      }
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<void> loadEvangelists() async {
    try {
      _evangelists = await _api.getEvangelists();
      notifyListeners();
    } catch (e) {
      debugPrint('loadEvangelists error: $e');
    }
  }

  Future<Map<String, dynamic>> createEvangelist(String name, String phone) async {
    try {
      final result = await _api.createEvangelist(name, phone);
      if (result['status'] == 'success') {
        await loadEvangelists();
      }
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }
}
