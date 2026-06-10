import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/chs_colors.dart';
import 'shift_service.dart';

class CanvasserShiftsHistoryPage extends StatefulWidget {
  const CanvasserShiftsHistoryPage({super.key});

  @override
  State<CanvasserShiftsHistoryPage> createState() =>
      _CanvasserShiftsHistoryPageState();
}

class _CanvasserShiftsHistoryPageState
    extends State<CanvasserShiftsHistoryPage> {
  final ShiftService _svc = ShiftService(Supabase.instance.client);

  List<Shift> _shifts = const [];
  bool _loading = true;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1));
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _days - 1));
      final shifts = await _svc.shiftsBetween(start, end);
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final hour12 = ((local.hour + 11) % 12) + 1;
    final am = local.hour < 12 ? 'AM' : 'PM';
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hour12:$mm $am';
  }

  String _fmtDateHeader(DateTime d) {
    final local = d.toLocal();
    final today = DateTime.now();
    final isToday = local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;
    if (isToday) return 'Today';
    if (isYesterday) return 'Yesterday';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    return '${weekdays[local.weekday - 1]}, ${months[local.month - 1]} ${local.day}';
  }

  Map<String, List<Shift>> _groupByDate(List<Shift> shifts) {
    final grouped = <String, List<Shift>>{};
    for (final s in shifts) {
      final d = s.clockInAt.toLocal();
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(s);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift history'),
        backgroundColor: kChsCard,
        foregroundColor: kChsTextPrimary,
        elevation: 0,
        actions: [
          PopupMenuButton<int>(
            initialValue: _days,
            tooltip: 'Range',
            icon: const Icon(Icons.date_range),
            onSelected: (v) {
              setState(() => _days = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 14, child: Text('Last 14 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
              PopupMenuItem(value: 90, child: Text('Last 90 days')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kChsPrimary),
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Couldn\'t load shifts: $_error',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      );
    }
    if (_shifts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No shifts in this range.',
                style: TextStyle(color: kChsTextSecondary),
              ),
            ),
          ),
        ],
      );
    }

    final grouped = _groupByDate(_shifts);
    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: dateKeys.length,
      itemBuilder: (_, i) {
        final key = dateKeys[i];
        final shifts = grouped[key]!;
        final dayTotal = shifts.fold<Duration>(
            Duration.zero, (sum, s) => sum + s.duration);
        final headerDate = shifts.first.clockInAt;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _fmtDateHeader(headerDate),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kChsTextPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_fmtDuration(dayTotal)} · ${shifts.length} shift${shifts.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kChsTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: kChsCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E8EE)),
                ),
                child: Column(
                  children: [
                    for (int j = 0; j < shifts.length; j++) ...[
                      _shiftRow(shifts[j]),
                      if (j < shifts.length - 1)
                        const Divider(height: 1, color: Color(0xFFEEF1F5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shiftRow(Shift s) {
    final isOpen = s.isOpen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            isOpen ? Icons.play_circle_fill : Icons.check_circle,
            size: 18,
            color: isOpen ? const Color(0xFF22C55E) : kChsTextSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              () {
                final base = isOpen
                    ? '${_fmtTime(s.clockInAt)} → still open'
                    : '${_fmtTime(s.clockInAt)} → ${_fmtTime(s.clockOutAt!)}';
                final signups = s.selfReportedSignups;
                return (!isOpen && signups != null)
                    ? '$base · $signups sign-ups'
                    : base;
              }(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kChsTextPrimary,
              ),
            ),
          ),
          Text(
            _fmtDuration(s.duration),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kChsTextPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
