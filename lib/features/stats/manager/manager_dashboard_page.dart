import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../canvassing/towns_page.dart';
import '../../shifts/manager_shifts_page.dart';
import 'bucket_drilldown_page.dart';
import 'route_map_dialog.dart';

class ManagerDashboardPage extends StatefulWidget {
  const ManagerDashboardPage({super.key});

  @override
  State<ManagerDashboardPage> createState() => _ManagerDashboardPageState();
}

class _ManagerDashboardPageState extends State<ManagerDashboardPage> {
  final _supabase = Supabase.instance.client;

  DateTimeRange? _range;
  List<String> _selectedCanvassers = [];
  List<String> _selectedZipCodes = [];
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  Set<String> _selectedOutcomes = {'knocked', 'answered', 'signed_up'};

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  List<String> _availableCanvassers = [];
  bool _showFilters = false;
  late TextEditingController _zipTextController;

  // Analytics state
  Map<String, dynamic> _kpiTotals = {};
  Map<String, dynamic> _kpiTotalsAllData = {}; // For showing all data initially
  List<Map<String, dynamic>> _allRows = []; // Unfiltered data
  List<Map<String, dynamic>> _shiftRows = []; // Raw v_shifts_detail rows in range
  List<Map<String, dynamic>> _leaderboardData = [];
  String _leaderboardSortBy = 'answers_per_hour';
  List<Map<String, dynamic>> _hourlyPerformance = [];
  List<Map<String, dynamic>> _dailyPerformance = [];
  List<Map<String, dynamic>> _zipPerformance = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 14)),
      end: now,
    );
    _zipTextController = TextEditingController();
    _loadFilterOptions();
    _fetch();
  }

  @override
  void dispose() {
    _zipTextController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterOptions() async {
    try {
      // Load unique canvassers
      final canvassersData = await _supabase
          .from('v_manager_daily_summary')
          .select('user_email')
          .order('user_email');

      final canvassers =
          (canvassersData as List)
              .map((e) => (e['user_email'] ?? '').toString())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      setState(() {
        _availableCanvassers = canvassers;
      });
    } catch (e) {
      debugPrint('Error loading filter options: $e');
    }
  }

  String _fmtYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    if (_range == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final startStr = _fmtYmd(_range!.start);
      final endStr = _fmtYmd(_range!.end);

      var query = _supabase
          .from('v_manager_daily_summary')
          .select()
          .gte('work_date_ny', startStr)
          .lte('work_date_ny', endStr);

      var allRows =
          (await query.order('work_date_ny', ascending: false) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      // Store unfiltered data
      _allRows = allRows;

      // Fetch shift rows for the same date range (used for Total Shift Hours KPI)
      final shiftStartUtc = DateTime(
        _range!.start.year,
        _range!.start.month,
        _range!.start.day,
      ).toUtc().toIso8601String();
      final shiftEndUtc = DateTime(
        _range!.end.year,
        _range!.end.month,
        _range!.end.day,
      ).add(const Duration(days: 1)).toUtc().toIso8601String();

      _shiftRows = ((await _supabase
              .from('v_shifts_detail')
              .select('user_email, duration_seconds, clock_in_at')
              .gte('clock_in_at', shiftStartUtc)
              .lt('clock_in_at', shiftEndUtc)
              .filter('disallowed_at', 'is', null)) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Apply canvasser filter
      var filteredRows = allRows;
      if (_selectedCanvassers.isNotEmpty) {
        filteredRows = filteredRows
            .where(
              (r) => _selectedCanvassers.contains(
                (r['user_email'] ?? '').toString(),
              ),
            )
            .toList();
      }

      // Apply ZIP code filter (need to query house_events for this)
      if (_selectedZipCodes.isNotEmpty ||
          _startTime != null ||
          _endTime != null ||
          _selectedOutcomes.length < 3) {
        filteredRows = await _applyAdvancedFilters(filteredRows);
      }

      // Calculate analytics from summary data
      _calculateKPITotals(filteredRows);
      _calculateKPITotals(_allRows, isAllData: true); // Calculate for all data
      _buildLeaderboardData(
        _allRows,
      ); // Leaderboard always shows all canvassers

      // Fetch and analyze detailed event data (async)
      _analyzeTimeAndZIPPerformance();

      setState(() {
        _rows = filteredRows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _applyAdvancedFilters(
    List<Map<String, dynamic>> summaryRows,
  ) async {
    if (summaryRows.isEmpty) return summaryRows;

    // For each summary row, verify it matches the advanced filters
    final filteredRows = <Map<String, dynamic>>[];

    for (final row in summaryRows) {
      final userId = row['user_id'];
      final workDate = row['work_date_ny'];

      if (userId == null || workDate == null) continue;

      // Query house_events for this user and date
      var eventQuery = _supabase
          .from('house_events')
          .select('*, houses!inner(zip)')
          .eq('user_id', userId)
          .gte('created_at', '$workDate 00:00:00')
          .lte('created_at', '$workDate 23:59:59');

      // Filter by outcomes
      if (_selectedOutcomes.isNotEmpty && _selectedOutcomes.length < 3) {
        eventQuery = eventQuery.inFilter(
          'event_type',
          _selectedOutcomes.toList(),
        );
      }

      final events = (await eventQuery as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (events.isEmpty) continue;

      // Apply ZIP code filter
      if (_selectedZipCodes.isNotEmpty) {
        final hasMatchingZip = events.any((e) {
          final houseData = e['houses'];
          if (houseData is Map) {
            final zip = (houseData['zip'] ?? '').toString();
            return _selectedZipCodes.contains(zip);
          }
          return false;
        });

        if (!hasMatchingZip) continue;
      }

      // Apply time of day filter
      if (_startTime != null || _endTime != null) {
        final hasMatchingTime = events.any((e) {
          try {
            final createdAt = DateTime.parse(
              e['created_at'].toString(),
            ).toLocal();
            final eventMinutes = createdAt.hour * 60 + createdAt.minute;

            final startMinutes = _startTime != null
                ? _startTime!.hour * 60 + _startTime!.minute
                : 0;
            final endMinutes = _endTime != null
                ? _endTime!.hour * 60 + _endTime!.minute
                : 24 * 60;

            return eventMinutes >= startMinutes && eventMinutes <= endMinutes;
          } catch (_) {
            return false;
          }
        });

        if (!hasMatchingTime) continue;
      }

      filteredRows.add(row);
    }

    return filteredRows;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
      await _fetch();
    }
  }

  String _num(dynamic v) => v == null ? '-' : v.toString();

  String _numFixed(dynamic v, {int decimals = 2}) {
    if (v == null) return '-';
    final n = v is num ? v : num.tryParse(v.toString());
    if (n == null) return '-';
    return n.toStringAsFixed(decimals);
  }

  String _pct(dynamic v) {
    if (v == null) return '-';
    final n = v is num ? v : num.tryParse(v.toString());
    if (n == null) return '-';
    return '${(n * 100).toStringAsFixed(1)}%';
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  void _openDrilldown(Map<String, dynamic> r) {
    final userId = (r['user_id'] ?? '').toString();
    final email = (r['user_email'] ?? '').toString();
    final workDateNy = (r['work_date_ny'] ?? '').toString();

    if (userId.isEmpty || workDateNy.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BucketDrilldownPage(
          userId: userId,
          userEmail: email,
          workDateNy: workDateNy,
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _selectedCanvassers.isNotEmpty ||
        _selectedZipCodes.isNotEmpty ||
        _startTime != null ||
        _endTime != null ||
        _selectedOutcomes.length < 3;
  }

  void _clearFilters() {
    setState(() {
      _selectedCanvassers.clear();
      _selectedZipCodes.clear();
      _startTime = null;
      _endTime = null;
      _selectedOutcomes = {'knocked', 'answered', 'signed_up'};
    });
    _fetch();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
      _fetch();
    }
  }

  bool _validateZip(String zip) {
    final trimmed = zip.trim();
    return RegExp(r'^\d{5}$').hasMatch(trimmed);
  }

  void _addManualZip(String input) {
    final zip = input.trim();

    if (zip.isEmpty) return;

    if (_validateZip(zip)) {
      setState(() {
        if (!_selectedZipCodes.contains(zip)) {
          _selectedZipCodes.add(zip);
        }
        _zipTextController.clear();
      });
      _fetch();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid ZIP code: $zip (must be 5 digits)'),
          backgroundColor: const Color.fromARGB(255, 255, 0, 0),
        ),
      );
    }
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  void _calculateKPITotals(
    List<Map<String, dynamic>> rows, {
    bool isAllData = false,
  }) {
    final shiftSeconds = _sumShiftSeconds(isAllData: isAllData);

    if (rows.isEmpty) {
      final emptyData = {
        'knocks': 0,
        'answers': 0,
        'signups': 0,
        'hours': 0,
        'answer_rate': 0.0,
        'knocks_per_hour': 0.0,
        'answers_per_hour': 0.0,
        'shift_seconds': shiftSeconds,
      };
      if (isAllData) {
        _kpiTotalsAllData = emptyData;
      } else {
        _kpiTotals = emptyData;
      }
      return;
    }

    final totalKnocks = rows.fold<num>(
      0,
      (s, r) => s + _toNum(r['total_knocks']),
    );
    final totalAnswers = rows.fold<num>(0, (s, r) => s + _toNum(r['answers']));
    final totalSignups = rows.fold<num>(
      0,
      (s, r) => s + _toNum(r['signed_ups']),
    );
    final totalHours = rows.fold<num>(
      0,
      (s, r) => s + _toNum(r['billable_hours']),
    );

    final answerRate = totalKnocks > 0 ? totalAnswers / totalKnocks : 0.0;
    final knocksPerHour = totalHours > 0 ? totalKnocks / totalHours : 0.0;
    final answersPerHour = totalHours > 0 ? totalAnswers / totalHours : 0.0;

    final data = {
      'knocks': totalKnocks,
      'answers': totalAnswers,
      'signups': totalSignups,
      'hours': totalHours,
      'answer_rate': answerRate,
      'knocks_per_hour': knocksPerHour,
      'answers_per_hour': answersPerHour,
      'shift_seconds': shiftSeconds,
    };

    if (isAllData) {
      _kpiTotalsAllData = data;
    } else {
      _kpiTotals = data;
    }
  }

  /// Sums duration_seconds across `_shiftRows`. When `isAllData` is false
  /// and a canvasser filter is active, sums only matching rows.
  num _sumShiftSeconds({required bool isAllData}) {
    final useFilter = !isAllData && _selectedCanvassers.isNotEmpty;
    return _shiftRows.fold<num>(0, (s, r) {
      if (useFilter &&
          !_selectedCanvassers.contains((r['user_email'] ?? '').toString())) {
        return s;
      }
      return s + _toNum(r['duration_seconds']);
    });
  }

  String _fmtShiftHours(num seconds) {
    final total = seconds.toInt();
    final h = total ~/ 3600;
    final m = ((total % 3600) / 60).round();
    return '${h}h ${m}m';
  }

  void _buildLeaderboardData(List<Map<String, dynamic>> rows) {
    // Group by canvasser
    final canvasserMap = <String, Map<String, num>>{};

    for (final row in rows) {
      final email = (row['user_email'] ?? '').toString();
      if (email.isEmpty) continue;

      canvasserMap.putIfAbsent(
        email,
        () => {'knocks': 0, 'answers': 0, 'signups': 0, 'hours': 0},
      );

      canvasserMap[email]!['knocks'] =
          (canvasserMap[email]!['knocks'] ?? 0) + _toNum(row['total_knocks']);
      canvasserMap[email]!['answers'] =
          (canvasserMap[email]!['answers'] ?? 0) + _toNum(row['answers']);
      canvasserMap[email]!['signups'] =
          (canvasserMap[email]!['signups'] ?? 0) + _toNum(row['signed_ups']);
      canvasserMap[email]!['hours'] =
          (canvasserMap[email]!['hours'] ?? 0) + _toNum(row['billable_hours']);
    }

    // Build leaderboard list with calculated metrics
    _leaderboardData = canvasserMap.entries.map((entry) {
      final knocks = entry.value['knocks'] ?? 0;
      final answers = entry.value['answers'] ?? 0;
      final signups = entry.value['signups'] ?? 0;
      final hours = entry.value['hours'] ?? 0;

      final answerRate = knocks > 0 ? answers / knocks : 0.0;
      final knocksPerHour = hours > 0 ? knocks / hours : 0.0;
      final answersPerHour = hours > 0 ? answers / hours : 0.0;

      return {
        'email': entry.key,
        'knocks': knocks,
        'answers': answers,
        'signups': signups,
        'hours': hours,
        'answer_rate': answerRate,
        'knocks_per_hour': knocksPerHour,
        'answers_per_hour': answersPerHour,
      };
    }).toList();

    // Sort by selected metric
    _sortLeaderboard();
  }

  void _sortLeaderboard() {
    _leaderboardData.sort((a, b) {
      final aVal = a[_leaderboardSortBy] ?? 0;
      final bVal = b[_leaderboardSortBy] ?? 0;
      return (bVal as num).compareTo(aVal as num); // Descending order
    });
  }

  Future<void> _analyzeTimeAndZIPPerformance() async {
    if (_range == null) return;

    try {
      final startStr = _fmtYmd(_range!.start);
      final endStr = _fmtYmd(_range!.end);

      // Query house_events with current filters
      var eventQuery = _supabase
          .from('house_events')
          .select('created_at, event_type, user_id, houses!inner(zip)')
          .gte('created_at', '$startStr 00:00:00')
          .lte('created_at', '$endStr 23:59:59');

      // Apply canvasser filter
      if (_selectedCanvassers.isNotEmpty) {
        // Get user IDs for selected emails
        final userIds = _rows
            .where((r) => _selectedCanvassers.contains(r['user_email']))
            .map((r) => r['user_id'].toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (userIds.isNotEmpty) {
          eventQuery = eventQuery.inFilter('user_id', userIds);
        }
      }

      // Apply outcome filter
      if (_selectedOutcomes.isNotEmpty && _selectedOutcomes.length < 3) {
        eventQuery = eventQuery.inFilter(
          'event_type',
          _selectedOutcomes.toList(),
        );
      }

      final events = (await eventQuery as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Analyze by hour of day
      _analyzeHourlyPerformance(events);

      // Analyze by day of week
      _analyzeDailyPerformance(events);

      // Analyze by ZIP code
      _analyzeZIPPerformance(events);
    } catch (e) {
      debugPrint('Error analyzing time/ZIP performance: $e');
    }
  }

  void _analyzeHourlyPerformance(List<Map<String, dynamic>> events) {
    final hourlyMap = <int, Map<String, int>>{};

    // Initialize all 24 hours
    for (var hour = 0; hour < 24; hour++) {
      hourlyMap[hour] = {'knocks': 0, 'answers': 0, 'signups': 0};
    }

    // Count events by hour
    for (final event in events) {
      try {
        final dt = DateTime.parse(event['created_at'].toString()).toLocal();
        final hour = dt.hour;
        final type = event['event_type'].toString();

        if (type == 'knocked')
          hourlyMap[hour]!['knocks'] = (hourlyMap[hour]!['knocks'] ?? 0) + 1;
        if (type == 'answered')
          hourlyMap[hour]!['answers'] = (hourlyMap[hour]!['answers'] ?? 0) + 1;
        if (type == 'signed_up')
          hourlyMap[hour]!['signups'] = (hourlyMap[hour]!['signups'] ?? 0) + 1;
      } catch (_) {}
    }

    // Convert to list and calculate rates
    _hourlyPerformance = hourlyMap.entries.map((entry) {
      final knocks = entry.value['knocks'] ?? 0;
      final answers = entry.value['answers'] ?? 0;
      final answerRate = knocks > 0 ? answers / knocks : 0.0;

      return {
        'hour': entry.key,
        'knocks': knocks,
        'answers': answers,
        'answer_rate': answerRate,
      };
    }).toList()..sort((a, b) => (a['hour'] as int).compareTo(b['hour'] as int));
  }

  void _analyzeDailyPerformance(List<Map<String, dynamic>> events) {
    final dailyMap = <int, Map<String, int>>{};

    // Initialize all 7 days (0=Sunday, 6=Saturday)
    for (var day = 0; day < 7; day++) {
      dailyMap[day] = {'knocks': 0, 'answers': 0, 'signups': 0};
    }

    // Count events by day of week
    for (final event in events) {
      try {
        final dt = DateTime.parse(event['created_at'].toString()).toLocal();
        final dayOfWeek = dt.weekday % 7; // Convert Monday=1 to Sunday=0
        final type = event['event_type'].toString();

        if (type == 'knocked')
          dailyMap[dayOfWeek]!['knocks'] =
              (dailyMap[dayOfWeek]!['knocks'] ?? 0) + 1;
        if (type == 'answered')
          dailyMap[dayOfWeek]!['answers'] =
              (dailyMap[dayOfWeek]!['answers'] ?? 0) + 1;
        if (type == 'signed_up')
          dailyMap[dayOfWeek]!['signups'] =
              (dailyMap[dayOfWeek]!['signups'] ?? 0) + 1;
      } catch (_) {}
    }

    // Convert to list and calculate rates
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    _dailyPerformance = dailyMap.entries.map((entry) {
      final knocks = entry.value['knocks'] ?? 0;
      final answers = entry.value['answers'] ?? 0;
      final answerRate = knocks > 0 ? answers / knocks : 0.0;

      return {
        'day': entry.key,
        'day_name': dayNames[entry.key],
        'knocks': knocks,
        'answers': answers,
        'answer_rate': answerRate,
      };
    }).toList()..sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));
  }

  void _analyzeZIPPerformance(List<Map<String, dynamic>> events) {
    final zipMap = <String, Map<String, int>>{};

    // Count events by ZIP code
    for (final event in events) {
      try {
        final houseData = event['houses'];
        if (houseData == null || houseData is! Map) continue;

        final zip = (houseData['zip'] ?? '').toString();
        if (zip.isEmpty) continue;

        final type = event['event_type'].toString();

        zipMap.putIfAbsent(
          zip,
          () => {'knocks': 0, 'answers': 0, 'signups': 0},
        );

        if (type == 'knocked')
          zipMap[zip]!['knocks'] = (zipMap[zip]!['knocks'] ?? 0) + 1;
        if (type == 'answered')
          zipMap[zip]!['answers'] = (zipMap[zip]!['answers'] ?? 0) + 1;
        if (type == 'signed_up')
          zipMap[zip]!['signups'] = (zipMap[zip]!['signups'] ?? 0) + 1;
      } catch (_) {}
    }

    // Filter by minimum sample size and calculate rates
    _zipPerformance =
        zipMap.entries
            .where(
              (entry) => (entry.value['knocks'] ?? 0) >= 20,
            ) // Minimum 20 knocks
            .map((entry) {
              final knocks = entry.value['knocks'] ?? 0;
              final answers = entry.value['answers'] ?? 0;
              final answerRate = knocks > 0 ? answers / knocks : 0.0;

              return {
                'zip': entry.key,
                'knocks': knocks,
                'answers': answers,
                'answer_rate': answerRate,
              };
            })
            .toList()
          ..sort(
            (a, b) =>
                (b['answer_rate'] as num).compareTo(a['answer_rate'] as num),
          ); // Sort by answer rate desc

    // Keep only top 10
    if (_zipPerformance.length > 10) {
      _zipPerformance = _zipPerformance.sublist(0, 10);
    }
  }

  Widget _buildCanvasserDropdown() {
    return PopupMenuButton<String>(
      tooltip: 'Select canvassers',
      offset: const Offset(0, 40),
      itemBuilder: (context) {
        return _availableCanvassers.map((email) {
          final isSelected = _selectedCanvassers.contains(email);
          return PopupMenuItem<String>(
            value: email,
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedCanvassers.remove(email);
                } else {
                  _selectedCanvassers.add(email);
                }
              });
              _fetch();
            },
            child: Row(
              children: [
                if (isSelected) const Icon(Icons.check, size: 16),
                if (isSelected) const SizedBox(width: 8),
                Expanded(
                  child: Text(email, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Select',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 20, color: Colors.black87),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    final hasSelections =
        _selectedCanvassers.isNotEmpty || _selectedZipCodes.isNotEmpty;

    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter controls row
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Canvassers filter
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Canvassers',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildCanvasserDropdown(),
                  ],
                ),

                // ZIP codes filter
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ZIP Codes',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: _zipTextController,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'Enter ZIP',
                              hintStyle: TextStyle(fontSize: 14),
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            onSubmitted: _addManualZip,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: () =>
                              _addManualZip(_zipTextController.text),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ],
                ),

                // Time of day filter
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Time of Day',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _pickTime(true),
                          icon: const Icon(Icons.access_time, size: 16),
                          label: Text(
                            _startTime != null
                                ? _startTime!.format(context)
                                : 'Start',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('to'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickTime(false),
                          icon: const Icon(Icons.access_time, size: 16),
                          label: Text(
                            _endTime != null
                                ? _endTime!.format(context)
                                : 'End',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                        if (_startTime != null || _endTime != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: 'Clear time filter',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _startTime = null;
                                _endTime = null;
                              });
                              _fetch();
                            },
                          ),
                      ],
                    ),
                  ],
                ),

                // Knock outcomes filter
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Outcomes',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          label: const Text(
                            'Knocked',
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: _selectedOutcomes.contains('knocked'),
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedOutcomes.add('knocked');
                              } else {
                                _selectedOutcomes.remove('knocked');
                              }
                            });
                            _fetch();
                          },
                        ),
                        FilterChip(
                          label: const Text(
                            'Answered',
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: _selectedOutcomes.contains('answered'),
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedOutcomes.add('answered');
                              } else {
                                _selectedOutcomes.remove('answered');
                              }
                            });
                            _fetch();
                          },
                        ),
                        FilterChip(
                          label: const Text(
                            'Signed Up',
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: _selectedOutcomes.contains('signed_up'),
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedOutcomes.add('signed_up');
                              } else {
                                _selectedOutcomes.remove('signed_up');
                              }
                            });
                            _fetch();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            // Active filters section (only show if there are selections)
            if (hasSelections) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ..._selectedCanvassers.map((email) {
                    return FilterChip(
                      avatar: const Icon(Icons.person, size: 14),
                      label: Text(email, style: const TextStyle(fontSize: 12)),
                      selected: true,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCanvassers.remove(email);
                        });
                        _fetch();
                      },
                    );
                  }),
                  ..._selectedZipCodes.map((zip) {
                    return FilterChip(
                      avatar: const Icon(Icons.location_on, size: 14),
                      label: Text(zip, style: const TextStyle(fontSize: 12)),
                      selected: true,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          _selectedZipCodes.remove(zip);
                        });
                        _fetch();
                      },
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKPISection() {
    // Use filtered data if filters are active, otherwise use all data
    final hasActiveFilters = _hasActiveFilters();
    final kpiData = hasActiveFilters ? _kpiTotals : _kpiTotalsAllData;

    if (kpiData.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (hasActiveFilters)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'FILTERED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ALL DATA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _buildKPIMetric(
                  'Knocks',
                  kpiData['knocks']?.toStringAsFixed(0) ?? '0',
                  Icons.door_front_door,
                ),
                _buildKPIMetric(
                  'Answers',
                  kpiData['answers']?.toStringAsFixed(0) ?? '0',
                  Icons.person,
                ),
                _buildKPIMetric(
                  'Signups',
                  kpiData['signups']?.toStringAsFixed(0) ?? '0',
                  Icons.check_circle,
                  highlighted: true,
                ),
                _buildKPIMetric(
                  'Answer Rate',
                  '${(kpiData['answer_rate'] * 100).toStringAsFixed(1)}%',
                  Icons.percent,
                  highlighted: true,
                ),
                _buildKPIMetric(
                  'Knocks/Hour',
                  kpiData['knocks_per_hour']?.toStringAsFixed(1) ?? '0',
                  Icons.speed,
                ),
                _buildKPIMetric(
                  'Answers/Hour',
                  kpiData['answers_per_hour']?.toStringAsFixed(1) ?? '0',
                  Icons.schedule,
                  highlighted: true,
                ),
                _buildKPIMetric(
                  'Shift Hours',
                  _fmtShiftHours(_toNum(kpiData['shift_seconds'])),
                  Icons.access_time,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIMetric(
    String label,
    String value,
    IconData icon, {
    bool highlighted = false,
  }) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: highlighted ? Colors.blue.shade700 : Colors.black54,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: highlighted ? 24 : 20,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w700,
              color: highlighted ? Colors.blue.shade700 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaderboardModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(
        alpha: 0.5,
      ), // Semi-transparent blur
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events,
                      color: Colors.amber,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Leaderboard',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Sort by:',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _leaderboardSortBy,
                      items: const [
                        DropdownMenuItem(
                          value: 'answers_per_hour',
                          child: Text('Answers/Hr'),
                        ),
                        DropdownMenuItem(
                          value: 'answer_rate',
                          child: Text('Answer Rate'),
                        ),
                        DropdownMenuItem(
                          value: 'knocks_per_hour',
                          child: Text('Knocks/Hr'),
                        ),
                        DropdownMenuItem(
                          value: 'signups',
                          child: Text('Signups'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _leaderboardSortBy = value;
                            _sortLeaderboard();
                          });
                          Navigator.of(context).pop();
                          _showLeaderboardModal(); // Reopen with new sort
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Expanded(
                  child: _leaderboardData.isEmpty
                      ? const Center(child: Text('No data available'))
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 48,
                              dataRowMinHeight: 40,
                              dataRowMaxHeight: 40,
                              columnSpacing: 32,
                              columns: const [
                                DataColumn(
                                  label: Text(
                                    'Rank',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Canvasser',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Answers/Hr',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Answer Rate',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Knocks/Hr',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Signups',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              rows: _leaderboardData.asMap().entries.map((
                                entry,
                              ) {
                                final idx = entry.key;
                                final data = entry.value;
                                final isTopThree = idx < 3;

                                return DataRow(
                                  color: WidgetStateProperty.resolveWith((
                                    states,
                                  ) {
                                    if (idx == 0) return Colors.amber.shade50;
                                    if (idx == 1) return Colors.orange.shade50;
                                    if (idx == 2) return Colors.blue.shade50;
                                    return null;
                                  }),
                                  cells: [
                                    DataCell(
                                      Row(
                                        children: [
                                          if (isTopThree)
                                            Icon(
                                              idx == 0
                                                  ? Icons.emoji_events
                                                  : Icons.star,
                                              size: 20,
                                              color: idx == 0
                                                  ? Colors.amber
                                                  : idx == 1
                                                  ? Colors.orange
                                                  : Colors.blue,
                                            ),
                                          if (isTopThree)
                                            const SizedBox(width: 8),
                                          Text(
                                            '${idx + 1}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: isTopThree
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        data['email']?.toString() ?? '',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isTopThree
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (data['answers_per_hour'] as num)
                                            .toStringAsFixed(1),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isTopThree
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${((data['answer_rate'] as num) * 100).toStringAsFixed(1)}%',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (data['knocks_per_hour'] as num)
                                            .toStringAsFixed(1),
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (data['signups'] as num)
                                            .toStringAsFixed(0),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isTopThree
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRouteMapDialog(Map<String, dynamic> row) {
    showDialog(
      context: context,
      builder: (context) => RouteMapDialog(
        userId: row['user_id'].toString(),
        userEmail: row['user_email'].toString(),
        workDateNy: row['work_date_ny'].toString(),
        startTime: _startTime,
        endTime: _endTime,
        selectedOutcomes: _selectedOutcomes,
      ),
    );
  }

  void _showInsightsModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.insights, color: Colors.blue, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Performance Insights',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Best Hours and Days Row
                        _buildTimePerformanceContent(),
                        const SizedBox(height: 24),
                        // Best ZIP Codes
                        _buildZIPPerformanceContent(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimePerformanceContent() {
    final hasHourlyData = _hourlyPerformance.any(
      (h) => (h['knocks'] as num) > 0,
    );
    final hasDailyData = _dailyPerformance.any((d) => (d['knocks'] as num) > 0);

    if (!hasHourlyData && !hasDailyData) {
      return const SizedBox.shrink();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Best Hours
        if (hasHourlyData)
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Best Hours',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _hourlyPerformance
                              .where(
                                (h) => (h['knocks'] as num) >= 5,
                              ) // Only show hours with activity
                              .map((h) {
                                final hour = h['hour'] as int;
                                final knocks = h['knocks'] as num;
                                final answers = h['answers'] as num;
                                final answerRate = h['answer_rate'] as num;
                                final hourLabel = hour == 0
                                    ? '12 AM'
                                    : hour < 12
                                    ? '$hour AM'
                                    : hour == 12
                                    ? '12 PM'
                                    : '${hour - 12} PM';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          hourLabel,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: LinearProgressIndicator(
                                          value: answerRate > 0
                                              ? answerRate.toDouble()
                                              : 0.01,
                                          backgroundColor: Colors.grey.shade200,
                                          valueColor: AlwaysStoppedAnimation(
                                            answerRate > 0.4
                                                ? Colors.green
                                                : answerRate > 0.25
                                                ? Colors.orange
                                                : Colors.red,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 100,
                                        child: Text(
                                          '${answers.toInt()}/${knocks.toInt()} (${(answerRate * 100).toStringAsFixed(0)}%)',
                                          style: const TextStyle(fontSize: 11),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (hasHourlyData && hasDailyData) const SizedBox(width: 12),

        // Best Days
        if (hasDailyData)
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Best Days',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: _dailyPerformance
                          .where(
                            (d) => (d['knocks'] as num) >= 5,
                          ) // Only show days with activity
                          .map((d) {
                            final dayName = d['day_name'] as String;
                            final knocks = d['knocks'] as num;
                            final answers = d['answers'] as num;
                            final answerRate = d['answer_rate'] as num;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      dayName,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: answerRate > 0
                                          ? answerRate.toDouble()
                                          : 0.01,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation(
                                        answerRate > 0.4
                                            ? Colors.green
                                            : answerRate > 0.25
                                            ? Colors.orange
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      '${answers.toInt()}/${knocks.toInt()} (${(answerRate * 100).toStringAsFixed(0)}%)',
                                      style: const TextStyle(fontSize: 11),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildZIPPerformanceContent() {
    if (_zipPerformance.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No ZIP code data available (minimum 20 knocks per ZIP required)',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Performing ZIP Codes',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Minimum 20 knocks per ZIP code',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 48,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 40,
            columnSpacing: 32,
            columns: const [
              DataColumn(
                label: Text(
                  'ZIP',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              DataColumn(
                label: Text(
                  'Knocks',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              DataColumn(
                label: Text(
                  'Answers',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              DataColumn(
                label: Text(
                  'Answer Rate',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
            rows: _zipPerformance.map((z) {
              final zip = z['zip'].toString();
              final knocks = z['knocks'] as num;
              final answers = z['answers'] as num;
              final answerRate = z['answer_rate'] as num;

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      zip,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      knocks.toInt().toString(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  DataCell(
                    Text(
                      answers.toInt().toString(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: answerRate > 0.4
                            ? Colors.green.shade100
                            : answerRate > 0.25
                            ? Colors.orange.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(answerRate * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: answerRate > 0.4
                              ? Colors.green.shade900
                              : answerRate > 0.25
                              ? Colors.orange.shade900
                              : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // Widget _summaryCard() {
  //   if (_rows.isEmpty) return const SizedBox.shrink();

  //   final totalHours = _rows.fold<num>(0, (s, r) => s + _toNum(r['billable_hours']));
  //   final totalBuckets =
  //       _rows.fold<num>(0, (s, r) => s + _toNum(r['valid_buckets']));
  //   final totalKnocks = _rows.fold<num>(0, (s, r) => s + _toNum(r['total_knocks']));
  //   final totalAnswers = _rows.fold<num>(0, (s, r) => s + _toNum(r['answers']));
  //   final totalSignups = _rows.fold<num>(0, (s, r) => s + _toNum(r['signed_ups']));

  //   final answerRate = totalKnocks > 0 ? (totalAnswers / totalKnocks) : 0;
  //   final conversionRate = totalAnswers > 0 ? (totalSignups / totalAnswers) : 0;
  //   final knocksPerHr = totalHours > 0 ? (totalKnocks / totalHours) : 0;

  //   return Card(
  //     elevation: 0,
  //     color: Colors.black.withOpacity(0.03),
  //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  //     child: Padding(
  //       padding: const EdgeInsets.all(12),
  //       child: Wrap(
  //         spacing: 18,
  //         runSpacing: 10,
  //         children: [
  //           _metricBlock('Total Paid Time', '${totalHours.toStringAsFixed(2)} hrs',
  //               strong: true),
  //           _metricBlock('Valid 15-min Buckets', totalBuckets.toStringAsFixed(0)),
  //           _metricBlock('Doors Knocked', totalKnocks.toStringAsFixed(0)),
  //           _metricBlock('People Answered', totalAnswers.toStringAsFixed(0)),
  //           _metricBlock('Sign-ups', totalSignups.toStringAsFixed(0), strong: true),
  //           _metricBlock('Answer Rate', '${(answerRate * 100).toStringAsFixed(1)}%'),
  //           _metricBlock('Conversion Rate',
  //               '${(conversionRate * 100).toStringAsFixed(1)}%'),
  //           _metricBlock('Knocks per Paid Hour', knocksPerHr.toStringAsFixed(2)),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = _range == null
        ? 'Pick date range'
        : '${_range!.start.month}/${_range!.start.day} - ${_range!.end.month}/${_range!.end.day}';

    final user = _supabase.auth.currentUser;
    final email = user?.email ?? '';

    final emphasisStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Go to Towns',
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TownsPage()));
            },
          ),
          IconButton(
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: _loading ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Email + explainer
            Row(
              children: [
                if (email.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.admin_panel_settings, size: 18),
                    label: Text(email),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Daily team stats. Click any row to open the 15-minute bucket drilldown for that canvasser and date.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(rangeLabel),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  icon: Icon(
                    _showFilters ? Icons.filter_list_off : Icons.filter_list,
                  ),
                  label: Text(_showFilters ? 'Hide Filters' : 'Show Filters'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _leaderboardData.isNotEmpty
                      ? _showLeaderboardModal
                      : null,
                  icon: const Icon(Icons.emoji_events),
                  label: const Text('Leaderboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showInsightsModal,
                  icon: const Icon(Icons.insights),
                  label: const Text('Insights'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ManagerShiftsPage(initialRange: _range),
                    ));
                    if (!mounted) return;
                    _fetch();
                  },
                  icon: const Icon(Icons.access_time),
                  label: const Text('Shifts'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                if (_hasActiveFilters())
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear Filters'),
                  ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_showFilters) ...[
              const SizedBox(height: 12),
              _buildFilterPanel(),
            ],
            const SizedBox(height: 12),

            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.red.withValues(alpha: 0.08),
                ),
                child: Text('Error: $_error'),
              ),

            const SizedBox(height: 12),

            // KPI Totals Section
            if (_kpiTotals.isNotEmpty || _kpiTotalsAllData.isNotEmpty) ...[
              _buildKPISection(),
              const SizedBox(height: 12),
            ],

            // Detailed Data Table Section
            Text(
              'Detailed Daily Data',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (_rows.isEmpty && !_loading)
              const SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'No results for the selected date range / filter.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Canvasser')),
                    DataColumn(label: Text('Map')),
                    DataColumn(label: Text('Paid Time (hrs)')),
                    DataColumn(label: Text('Valid Buckets')),
                    DataColumn(label: Text('Doors Knocked')),
                    DataColumn(label: Text('People Answered')),
                    DataColumn(label: Text('Sign-ups')),
                    DataColumn(label: Text('Answer Rate')),
                    DataColumn(label: Text('Conversion Rate')),
                    DataColumn(label: Text('Knocks / Paid Hr')),
                  ],
                  rows: _rows.map((r) {
                    return DataRow(
                      onSelectChanged: (_) => _openDrilldown(r),
                      cells: [
                        DataCell(Text(_num(r['work_date_ny']))),
                        DataCell(Text(_num(r['user_email']))),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.map, size: 18),
                            tooltip: 'View route map',
                            onPressed: () => _showRouteMapDialog(r),
                            color: Colors.blue.shade700,
                          ),
                        ),
                        DataCell(
                          Text(
                            _numFixed(r['billable_hours']),
                            style: emphasisStyle,
                          ),
                        ),
                        DataCell(Text(_num(r['valid_buckets']))),
                        DataCell(Text(_num(r['total_knocks']))),
                        DataCell(Text(_num(r['answers']))),
                        DataCell(
                          Text(_num(r['signed_ups']), style: emphasisStyle),
                        ),
                        DataCell(Text(_pct(r['answer_rate']))),
                        DataCell(Text(_pct(r['signup_rate']))),
                        DataCell(
                          Text(_numFixed(r['knocks_per_billable_hour'])),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
