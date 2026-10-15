import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetwork;

  /// Code d'erreur renvoyé par le serveur : `auth_required`, `forbidden`,
  /// `invalid`, `refused`, `duplicate`, `server`…
  final String? code;

  ApiException(this.message, {this.statusCode, this.isNetwork = false, this.code});

  bool get isSessionExpired => code == 'auth_required';

  @override
  String toString() => message;
}

class ApiService {
  /// Client HTTP injectable (les tests passent un `MockClient`).
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String _baseUrl = '';
  int? _userId;
  String? _token;

  String get baseUrl => _baseUrl;

  /// Appelé quand le serveur répond que la session a expiré : l'app se
  /// déconnecte au lieu d'afficher des listes vides.
  void Function(String message)? onSessionExpired;

  /// Safely convert a dynamic list from the API to List<Map<String, dynamic>>.
  List<Map<String, dynamic>> _safeList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Un refus du serveur est une erreur à montrer, jamais une liste vide.
  void _ensureSuccess(dynamic result) {
    if (result is! Map || result['status'] != 'success') {
      final message = result is Map ? result['message'] : null;
      throw ApiException((message ?? 'Erreur serveur').toString(),
          code: result is Map ? result['code']?.toString() : null);
    }
  }

  List<Map<String, dynamic>> _successList(dynamic result, String key) {
    _ensureSuccess(result);
    return _safeList(result[key]);
  }

  Map<String, dynamic> _successMap(dynamic result, String key) {
    _ensureSuccess(result);
    final value = result[key];
    return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  }

