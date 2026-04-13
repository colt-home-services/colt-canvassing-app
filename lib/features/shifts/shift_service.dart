import 'package:supabase_flutter/supabase_flutter.dart';

class Shift {
  final String id;
  final String userId;
  final DateTime clockInAt;
  final DateTime? clockOutAt;

  const Shift({
    required this.id,
    required this.userId,
    required this.clockInAt,
    required this.clockOutAt,
  });

  bool get isOpen => clockOutAt == null;

  Duration get duration =>
      (clockOutAt ?? DateTime.now()).difference(clockInAt);

  factory Shift.fromMap(Map<String, dynamic> m) => Shift(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        clockInAt: DateTime.parse(m['clock_in_at'] as String).toLocal(),
        clockOutAt: m['clock_out_at'] == null
            ? null
            : DateTime.parse(m['clock_out_at'] as String).toLocal(),
      );
}

class ShiftService {
  ShiftService(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<Shift?> activeShift() async {
    final uid = _userId;
    if (uid == null) return null;

    final rows = await _client
        .from('shifts')
        .select()
        .match({'user_id': uid})
        .filter('clock_out_at', 'is', null)
        .limit(1);

    final list = (rows as List);
    if (list.isEmpty) return null;
    return Shift.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  /// Returns all shifts whose clock-in timestamp is on or after local midnight today.
  Future<List<Shift>> todayShifts() async {
    final uid = _userId;
    if (uid == null) return const [];

    final now = DateTime.now();
    final localMidnight = DateTime(now.year, now.month, now.day);

    final rows = await _client
        .from('shifts')
        .select()
        .match({'user_id': uid})
        .gte('clock_in_at', localMidnight.toUtc().toIso8601String())
        .order('clock_in_at', ascending: true);

    return (rows as List)
        .map((e) => Shift.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Shift> clockIn({double? lat, double? lon, double? accuracyM}) async {
    final row = await _client.rpc('clock_in', params: {
      'p_lat': lat,
      'p_lon': lon,
      'p_accuracy_m': accuracyM,
    });
    return Shift.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<Shift?> clockOut({double? lat, double? lon, double? accuracyM}) async {
    final row = await _client.rpc('clock_out', params: {
      'p_lat': lat,
      'p_lon': lon,
      'p_accuracy_m': accuracyM,
    });
    if (row == null) return null;
    return Shift.fromMap(Map<String, dynamic>.from(row as Map));
  }
}
