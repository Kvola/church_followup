import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class OrganizationProvider extends ChangeNotifier {
  AuthProvider? _auth;

  List<Map<String, dynamic>> _cells = [];
  List<Map<String, dynamic>> _ageGroups = [];
  List<Map<String, dynamic>> _districts = [];
  List<Map<String, dynamic>> _cookingRotation = [];
  List<Map<String, dynamic>> _mobileUsers = [];
  List<Map<String, dynamic>> _churches = [];
  int _loadingCount = 0;
  String? _error;

  List<Map<String, dynamic>> get cells => _cells;
  List<Map<String, dynamic>> get ageGroups => _ageGroups;
  List<Map<String, dynamic>> get districts => _districts;

  // Pour choisir (fiche d'une personne…) : jamais une unité archivée.
  static bool _active(Map<String, dynamic> r) => r['active'] != false;
  List<Map<String, dynamic>> get activeCells => _cells.where(_active).toList();
  List<Map<String, dynamic>> get activeAgeGroups => _ageGroups.where(_active).toList();
  List<Map<String, dynamic>> get activeDistricts => _districts.where(_active).toList();
  List<Map<String, dynamic>> get cookingRotation => _cookingRotation;
  List<Map<String, dynamic>> get mobileUsers => _mobileUsers;
  List<Map<String, dynamic>> get churches => _churches;
  bool get isLoading => _loadingCount > 0;
  String? get error => _error;

  ApiService get _api => _auth!.api;

  String? _scope;

  /// Déconnexion ou autre église : ce qui est chargé appartient à l'ancien périmètre.
  void updateAuth(AuthProvider auth) {
    final scope = auth.sessionScope;
    final changed = _scope != null && _scope != scope;
    _scope = scope;
    _auth = auth;
    if (changed) {
      clear();
    }
  }

  void clear() {
    _cells = [];
    _ageGroups = [];
    _districts = [];
    _cookingRotation = [];
    _mobileUsers = [];
    _churches = [];
    _loadingCount = 0;
    _error = null;
    notifyListeners();
  }

  void _startLoading() {
    _loadingCount++;
    _error = null;
    notifyListeners();
  }

  void _stopLoading() {
    _loadingCount = (_loadingCount - 1).clamp(0, 999);
    notifyListeners();
  }

  /// Les responsables peuvent voir les cellules, groupes et quartiers archivés.
  bool _showArchived = false;
  bool get showArchived => _showArchived;
  set showArchived(bool value) {
    _showArchived = value;
    notifyListeners();
    loadCells();
    loadAgeGroups();
    loadDistricts();
  }

  List<Map<String, dynamic>> _ageRanges = [];
  List<Map<String, dynamic>> get ageRanges => _ageRanges;

  Future<void> loadAgeRanges() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    try {
      _ageRanges = await _api.getAgeRanges();
      notifyListeners();
    } catch (_) {}
  }

  /// Enregistre puis recharge la liste. Rend `{success, message, record}`.
  Future<Map<String, dynamic>> _save(
      Future<Map<String, dynamic>> Function() send, Future<void> Function() reload, String done) async {
    try {
      final record = await send();
      await reload();
      return {'success': true, 'message': done, 'record': record};
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> saveCell(Map<String, dynamic> data) =>
      _save(() => _api.saveCell(data), loadCells, 'Cellule enregistrée');

  Future<Map<String, dynamic>> saveAgeGroup(Map<String, dynamic> data) =>
      _save(() => _api.saveAgeGroup(data), loadAgeGroups, 'Groupe enregistré');

  Future<Map<String, dynamic>> saveDistrict(Map<String, dynamic> data) =>
      _save(() => _api.saveDistrict(data), loadDistricts, 'Quartier enregistré');

  Future<void> loadCells() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _startLoading();
    try {
      _cells = await _api.getPrayerCells(includeArchived: _showArchived);
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopLoading();
    }
  }

  Future<void> loadAgeGroups() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _startLoading();
    try {
      _ageGroups = await _api.getAgeGroups(includeArchived: _showArchived);
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopLoading();
    }
  }

  Future<void> loadDistricts() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _startLoading();
    try {
      _districts = await _api.getDistricts(includeArchived: _showArchived);
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopLoading();
    }
  }

  Future<void> loadCookingRotation() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _startLoading();
    try {
      _cookingRotation = await _api.getCookingRotation();
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopLoading();
    }
  }

  Future<void> loadMobileUsers() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _startLoading();
    try {
      _mobileUsers = await _api.getMobileUsers();
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopLoading();
    }
  }

  // Attendance
  Future<Map<String, dynamic>> saveSundayAttendance(String date, List<int> memberIds) async {
    try {
      return await _api.saveSundayAttendance(date, memberIds);
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> saveCellAttendance(int cellId, String date, List<int> memberIds) async {
    try {
      return await _api.saveCellAttendance(cellId, date, memberIds);
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  // Admin actions
  Future<Map<String, dynamic>> shareInvitation(int targetUserId) async {
    try {
      return await _api.shareInvitation(targetUserId);
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> createCellLeader(String name, String phone, int cellId) async {
    try {
      final result = await _api.createCellLeader(name, phone, cellId);
      if (result['status'] == 'success') await loadMobileUsers();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> createGroupLeader(String name, String phone, int groupId) async {
    try {
      final result = await _api.createGroupLeader(name, phone, groupId);
      if (result['status'] == 'success') await loadMobileUsers();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  // ─── Super Admin ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> adminCreateUser(Map<String, dynamic> data) async {
    try {
      final result = await _api.adminCreateUser(data);
      if (result['status'] == 'success') await loadMobileUsers();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> adminUpdateUser(int targetUserId, Map<String, dynamic> data) async {
    try {
      final result = await _api.adminUpdateUser(targetUserId, data);
      if (result['status'] == 'success') await loadMobileUsers();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  // Reports
  Future<Map<String, dynamic>> getFollowupReport(int evangelistId) async {
    return await _api.getFollowupReport(evangelistId);
  }

  // ─── Church Management (Super Admin) ──────────────────────────────

  Future<void> loadChurches() async {
    if (_auth == null || !_auth!.isAuthenticated) return;
    _startLoading();
    try {
      _churches = await _api.getChurches();
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopLoading();
    }
  }

  /// Les églises de l'annuaire du réseau qui ne sont pas encore dans le suivi.
  Future<List<Map<String, dynamic>>> searchDirectory(String query) async {
    try {
      return await _api.searchDirectory(query);
    } catch (e) {
      _error = e.toString();
      return [];
    }
  }

  Future<Map<String, dynamic>> createChurch(Map<String, dynamic> data) async {
    try {
      final result = await _api.createChurch(data);
      if (result['status'] == 'success') await loadChurches();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateChurch(int churchId, Map<String, dynamic> data) async {
    try {
      final result = await _api.updateChurch(churchId, data);
      if (result['status'] == 'success') await loadChurches();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>?> getChurchDetail(int churchId) async {
    try {
      return await _api.getChurchDetail(churchId);
    } catch (e) {
      _error = e.toString();
      return null;
    }
  }

  Future<Map<String, dynamic>> createManager(String name, String phone, int churchId, {String email = ''}) async {
    try {
      final result = await _api.createManager(name, phone, churchId, email: email);
      if (result['status'] == 'success') await loadChurches();
      return result;
    } catch (e) {
      return {'status': 'error', 'message': '$e'};
    }
  }

  // ─── Pasteurs : ceux de l'annuaire du réseau, en lecture ─────────

  Future<List<Map<String, dynamic>>> getPastors({int? churchId}) async {
    try {
      return await _api.getPastors(churchId: churchId);
    } catch (e) {
      _error = e.toString();
      return [];
    }
  }
}
