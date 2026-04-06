import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetwork;

  ApiException(this.message, {this.statusCode, this.isNetwork = false});

  @override
  String toString() => message;
}

class ApiService {
  String _baseUrl = '';
  int? _userId;
  String? _token;

  String get baseUrl => _baseUrl;

  /// Safely convert a dynamic list from the API to List<Map<String, dynamic>>.
  List<Map<String, dynamic>> _safeList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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
      final response = await http
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

  // ─── Dashboard ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboard() async {
    final result = await call('/api/church/dashboard', {});
    if (result['status'] == 'success') {
      return Map<String, dynamic>.from(result['dashboard']);
    }
    throw ApiException(result['message'] ?? 'Erreur serveur');
  }

  // ─── Evangelists ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEvangelists() async {
    final result = await call('/api/church/evangelists', {});
    if (result['status'] == 'success') {
      return _safeList(result['evangelists']);
    }
    return [];
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
    if (result['status'] == 'success') {
      return _safeList(result['members']);
    }
    return [];
  }

  Future<Map<String, dynamic>> createMember(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(await call('/api/church/member/create', data));
  }

  Future<Map<String, dynamic>?> getMemberDetail(int memberId) async {
    final result = await call('/api/church/member/detail', {'member_id': memberId});
    if (result['status'] == 'success') {
      return Map<String, dynamic>.from(result['member']);
    }
    return null;
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
    if (result['status'] == 'success') {
      return _safeList(result['followups']);
    }
    return [];
  }

  Future<Map<String, dynamic>?> getFollowupDetail(int followupId) async {
    final result = await call('/api/church/followup/detail', {'followup_id': followupId});
    if (result['status'] == 'success') {
      return Map<String, dynamic>.from(result['followup']);
    }
    return null;
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
  }) async {
    final params = <String, dynamic>{
      'followup_id': followupId,
      'action': action,
    };
    if (evangelistId != null) params['transferred_to_id'] = evangelistId;
    if (cellId != null) params['target_cell_id'] = cellId;
    if (groupId != null) params['target_age_group_id'] = groupId;
    return Map<String, dynamic>.from(await call('/api/church/followup/action', params));
  }

  // ─── Organization ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPrayerCells() async {
    final result = await call('/api/church/cells', {});
    if (result['status'] == 'success') {
      return _safeList(result['cells']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAgeGroups() async {
    final result = await call('/api/church/age_groups', {});
    if (result['status'] == 'success') {
      return _safeList(result['age_groups']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getDistricts() async {
    final result = await call('/api/church/districts', {});
    if (result['status'] == 'success') {
      return _safeList(result['districts']);
    }
    return [];
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
    if (result['status'] == 'success') {
      return _safeList(result['rotations']);
    }
    return [];
  }

  // ─── Users / Admin ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMobileUsers() async {
    final result = await call('/api/church/mobile_users', {});
    if (result['status'] == 'success') {
      return _safeList(result['users']);
    }
    return [];
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

  // ─── Reports ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFollowupReport(int evangelistId) async {
    final result = await call('/api/church/report/followup', {'evangelist_id': evangelistId});
    if (result['status'] == 'success') {
      return Map<String, dynamic>.from(result['report']);
    }
    return {};
  }
}