  void configure({required String baseUrl, int? userId, String? token}) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    _userId = userId;
    _token = token;
  }

  Future<dynamic> call(String endpoint, Map<String, dynamic> params, {int retries = 0}) async {
    final url = Uri.parse('$_baseUrl$endpoint');

    if (_userId != null) {
      params['user_id'] = _userId;
    }
    if (_token != null) {
      params['token'] = _token;
    }

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'id': DateTime.now().millisecondsSinceEpoch,
      'params': params,
    });

    try {
      final response = await _client
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode != 200) {
        throw ApiException('Erreur serveur (${response.statusCode})', statusCode: response.statusCode);
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw ApiException('Réponse invalide du serveur', statusCode: response.statusCode);
      }

      if (decoded['error'] != null) {
        final error = decoded['error'];
        final msg = error['data']?['message'] ?? error['message'] ?? 'Erreur inconnue';
        throw ApiException(msg);
      }

      final result = decoded['result'];
      if (result == null) throw ApiException('Réponse vide du serveur');
      if (result is Map && result['code'] == 'auth_required' && _token != null) {
        final message = (result['message'] ?? 'Session expirée : veuillez vous reconnecter.').toString();
        onSessionExpired?.call(message);
        throw ApiException(message, code: 'auth_required');
      }
      return result;
    } on TimeoutException {
      if (retries < AppConstants.maxRetries) {
        await Future.delayed(Duration(seconds: retries + 1));
        return call(endpoint, params, retries: retries + 1);
      }
      throw ApiException('Le serveur ne répond pas. Vérifiez votre connexion.', isNetwork: true);
    } on http.ClientException catch (e) {
      if (retries < AppConstants.maxRetries) {
        await Future.delayed(Duration(seconds: retries + 1));
        return call(endpoint, params, retries: retries + 1);
      }
      throw ApiException('Erreur réseau: ${e.message}', isNetwork: true);
    } on ApiException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      final isRetryable = msg.contains('SocketException') || msg.contains('Connection');
      if (isRetryable && retries < AppConstants.maxRetries) {
        await Future.delayed(Duration(seconds: retries + 1));
        return call(endpoint, params, retries: retries + 1);
      }
      if (isRetryable) {
        throw ApiException('Connexion impossible. Vérifiez votre réseau.', isNetwork: true);
      }
      debugPrint('API error on $endpoint: $e');
      throw ApiException('Erreur inattendue');
    }
  }

  // ─── Auth ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String phone, String pin, String db) async {
    final result = await call('/api/church/auth/login', {
      'phone': phone,
      'pin': pin,
      'db': db,
    });
    return Map<String, dynamic>.from(result);
  }

  /// Ferme la session côté serveur (sans échouer si le réseau manque).
  Future<void> logout() async {
    if (_token == null) return;
    try {
      await call('/api/church/auth/logout', {});
    } catch (_) {}
  }

  // ─── Dashboard ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboard() async {
    final result = await call('/api/church/dashboard', {});
    return _successMap(result, 'dashboard');
  }

  // ─── Evangelists ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEvangelists() async {
    final result = await call('/api/church/evangelists', {});
    return _successList(result, 'evangelists');
  }

  Future<Map<String, dynamic>> createEvangelist(String name, String phone) async {
    return Map<String, dynamic>.from(
      await call('/api/church/evangelist/create', {'name': name, 'phone': phone}),
    );
  }

  // ─── Members ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMembers({String? memberType}) async {
    final params = <String, dynamic>{};
    if (memberType != null) params['member_type'] = memberType;
    final result = await call('/api/church/members', params);
    return _successList(result, 'members');
  }

  Future<Map<String, dynamic>> createMember(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(await call('/api/church/member/create', data));
  }

  Future<Map<String, dynamic>?> getMemberDetail(int memberId) async {
    final result = await call('/api/church/member/detail', {'member_id': memberId});
    return _successMap(result, 'member');
  }

  Future<Map<String, dynamic>> updateMember(int memberId, Map<String, dynamic> data) async {
    data['member_id'] = memberId;
    return Map<String, dynamic>.from(await call('/api/church/member/update', data));
  }

  // ─── Followups ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFollowups({String? state, bool myOnly = false}) async {
    final params = <String, dynamic>{};
    if (state != null) params['state'] = state;
    if (myOnly) params['my_only'] = true;
    final result = await call('/api/church/followups', params);
    return _successList(result, 'followups');
  }

  Future<Map<String, dynamic>?> getFollowupDetail(int followupId) async {
    final result = await call('/api/church/followup/detail', {'followup_id': followupId});
    return _successMap(result, 'followup');
  }

  Future<Map<String, dynamic>> createFollowup(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(await call('/api/church/followup/create', data));
  }

  Future<Map<String, dynamic>> saveFollowupWeek(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(await call('/api/church/followup/week/save', data));
  }

  Future<Map<String, dynamic>> followupAction(
    int followupId,
    String action, {
    int? evangelistId,
    int? cellId,
    int? groupId,
    int? weeks,
    String? reason,
    String? note,
    String? justification,
  }) async {
    final params = <String, dynamic>{
      'followup_id': followupId,
      'action': action,
    };
    if (evangelistId != null) params['transferred_to_id'] = evangelistId;
    if (cellId != null) params['target_cell_id'] = cellId;
    if (groupId != null) params['target_age_group_id'] = groupId;
    if (weeks != null) params['weeks'] = weeks;
    if (reason != null) params['reason'] = reason;
    if (note != null && note.isNotEmpty) params['note'] = note;
    if (justification != null && justification.isNotEmpty) params['justification'] = justification;
    return Map<String, dynamic>.from(await call('/api/church/followup/action', params));
  }

  // ─── Organization ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPrayerCells() async {
    final result = await call('/api/church/cells', {});
    return _successList(result, 'cells');
  }

  Future<List<Map<String, dynamic>>> getAgeGroups() async {
    final result = await call('/api/church/age_groups', {});
    return _successList(result, 'age_groups');
  }

  Future<List<Map<String, dynamic>>> getDistricts() async {
    final result = await call('/api/church/districts', {});
    return _successList(result, 'districts');
  }

  // ─── Attendance ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> saveSundayAttendance(String date, List<int> memberIds) async {
    return Map<String, dynamic>.from(
      await call('/api/church/attendance/sunday/save', {'date': date, 'member_ids': memberIds}),
    );
  }

  Future<Map<String, dynamic>> saveCellAttendance(int cellId, String date, List<int> memberIds) async {
    return Map<String, dynamic>.from(
      await call('/api/church/attendance/cell/save', {
        'prayer_cell_id': cellId,
        'date': date,
        'member_ids': memberIds,
      }),
    );
  }

  // ─── Cooking Rotation ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCookingRotation() async {
    final result = await call('/api/church/cooking_rotation', {});
    return _successList(result, 'rotations');
  }

  // ─── Users / Admin ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMobileUsers() async {
    final result = await call('/api/church/mobile_users', {});
    return _successList(result, 'users');
  }

  Future<Map<String, dynamic>> shareCredentials(int targetUserId) async {
    return Map<String, dynamic>.from(
      await call('/api/church/user/share_message', {'target_user_id': targetUserId}),
    );
  }

  Future<Map<String, dynamic>> createCellLeader(String name, String phone, int cellId) async {
    return Map<String, dynamic>.from(
      await call('/api/church/cell_leader/create', {
        'name': name,
        'phone': phone,
        'prayer_cell_id': cellId,
      }),
    );
  }

  Future<Map<String, dynamic>> createGroupLeader(String name, String phone, int groupId) async {
    return Map<String, dynamic>.from(
      await call('/api/church/group_leader/create', {
        'name': name,
        'phone': phone,
        'age_group_id': groupId,
      }),
    );
  }

  // ─── Super Admin ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> adminCreateUser(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(
      await call('/api/church/admin/create_user', data),
    );
  }

  Future<Map<String, dynamic>> adminUpdateUser(int targetUserId, Map<String, dynamic> data) async {
    data['target_user_id'] = targetUserId;
    return Map<String, dynamic>.from(
      await call('/api/church/admin/update_user', data),
    );
  }

  Future<Map<String, dynamic>> adminResetPin(int targetUserId) async {
    return Map<String, dynamic>.from(
      await call('/api/church/admin/reset_pin', {'target_user_id': targetUserId}),
    );
  }

  // ─── Churches (Super Admin) ───────────────────────────────────────

  Future<List<Map<String, dynamic>>> getChurches() async {
    final result = await call('/api/church/churches', {});
    return _successList(result, 'churches');
  }

  Future<Map<String, dynamic>> createChurch(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(
      await call('/api/church/churches/create', data),
    );
  }

  Future<Map<String, dynamic>> updateChurch(int churchId, Map<String, dynamic> data) async {
    data['church_id'] = churchId;
    return Map<String, dynamic>.from(
      await call('/api/church/churches/update', data),
    );
  }

  Future<Map<String, dynamic>?> getChurchDetail(int churchId) async {
    final result = await call('/api/church/churches/detail', {'church_id': churchId});
    return _successMap(result, 'church');
  }

  Future<Map<String, dynamic>> createManager(String name, String phone, int churchId) async {
    return Map<String, dynamic>.from(
      await call('/api/church/manager/create', {
        'name': name,
        'phone': phone,
        'church_id': churchId,
      }),
    );
  }

  // ─── Pastors ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPastors({int? churchId}) async {
    final result = await call('/api/church/pastors', {
      if (churchId != null) 'church_id': churchId,
    });
    return _successList(result, 'pastors');
  }

  Future<Map<String, dynamic>> createPastor(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(
      await call('/api/church/pastors/create', data),
    );
  }

  Future<Map<String, dynamic>> updatePastor(int pastorId, Map<String, dynamic> data) async {
    data['pastor_id'] = pastorId;
    return Map<String, dynamic>.from(
      await call('/api/church/pastors/update', data),
    );
  }

  Future<Map<String, dynamic>> deletePastor(int pastorId) async {
    return Map<String, dynamic>.from(
      await call('/api/church/pastors/delete', {'pastor_id': pastorId}),
    );
  }

  // ─── Reports ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFollowupReport(int evangelistId) async {
    final result = await call('/api/church/report/followup', {'evangelist_id': evangelistId});
    return _successMap(result, 'report');
  }
}
