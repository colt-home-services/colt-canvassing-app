import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TownsCache {
  static const _key = 'towns_cache_v1';

  static Future<List<String>?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final towns = decoded.map((e) => e.toString()).toList();
      return towns.isEmpty ? null : towns;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(List<String> towns) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(towns));
    } catch (_) {}
  }

  static List<String> _normalize(List<dynamic> raw) {
    return raw
        .map((e) {
          if (e is Map && e['town'] is String) return e['town'] as String;
          if (e is String) return e;
          return e.toString();
        })
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => t.toUpperCase())
        .toSet()
        .toList()
      ..sort();
  }

  static Future<List<String>> fetchWithRetry(SupabaseClient client) async {
    Object? lastError;
    const timeouts = [Duration(seconds: 20), Duration(seconds: 30)];
    for (var attempt = 0; attempt < timeouts.length; attempt++) {
      try {
        final data = await client
            .rpc('get_unique_towns')
            .timeout(timeouts[attempt]);
        return _normalize(data as List<dynamic>);
      } catch (e) {
        lastError = e;
        if (attempt < timeouts.length - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    throw lastError ?? Exception('Unknown error loading towns');
  }

  static Future<List<String>> refresh(SupabaseClient client) async {
    final towns = await fetchWithRetry(client);
    await write(towns);
    return towns;
  }
}
