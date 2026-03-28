import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class CacheService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> put(String key, dynamic data) async {
    final p = await prefs;
    await p.setString('cache_$key', jsonEncode(data));
    await p.setInt('cache_${key}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  Future<dynamic> get(String key, {int maxAgeMinutes = AppConstants.cacheDurationMinutes}) async {
    final p = await prefs;
    final ts = p.getInt('cache_${key}_ts') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > maxAgeMinutes * 60 * 1000) return null;
    final raw = p.getString('cache_$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      await remove(key);
      return null;
    }
  }

  Future<void> remove(String key) async {
    final p = await prefs;
    await p.remove('cache_$key');
    await p.remove('cache_${key}_ts');
  }

  Future<void> clearAll() async {
    final p = await prefs;
    final keys = p.getKeys().where((k) => k.startsWith('cache_'));
    for (final key in keys) {
      await p.remove(key);
    }
  }
}
