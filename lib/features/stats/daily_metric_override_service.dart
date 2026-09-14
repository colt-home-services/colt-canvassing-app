import 'package:supabase_flutter/supabase_flutter.dart';

class DailyMetricOverrideService {
  DailyMetricOverrideService(this._client);

  final SupabaseClient _client;

  Future<Map<String, Map<String, dynamic>>> fetchOverrides({
    required DateTime start,
    required DateTime end,
    String? userId,
  }) async {
    var query = _client
        .from('manager_daily_metric_overrides')
        .select('user_id, work_date_ny, total_knocks, signed_ups')
        .gte('work_date_ny', _fmtYmd(start))
        .lte('work_date_ny', _fmtYmd(end));
    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }

    final rows = ((await query) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      for (final row in rows)
        _key(
          (row['user_id'] ?? '').toString(),
          (row['work_date_ny'] ?? '').toString(),
        ): row,
    }..removeWhere((key, value) => key.startsWith('|') || key.endsWith('|'));
  }

  List<Map<String, dynamic>> applyOverrides(
    List<Map<String, dynamic>> rows,
    Map<String, Map<String, dynamic>> overrides,
  ) {
    return rows.map((row) {
      final userId = (row['user_id'] ?? '').toString();
      final workDate = (row['work_date_ny'] ?? '').toString();
      final override = overrides[_key(userId, workDate)];
      if (override == null) return row;

      final adjusted = Map<String, dynamic>.from(row);
      if (override['total_knocks'] != null) {
        adjusted['total_knocks'] = override['total_knocks'];
      }
      if (override['signed_ups'] != null) {
        adjusted['signed_ups'] = override['signed_ups'];
      }
      _recalculateRates(adjusted);
      return adjusted;
    }).toList();
  }

  Future<void> setOverride({
    required String userId,
    required String workDateNy,
    int? totalKnocks,
    int? signedUps,
  }) async {
    await _client.rpc(
      'manager_set_daily_metric_override',
      params: {
        'p_user_id': userId,
        'p_work_date_ny': workDateNy,
        'p_total_knocks': totalKnocks,
        'p_signed_ups': signedUps,
      },
    );
  }

  void _recalculateRates(Map<String, dynamic> row) {
    final knocks = _toNum(row['total_knocks']);
    final answers = _toNum(row['answers']);
    final signups = _toNum(row['signed_ups']);
    final hours = _toNum(row['billable_hours']);

    row['answer_rate'] = knocks > 0 ? answers / knocks : 0.0;
    row['signup_rate'] = answers > 0 ? signups / answers : 0.0;
    row['knocks_per_billable_hour'] = hours > 0 ? knocks / hours : 0.0;
  }

  String _fmtYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _key(String userId, String workDateNy) => '$userId|$workDateNy';

  num _toNum(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? 0;
  }
}
