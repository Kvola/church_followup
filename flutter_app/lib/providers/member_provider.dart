import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class MemberProvider extends ChangeNotifier {
  AuthProvider? _auth;

  List<Map<String, dynamic>> _members = [];
  Map<String, dynamic>? _currentDetail;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  List<Map<String, dynamic>> get members => _searchQuery.isEmpty
      ? _members
      : _members.where((m) {
          final name = '${m['name'] ?? ''} ${m['first_name'] ?? ''}'.toLowerCase();
          final phone = (m['phone'] ?? '').toString().toLowerCase();
          final q = _searchQuery.toLowerCase();
          return name.contains(q) || phone.contains(q);
        }).toList();

  List<Map<String, dynamic>> get allMembers => _members;
  Map<String, dynamic>? get currentDetail => _currentDetail;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  ApiService get _api => _auth!.api;

  void updateAuth(AuthProvider auth) {
    final wasAuthenticated = _auth?.isAuthenticated ?? false;
    _auth = auth;
    if (wasAuthenticated && !auth.isAuthenticated) {
      clear();
    }
  }

  void clear() {
    _members = [];
    _currentDetail = null;
    _isLoading = false;
    _error = null;
    _searchQuery = '';
    notifyListeners();
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadMembers({String? memberType}) async {
    if (_auth == null || !_auth!.isAuthenticated) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _members = await _api.getMembers(memberType: memberType);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDetail(int memberId) async {
    _isLoading = true;
    _error = null;
    _currentDetail = null;
    notifyListeners();

    try {
      _currentDetail = await _api.getMemberDetail(memberId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createMember(Map<String, dynamic> data) async {
    try {
      final result = await _api.createMember(data);
      if (result['status'] == 'success') {
        await loadMembers();
      }
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateMember(int memberId, Map<String, dynamic> data) async {
    try {
      final result = await _api.updateMember(memberId, data);
      if (result['status'] == 'success') {
        await loadMembers();
      }
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }
}
