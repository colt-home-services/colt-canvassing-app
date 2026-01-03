import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../canvassing/towns_page.dart';

class CanvasserDashboardPage extends StatefulWidget {
  const CanvasserDashboardPage({super.key});

  @override
  State<CanvasserDashboardPage> createState() => _CanvasserDashboardPageState();
}

class _CanvasserDashboardPageState extends State<CanvasserDashboardPage> {
  final _supabase = Supabase.instance.client;

  DateTimeRange? _range;

  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: now.subtract(const Duration(days: 14)), end: now);
    _fetch();
  }

  String _fmtYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Not signed in.';
        _rows = [];
        _loading = false;
      });
      return;
    }
    if (_range == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final startStr = _fmtYmd(_range!.start);
      final endStr = _fmtYmd(_range!.end);

      // ✅ Filter by the logged-in user_id explicitly (do NOT rely on view/RLS behavior)
      final payrollRaw = await _supabase
          .from('v_payroll_daily')
          .select()
          .match({'user_id': user.id})
          .gte('work_date_ny', startStr)
          .lte('work_date_ny', endStr)
          .order('work_date_ny', ascending: false);

      final perfRaw = await _supabase
          .from('v_performance_daily')
          .select()
          .match({'user_id': user.id})
          .gte('work_date_ny', startStr)
          .lte('work_date_ny', endStr)
          .order('work_date_ny', ascending: false);

      final payroll = (payrollRaw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final perf = (perfRaw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final perfByDate = <String, Map<String, dynamic>>{};
      for (final r in perf) {
        final d = (r['work_date_ny'] ?? '').toString();
        if (d.isNotEmpty) perfByDate[d] = r;
      }

      final joined = <Map<String, dynamic>>[];
      for (final p in payroll) {
        final d = (p['work_date_ny'] ?? '').toString();
        final pr = perfByDate[d];

        joined.add({
          'work_date_ny': d,
          'billable_hours': p['billable_hours'],
          'valid_buckets': p['valid_buckets'],
          'total_knocks': p['total_knocks'],
          'answers': pr?['answers'] ?? 0,
          'signed_ups': pr?['signed_ups'] ?? 0,
          'answer_rate': pr?['answer_rate'] ?? 0,
          'signup_rate': pr?['signup_rate'] ?? 0,
        });
      }

      setState(() {
        _rows = joined;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final rangeLabel = _range == null
        ? 'Pick date range'
        : '${_range!.start.month}/${_range!.start.day} - ${_range!.end.month}/${_range!.end.day}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Stats'),
        actions: [
          IconButton(
            tooltip: 'Go to Towns',
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TownsPage()),
              );
            },
          ),
          IconButton(
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(rangeLabel),
                ),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.red.withOpacity(0.08),
                ),
                child: Text('Error: $_error'),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _rows.isEmpty && !_loading
                  ? const Center(child: Text('No rows for selected range.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Billable hrs')),
                          DataColumn(label: Text('Valid buckets')),
                          DataColumn(label: Text('Knocks')),
                          DataColumn(label: Text('Answers')),
                          DataColumn(label: Text('Signups')),
                          DataColumn(label: Text('Answer %')),
                          DataColumn(label: Text('Signup/Answer %')),
                        ],
                        rows: _rows.map((r) {
                          return DataRow(
                            cells: [
                              DataCell(Text(_num(r['work_date_ny']))),
                              DataCell(Text(_numFixed(r['billable_hours']))),
                              DataCell(Text(_num(r['valid_buckets']))),
                              DataCell(Text(_num(r['total_knocks']))),
                              DataCell(Text(_num(r['answers']))),
                              DataCell(Text(_num(r['signed_ups']))),
                              DataCell(Text(_pct(r['answer_rate']))),
                              DataCell(Text(_pct(r['signup_rate']))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
