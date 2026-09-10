import 'package:supabase_flutter/supabase_flutter.dart';

class AppResource {
  const AppResource({
    required this.id,
    required this.title,
    required this.url,
    required this.description,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String title;
  final String url;
  final String description;
  final int sortOrder;
  final bool isActive;

  factory AppResource.fromMap(Map<String, dynamic> map) {
    return AppResource(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
    );
  }
}

class ResourceService {
  ResourceService(this._client);

  final SupabaseClient _client;

  static String normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    return 'https://$trimmed';
  }

  Future<bool> isManager() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;

    final row = await _client.from('profiles').select('role').match({
      'user_id': uid,
    }).maybeSingle();
    return (row?['role'] ?? '').toString() == 'manager';
  }

  Future<List<AppResource>> fetchResources({
    required bool includeInactive,
  }) async {
    var query = _client.from('app_resources').select();
    if (!includeInactive) {
      query = query.eq('is_active', true);
    }

    final rows = await query
        .order('sort_order', ascending: true)
        .order('title', ascending: true);
    return (rows as List)
        .map(
          (row) => AppResource.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> saveResource({
    String? id,
    required String title,
    required String url,
    required String description,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = {
      'title': title.trim(),
      'url': normalizeUrl(url),
      'description': description.trim().isEmpty ? null : description.trim(),
      'sort_order': sortOrder,
      'is_active': isActive,
    };

    if (id == null || id.isEmpty) {
      await _client.from('app_resources').insert(data);
    } else {
      await _client.from('app_resources').update(data).eq('id', id);
    }
  }

  Future<void> deleteResource(String id) async {
    await _client.from('app_resources').delete().eq('id', id);
  }

  Future<void> reorderResources(List<AppResource> resources) async {
    await Future.wait([
      for (var i = 0; i < resources.length; i++)
        _client
            .from('app_resources')
            .update({'sort_order': i * 10})
            .eq('id', resources[i].id),
    ]);
  }
}
