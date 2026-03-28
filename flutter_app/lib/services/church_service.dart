import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ChurchService extends ChangeNotifier {
  String _baseUrl = '';
  String _database = '';
  bool _isAuthenticated = false;
  Map<String, dynamic>? _currentUser;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get currentUser => _currentUser;
  String get baseUrl => _baseUrl;
  String get userRole => _currentUser?['role'] ?? '';
  int get userId => _currentUser?['id'] ?? 0;
  int get churchId => _currentUser?['church_id'] ?? 0;
  String get churchName => _currentUser?['church_name'] ?? '';
  String get userName => _currentUser?['name'] ?? '';

  ChurchService() {
    _loadSession();
  }

  // ─── Session Management ────────────────────────────────────────────

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('church_url') ?? '';
    _database = prefs.getString('church_db') ?? '';
    final userData = prefs.getString('church_user');
    if (userData != null) {
      _currentUser = jsonDecode(userData);
      _isAuthenticated = true;
    }
    notifyListeners();
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('church_url', _baseUrl);
    await prefs.setString('church_db', _database);
    if (_currentUser != null) {
      await prefs.setString('church_user', jsonEncode(_currentUser));
    }
  }

  Future<Map<String, String>> getLastConnectionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': prefs.getString('church_url') ?? '',
      'db': prefs.getString('church_db') ?? '',
    };
  }

  // ─── Cache ─────────────────────────────────────────────────────────

  Future<void> _cacheData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_$key', jsonEncode(data));
    await prefs.setInt('cache_${key}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  Future<dynamic> _getCachedData(String key, {int maxAgeMinutes = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('cache_${key}_ts') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > maxAgeMinutes * 60 * 1000) return null;
    final raw = prefs.getString('cache_$key');
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  // ─── JSON-RPC ──────────────────────────────────────────────────────

  static const _timeout = Duration(seconds: 30);
  static const _maxRetries = 2;

  Future<dynamic> _jsonRpc(String endpoint, Map<String, dynamic> params, {int retries = 0}) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    // Always add user_id for authentication
    if (_currentUser != null) {
      params['user_id'] = _currentUser!['id'];
    }

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'id': DateTime.now().millisecondsSinceEpoch,
      'params': params,
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }

      final result = jsonDecode(response.body);
      if (result['error'] != null) {
        final error = result['error'];
        throw Exception(error['data']?['message'] ?? error['message'] ?? 'Erreur inconnue');
      }

      return result['result'];
    } on Exception catch (e) {
      // Retry on timeout or network errors (not on server-side errors)
      final isRetryable = e.toString().contains('TimeoutException') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection');
      if (isRetryable && retries < _maxRetries) {
        await Future.delayed(Duration(seconds: retries + 1));
        return _jsonRpc(endpoint, params, retries: retries + 1);
      }
      if (e.toString().contains('TimeoutException')) {
        throw Exception('Le serveur ne répond pas. Vérifiez votre connexion.');
      }
      rethrow;
    }
  }

  // ─── Authentication ────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String url, String db, String phone, String pin) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _database = db;

    try {
      final result = await _jsonRpc('/api/church/auth/login', {
        'phone': phone,
        'pin': pin,
        'db': db,
      });

      if (result['status'] == 'success') {
        _currentUser = result['user'];
        _isAuthenticated = true;
        await _saveSession();
        notifyListeners();
        return {'success': true};
      }
      return {'success': false, 'message': result['message'] ?? 'Erreur de connexion'};
    } catch (e) {
      debugPrint('Login error: $e');
      return {'success': false, 'message': 'Erreur de connexion: $e'};
    }
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('church_user');
    notifyListeners();
  }

  // ─── Dashboard ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboard() async {
    try {
      final result = await _jsonRpc('/api/church/dashboard', {});
      if (result['status'] == 'success') {
        await _cacheData('dashboard', result['dashboard']);
        return result['dashboard'];
      }
    } catch (e) {
      debugPrint('getDashboard error: $e');
      final cached = await _getCachedData('dashboard');
      if (cached != null) return Map<String, dynamic>.from(cached);
    }
    return {};
  }

  // ─── Evangelists ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEvangelists() async {
    try {
      final result = await _jsonRpc('/api/church/evangelists', {});
      if (result['status'] == 'success') {
        final list = (result['evangelists'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
        await _cacheData('evangelists', list);
        return list;
      }
    } catch (e) {
      debugPrint('getEvangelists error: $e');
      final cached = await _getCachedData('evangelists');
      if (cached is List) {
        return cached.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return [];
  }

  Future<Map<String, dynamic>> createEvangelist(String name, String phone) async {
    final result = await _jsonRpc('/api/church/evangelist/create', {
      'name': name,
      'phone': phone,
    });
    return Map<String, dynamic>.from(result);
  }

  // ─── Members ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMembers({String? memberType}) async {
    try {
      final params = <String, dynamic>{};
      if (memberType != null) params['member_type'] = memberType;
      final result = await _jsonRpc('/api/church/members', params);
      if (result['status'] == 'success') {
        return (result['members'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getMembers error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> createMember(Map<String, dynamic> data) async {
    try {
      final result = await _jsonRpc('/api/church/member/create', data);
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>?> getMemberDetail(int memberId) async {
    try {
      final result = await _jsonRpc('/api/church/member/detail', {
        'member_id': memberId,
      });
      if (result['status'] == 'success') {
        return Map<String, dynamic>.from(result['member']);
      }
    } catch (e) {
      debugPrint('getMemberDetail error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> updateMember(int memberId, Map<String, dynamic> data) async {
    try {
      data['member_id'] = memberId;
      final result = await _jsonRpc('/api/church/member/update', data);
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  // ─── Followups ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFollowups({String? state, bool myOnly = false}) async {
    try {
      final params = <String, dynamic>{};
      if (state != null) params['state'] = state;
      if (myOnly) params['my_only'] = true;
      final result = await _jsonRpc('/api/church/followups', params);
      if (result['status'] == 'success') {
        return (result['followups'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getFollowups error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> getFollowupDetail(int followupId) async {
    try {
      final result = await _jsonRpc('/api/church/followup/detail', {
        'followup_id': followupId,
      });
      if (result['status'] == 'success') {
        return Map<String, dynamic>.from(result['followup']);
      }
    } catch (e) {
      debugPrint('getFollowupDetail error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> createFollowup(Map<String, dynamic> data) async {
    try {
      final result = await _jsonRpc('/api/church/followup/create', data);
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> createFollowupWeek(int followupId, Map<String, dynamic> data) async {
    try {
      data['followup_id'] = followupId;
      final result = await _jsonRpc('/api/church/followup/week/save', data);
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateFollowupWeek(int weekId, Map<String, dynamic> data) async {
    try {
      data['week_id'] = weekId;
      final result = await _jsonRpc('/api/church/followup/week/save', data);
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> followupAction(int followupId, String action, {int? evangelistId, int? cellId, int? groupId}) async {
    final params = <String, dynamic>{
      'followup_id': followupId,
      'action': action,
    };
    if (evangelistId != null) params['transferred_to_id'] = evangelistId;
    if (cellId != null) params['target_cell_id'] = cellId;
    if (groupId != null) params['target_age_group_id'] = groupId;
    try {
      final result = await _jsonRpc('/api/church/followup/action', params);
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  // ─── Prayer Cells ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPrayerCells() async {
    try {
      final result = await _jsonRpc('/api/church/cells', {});
      if (result['status'] == 'success') {
        return (result['cells'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getPrayerCells error: $e');
    }
    return [];
  }

  // ─── Age Groups ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAgeGroups() async {
    try {
      final result = await _jsonRpc('/api/church/age_groups', {});
      if (result['status'] == 'success') {
        return (result['age_groups'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getAgeGroups error: $e');
    }
    return [];
  }

  // ─── Districts ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDistricts() async {
    try {
      final result = await _jsonRpc('/api/church/districts', {});
      if (result['status'] == 'success') {
        return (result['districts'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getDistricts error: $e');
    }
    return [];
  }

  // ─── Attendance ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> saveSundayAttendance(String date, List<int> memberIds) async {
    try {
      final result = await _jsonRpc('/api/church/attendance/sunday/save', {
        'date': date,
        'member_ids': memberIds,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> saveCellAttendance(int cellId, String date, List<int> memberIds) async {
    try {
      final result = await _jsonRpc('/api/church/attendance/cell/save', {
        'prayer_cell_id': cellId,
        'date': date,
        'member_ids': memberIds,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  // ─── Cooking Rotation ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCookingRotation() async {
    try {
      final result = await _jsonRpc('/api/church/cooking_rotation', {});
      if (result['status'] == 'success') {
        return (result['rotations'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getCookingRotation error: $e');
    }
    return [];
  }

  // ─── Credentials Sharing ──────────────────────────────────────────

  Future<Map<String, dynamic>> shareCredentials(int targetUserId) async {
    try {
      final result = await _jsonRpc('/api/church/user/share_message', {
        'target_user_id': targetUserId,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  // ─── Reports ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFollowupReport(int evangelistId) async {
    try {
      final result = await _jsonRpc('/api/church/report/followup', {
        'evangelist_id': evangelistId,
      });
      if (result['status'] == 'success') {
        return Map<String, dynamic>.from(result['report']);
      }
    } catch (e) {
      debugPrint('getFollowupReport error: $e');
    }
    return {};
  }

  // ─── Mobile Users ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMobileUsers() async {
    try {
      final result = await _jsonRpc('/api/church/mobile_users', {});
      if (result['status'] == 'success') {
        return (result['users'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getMobileUsers error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> createCellLeader(String name, String phone, int cellId) async {
    final result = await _jsonRpc('/api/church/cell_leader/create', {
      'name': name,
      'phone': phone,
      'prayer_cell_id': cellId,
    });
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> createGroupLeader(String name, String phone, int groupId) async {
    final result = await _jsonRpc('/api/church/group_leader/create', {
      'name': name,
      'phone': phone,
      'age_group_id': groupId,
    });
    return Map<String, dynamic>.from(result);
  }
}
