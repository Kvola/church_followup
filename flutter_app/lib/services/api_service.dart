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

  void configure({required String baseUrl, String? token}) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    _token = token;
  }

  bool get hasSession => _token != null;

  Future<dynamic> call(String endpoint, Map<String, dynamic> params,
      {int retries = 0, Duration? timeout}) async {
    final url = Uri.parse('$_baseUrl$endpoint');

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'id': DateTime.now().millisecondsSinceEpoch,
      'params': params,
    });

    try {
      final response = await _client
          .post(url, headers: {
            'Content-Type': 'application/json',
            // La session voyage dans l'en-tête, jamais dans le corps : un
            // journal de requêtes ne la recopie pas.
            if (_token != null) 'Authorization': 'Bearer $_token',
          }, body: body)
          .timeout(timeout ?? AppConstants.requestTimeout);

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

  /// Demande un code de connexion pour ce numéro ou cette adresse. La réponse
  /// est la même qu'un compte existe ou non.
  Future<Map<String, dynamic>> requestOtp(String identifier) async {
    final result = await call('/api/church/auth/request_otp', {'identifier': identifier});
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
  }

  /// Vérifie le code ; rend le jeton, le compte ouvert et tous les comptes de
  /// la personne (un par église).
  Future<Map<String, dynamic>> verifyOtp(String identifier, String code, String deviceLabel) async {
    final result = await call('/api/church/auth/verify_otp',
        {'identifier': identifier, 'code': code, 'device_label': deviceLabel});
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
  }

  /// Passe au compte de la même personne dans une autre église.
  Future<Map<String, dynamic>> switchAccount(int accountId, String deviceLabel) async {
    final result = await call('/api/church/auth/switch',
        {'account_id': accountId, 'device_label': deviceLabel});
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
  }

  /// L'administrateur choisit l'église qu'il gère (0 : toutes les églises).
  Future<Map<String, dynamic>> setChurch(int churchId) async {
    final result = await call('/api/church/auth/set_church', {'church_id': churchId});
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
  }

  /// Ferme la session côté serveur : désenregistre le téléphone puis révoque
  /// le jeton. Un seul essai, borné : la déconnexion n'attend pas le réseau.
  Future<void> closeSession({String? deviceToken}) async {
    if (_token == null) return;
    Future<void> once(String endpoint, Map<String, dynamic> params) async {
      try {
        await call(endpoint, params, retries: AppConstants.maxRetries)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    if (deviceToken != null) {
      await once('/api/church/device/unregister', {'device_token': deviceToken});
    }
    await once('/api/church/auth/logout', {});
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

  Future<List<Map<String, dynamic>>> getPrayerCells({bool includeArchived = false}) async {
    final result = await call('/api/church/cells', {if (includeArchived) 'include_archived': true});
    return _successList(result, 'cells');
  }

  Future<List<Map<String, dynamic>>> getAgeGroups({bool includeArchived = false}) async {
    final result = await call('/api/church/age_groups', {if (includeArchived) 'include_archived': true});
    return _successList(result, 'age_groups');
  }

  Future<List<Map<String, dynamic>>> getDistricts({bool includeArchived = false}) async {
    final result = await call('/api/church/districts', {if (includeArchived) 'include_archived': true});
    return _successList(result, 'districts');
  }

  Future<List<Map<String, dynamic>>> getAgeRanges() async {
    final result = await call('/api/church/age_ranges', {});
    return _successList(result, 'age_ranges');
  }

  /// Crée (sans `cell_id`) ou modifie une cellule ; rend la cellule enregistrée.
  Future<Map<String, dynamic>> saveCell(Map<String, dynamic> data) async =>
      _successMap(await call('/api/church/cell/save', data), 'cell');

  Future<Map<String, dynamic>> saveAgeGroup(Map<String, dynamic> data) async =>
      _successMap(await call('/api/church/age_group/save', data), 'age_group');

  Future<Map<String, dynamic>> saveDistrict(Map<String, dynamic> data) async =>
      _successMap(await call('/api/church/district/save', data), 'district');

  // ─── Imports Excel ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getImportKinds() async =>
      _successList(await call('/api/church/import/kinds', {}), 'kinds');

  /// Le modèle de l'église : `filename`, `content_base64`, `download_path`.
  Future<Map<String, dynamic>> getImportTemplate(String kind) async {
    final result = await call('/api/church/import/template', {'kind': kind});
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
  }

  /// Importe un fichier, tout ou rien. Un refus n'est pas une exception : il
  /// rend `ok: false` et la liste des erreurs à corriger.
  Future<Map<String, dynamic>> runImport(String kind, String filename, Uint8List bytes) async {
    final result = await call(
      '/api/church/import/run',
      {'kind': kind, 'filename': filename, 'content_base64': base64Encode(bytes)},
      // Un gros fichier se vérifie puis s'écrit d'un bloc : on attend, et on ne
      // renvoie pas la requête en double.
      retries: AppConstants.maxRetries,
      timeout: const Duration(minutes: 3),
    );
    if (result is Map && (result['status'] == 'success' || result['code'] == 'import_refused')) {
      return Map<String, dynamic>.from(result);
    }
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
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

  /// L'invitation à installer l'app (sans secret : on peut la renvoyer).
  Future<Map<String, dynamic>> shareInvitation(int targetUserId) async {
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

  // ─── Églises : celles de l'annuaire du réseau (Super Admin) ────────

  /// Les églises qui utilisent le suivi.
  Future<List<Map<String, dynamic>>> getChurches() async {
    final result = await call('/api/church/churches', {});
    return _successList(result, 'churches');
  }

  /// Cherche dans l'annuaire du réseau les églises pas encore dans le suivi.
  Future<List<Map<String, dynamic>>> searchDirectory(String query) async {
    final result = await call('/api/church/churches/directory', {'query': query});
    return _successList(result, 'churches');
  }

  /// Fait entrer une église dans le suivi : par son `church_id` dans
  /// l'annuaire, ou par son nom (reprise si elle y est déjà sous une autre
  /// écriture, créée sinon).
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

  Future<Map<String, dynamic>> createManager(String name, String phone, int churchId, {String email = ''}) async {
    return Map<String, dynamic>.from(
      await call('/api/church/manager/create', {
        'name': name,
        'phone': phone,
        'church_id': churchId,
        if (email.isNotEmpty) 'email': email,
      }),
    );
  }

  // ─── Pasteurs : lus dans l'annuaire du réseau ─────────────────────

  Future<List<Map<String, dynamic>>> getPastors({int? churchId}) async {
    final result = await call('/api/church/pastors', {
      if (churchId != null) 'church_id': churchId,
    });
    return _successList(result, 'pastors');
  }

  // ─── À faire, à attribuer, contrôles ─────────────────────────────

  /// Ce qui attend l'utilisateur : `{count, summary, items}`.
  Future<Map<String, dynamic>> getTodo() async {
    final result = await call('/api/church/todo', {});
    _ensureSuccess(result);
    return Map<String, dynamic>.from(result);
  }

  /// Nouvelles personnes à confier (`members`) et suivis interrompus (`interrupted`).
  Future<Map<String, List<Map<String, dynamic>>>> getPeopleToAssign() async {
    final result = await call('/api/church/followups/to_assign', {});
    _ensureSuccess(result);
    return {
      'members': _safeList(result['members']),
      'interrupted': _safeList(result['interrupted']),
    };
  }

  Future<List<Map<String, dynamic>>> getCheckpoints({String state = 'planned'}) async {
    final result = await call('/api/church/checkpoints', {'state': state});
    return _successList(result, 'checkpoints');
  }

  Future<Map<String, dynamic>> saveCheckpoint(Map<String, dynamic> data) async {
    return Map<String, dynamic>.from(await call('/api/church/checkpoint/save', data));
  }

  // ─── Téléphone (notifications push) ───────────────────────────────

  Future<void> registerDevice(String token, String platform, String label) async {
    await call('/api/church/device/register', {
      'device_token': token,
      'platform': platform,
      'device_label': label,
    });
  }

  Future<void> unregisterDevice(String token) async {
    try {
      await call('/api/church/device/unregister', {'device_token': token});
    } catch (_) {}
  }

  // ─── Mise à jour de l'application ─────────────────────────────────

  /// Ce que le catalogue sait de la dernière version publiée, comparée à
  /// celle-ci : `{update_available, mandatory, latest_version, download_url…}`.
  /// Rend `null` si l'on ne peut pas savoir (build de développement, réseau).
  Future<Map<String, dynamic>?> checkForUpdate() async {
    if (AppConstants.appVersion.isEmpty || _baseUrl.isEmpty) return null;
    try {
      final result = await call('/api/mobile/v1/apps/${AppConstants.appSlug}/latest',
          {'current_version': AppConstants.appVersion});
      return result is Map && result['status'] == 'success' ? Map<String, dynamic>.from(result) : null;
    } catch (_) {
      return null;
    }
  }

  // ─── Reports ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFollowupReport(int evangelistId) async {
    final result = await call('/api/church/report/followup', {'evangelist_id': evangelistId});
    return _successMap(result, 'report');
  }
}
