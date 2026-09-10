import 'package:supabase_flutter/supabase_flutter.dart';

class WeeklySignupGoal {
  final String userId;
  final String? userEmail;
  final DateTime weekStartNy;
  final int goalSignups;
  final int knockSignups;
  final int shiftSignups;

  const WeeklySignupGoal({
    required this.userId,
    required this.userEmail,
    required this.weekStartNy,
    required this.goalSignups,
    required this.knockSignups,
    required this.shiftSignups,
  });

  int get actualSignups => knockSignups + shiftSignups;
  int get remainingSignups => goalSignups - actualSignups;
  bool get isComplete => remainingSignups <= 0;
  double get progress {
    if (goalSignups <= 0) return 0;
    final ratio = actualSignups / goalSignups;
    return ratio > 1 ? 1.0 : ratio.toDouble();
  }
}

class WeeklyGoalService {
  WeeklyGoalService(this._client);

  final SupabaseClient _client;

  String fmtYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime currentWeekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  DateTime weekEndExclusive(DateTime weekStart) {
    return DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    ).add(const Duration(days: 7));
  }

  Future<Map<String, WeeklySignupGoal>> fetchGoalsWithProgress({
    required DateTime weekStart,
    List<String>? userIds,
    String performanceSource = 'v_performance_daily',
  }) async {
    final weekStartStr = fmtYmd(weekStart);
    final weekEndStr = fmtYmd(weekEndExclusive(weekStart));

    var goalsQuery = _client
        .from('weekly_signup_goals')
        .select('user_id, week_start_ny, goal_signups')
        .eq('week_start_ny', weekStartStr);
    if (userIds != null && userIds.isNotEmpty) {
      goalsQuery = goalsQuery.inFilter('user_id', userIds);
    }
    final goalRows = ((await goalsQuery) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    var perfQuery = _client
        .from(performanceSource)
        .select('user_id, work_date_ny, signed_ups')
        .gte('work_date_ny', weekStartStr)
        .lt('work_date_ny', weekEndStr);
    if (userIds != null && userIds.isNotEmpty) {
      perfQuery = perfQuery.inFilter('user_id', userIds);
    }
    final perfRows = ((await perfQuery) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    var overridesQuery = _client
        .from('canvasser_daily_metric_overrides')
        .select('user_id, work_date_ny, signed_ups')
        .gte('work_date_ny', weekStartStr)
        .lt('work_date_ny', weekEndStr);
    if (userIds != null && userIds.isNotEmpty) {
      overridesQuery = overridesQuery.inFilter('user_id', userIds);
    }
    final overrideRows = ((await overridesQuery) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    var shiftQuery = _client
        .from('v_shifts_detail')
        .select('user_id, user_email, self_reported_signups')
        .gte('work_date_ny', weekStartStr)
        .lt('work_date_ny', weekEndStr)
        .filter('disallowed_at', 'is', null);
    if (userIds != null && userIds.isNotEmpty) {
      shiftQuery = shiftQuery.inFilter('user_id', userIds);
    }
    final shiftRows = ((await shiftQuery) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final knockSignupsByUserDate = <String, int>{};
    for (final row in perfRows) {
      final userId = (row['user_id'] ?? '').toString();
      final workDate = (row['work_date_ny'] ?? '').toString();
      if (userId.isEmpty || workDate.isEmpty) continue;
      final key = _key(userId, workDate);
      knockSignupsByUserDate[key] =
          (knockSignupsByUserDate[key] ?? 0) + _toInt(row['signed_ups']);
    }

    for (final row in overrideRows) {
      if (row['signed_ups'] == null) continue;
      final userId = (row['user_id'] ?? '').toString();
      final workDate = (row['work_date_ny'] ?? '').toString();
      if (userId.isEmpty || workDate.isEmpty) continue;
      knockSignupsByUserDate[_key(userId, workDate)] = _toInt(
        row['signed_ups'],
      );
    }

    final knockSignupsByUser = <String, int>{};
    for (final entry in knockSignupsByUserDate.entries) {
      final userId = entry.key.split('|').first;
      knockSignupsByUser[userId] =
          (knockSignupsByUser[userId] ?? 0) + entry.value;
    }

    final shiftSignupsByUser = <String, int>{};
    final emailByUser = <String, String>{};
    for (final row in shiftRows) {
      final userId = (row['user_id'] ?? '').toString();
      if (userId.isEmpty) continue;
      final email = (row['user_email'] ?? '').toString();
      if (email.isNotEmpty) emailByUser[userId] = email;
      shiftSignupsByUser[userId] =
          (shiftSignupsByUser[userId] ?? 0) +
          _toInt(row['self_reported_signups']);
    }

    final goalRowsByUser = {
      for (final row in goalRows)
        (row['user_id'] ?? '').toString(): Map<String, dynamic>.from(row),
    }..removeWhere((key, value) => key.isEmpty);

    final resultUserIds = <String>{
      ...goalRowsByUser.keys,
      ...knockSignupsByUser.keys,
      ...shiftSignupsByUser.keys,
      if (userIds != null) ...userIds.where((id) => id.isNotEmpty),
    };

    return {
      for (final userId in resultUserIds)
        userId: WeeklySignupGoal(
          userId: userId,
          userEmail: emailByUser[userId],
          weekStartNy: goalRowsByUser[userId] == null
              ? weekStart
              : DateTime.parse(
                  goalRowsByUser[userId]!['week_start_ny'].toString(),
                ),
          goalSignups: _toInt(goalRowsByUser[userId]?['goal_signups']),
          knockSignups: knockSignupsByUser[userId] ?? 0,
          shiftSignups: shiftSignupsByUser[userId] ?? 0,
        ),
    };
  }

  Future<WeeklySignupGoal?> fetchCurrentUserGoal() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final goals = await fetchGoalsWithProgress(
      weekStart: currentWeekStart(),
      userIds: [uid],
    );
    return goals[uid];
  }

  Future<void> setGoal({
    required String userId,
    required DateTime weekStart,
    required int goalSignups,
  }) async {
    await _client.from('weekly_signup_goals').upsert({
      'user_id': userId,
      'week_start_ny': fmtYmd(weekStart),
      'goal_signups': goalSignups,
    }, onConflict: 'user_id,week_start_ny');
  }

  Future<void> setGoals({
    required Iterable<String> userIds,
    required DateTime weekStart,
    required int goalSignups,
  }) async {
    final rows = userIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .map(
          (userId) => {
            'user_id': userId,
            'week_start_ny': fmtYmd(weekStart),
            'goal_signups': goalSignups,
          },
        )
        .toList();
    if (rows.isEmpty) return;

    await _client
        .from('weekly_signup_goals')
        .upsert(rows, onConflict: 'user_id,week_start_ny');
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _key(String userId, String workDateNy) => '$userId|$workDateNy';
}
