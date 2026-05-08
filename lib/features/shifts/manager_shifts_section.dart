import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerShiftsSection extends StatefulWidget {
  const ManagerShiftsSection({
    super.key,
    required this.range,
    this.selectedCanvasserEmails = const [],
  });

  final DateTimeRange range;
  final List<String> selectedCanvasserEmails;

  @override
  State<ManagerShiftsSection> createState() => _ManagerShiftsSectionState();
}

class _ManagerShiftsSectionState extends State<ManagerShiftsSection> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _rows = [];
  Set<String> _hadKnocksKeys = {}; // '$userId|$workDateNy'
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant ManagerShiftsSection old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range ||
        old.selectedCanvasserEmails.join(',') !=
            widget.selectedCanvasserEmails.join(',')) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = DateTime(
        widget.range.start.year,
        widget.range.start.month,
        widget.range.start.day,
      ).toUtc().toIso8601String();
      final endExclusive = DateTime(
        widget.range.end.year,
        widget.range.end.month,
        widget.range.end.day,
      ).add(const Duration(days: 1)).toUtc().toIso8601String();

      var query = _supabase
          .from('v_shifts_detail')
          .select()
          .gte('clock_in_at', start)
          .lt('clock_in_at', endExclusive);

      if (widget.selectedCanvasserEmails.isNotEmpty) {
        query = query.inFilter('user_email', widget.selectedCanvasserEmails);
      }

      String ymd(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final startYmd = ymd(widget.range.start);
      final endYmd = ymd(widget.range.end);

      final results = await Future.wait([
        query.order('clock_in_at', ascending: false),
        _supabase
            .from('v_user_knock_dates')
            .select('user_id, work_date_ny')
            .gte('work_date_ny', startYmd)
            .lte('work_date_ny', endYmd),
      ]);

      final shiftRows = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final knockRows = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final hadKnocks = <String>{
        for (final r in knockRows) '${r['user_id']}|${r['work_date_ny']}',
      };

      if (!mounted) return;
      setState(() {
        _rows = shiftRows;
        _hadKnocksKeys = hadKnocks;
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

  Future<void> _openEditor(Map<String, dynamic> row) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _ShiftEditorDialog(row: row),
    );
    if (updated == true) _fetch();
  }

  String _fmtDateTime(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final h12 = ((local.hour + 11) % 12) + 1;
    final mm = local.minute.toString().padLeft(2, '0');
    final am = local.hour < 12 ? 'AM' : 'PM';
    return '$m/$day $h12:$mm $am';
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.blue.shade800, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Shifts (clock in/out)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh shifts',
                  onPressed: _loading ? null : _fetch,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(fontSize: 12),
                ),
              )
            else if (_rows.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No shifts in this date range.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingRowHeight: 36,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 44,
                  columns: const [
                    DataColumn(label: Text('Canvasser')),
                    DataColumn(label: Text('Clock in')),
                    DataColumn(label: Text('Clock out')),
                    DataColumn(label: Text('Duration')),
                    DataColumn(label: Text('Edited')),
                    DataColumn(label: Text('')),
                  ],
                  rows: _rows.map((r) {
                    final clockIn = DateTime.parse(r['clock_in_at']);
                    final clockOutRaw = r['clock_out_at'];
                    final isOpen = clockOutRaw == null;
                    final clockOut = isOpen
                        ? null
                        : DateTime.parse(clockOutRaw as String);
                    final seconds = (r['duration_seconds'] ?? 0) as num;
                    final edited = r['edited_at'] != null;
                    final autoClosed = (r['auto_closed'] as bool?) ?? false;
                    final disallowed = r['disallowed_at'] != null;
                    final strike = disallowed
                        ? TextDecoration.lineThrough
                        : TextDecoration.none;
                    final mutedColor = disallowed
                        ? Colors.black45
                        : Colors.black87;
                    final userId = (r['user_id'] ?? '').toString();
                    final workDateNy = (r['work_date_ny'] ?? '').toString();
                    final knockKey = '$userId|$workDateNy';
                    final hasComparableDate =
                        userId.isNotEmpty && workDateNy.isNotEmpty;
                    final knockedThatDay =
                        !disallowed &&
                        hasComparableDate &&
                        _hadKnocksKeys.contains(knockKey);
                    return DataRow(
                      color: knockedThatDay
                          ? WidgetStateProperty.resolveWith(
                              (_) => Colors.red.shade50,
                            )
                          : null,
                      cells: [
                        DataCell(
                          Text(
                            (r['user_email'] ?? '—').toString(),
                            style: TextStyle(
                              decoration: strike,
                              color: mutedColor,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _fmtDateTime(clockIn),
                            style: TextStyle(
                              decoration: strike,
                              color: mutedColor,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isOpen ? '— (open)' : _fmtDateTime(clockOut!),
                                style: TextStyle(
                                  color: disallowed
                                      ? Colors.black45
                                      : (isOpen
                                            ? Colors.orange.shade800
                                            : Colors.black87),
                                  fontWeight: isOpen
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  decoration: strike,
                                ),
                              ),
                              if (autoClosed && !disallowed) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'Auto-closed after 9 PM (4h cap)',
                                  child: Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                              if (disallowed) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'VOIDED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            disallowed
                                ? '0h 0m'
                                : _fmtDuration(seconds.toInt()),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: mutedColor,
                              decoration: strike,
                            ),
                          ),
                        ),
                        DataCell(
                          Icon(
                            edited ? Icons.edit_note : Icons.remove,
                            color: edited
                                ? Colors.orange.shade700
                                : Colors.black26,
                            size: 18,
                          ),
                        ),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            tooltip: 'Override',
                            onPressed: () => _openEditor(r),
                          ),
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

class _ShiftEditorDialog extends StatefulWidget {
  const _ShiftEditorDialog({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_ShiftEditorDialog> createState() => _ShiftEditorDialogState();
}

class _ShiftEditorDialogState extends State<_ShiftEditorDialog> {
  late DateTime _clockIn;
  DateTime? _clockOut;
  bool _saving = false;
  bool _disallowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clockIn = DateTime.parse(widget.row['clock_in_at']).toLocal();
    final co = widget.row['clock_out_at'];
    _clockOut = co == null ? null : DateTime.parse(co as String).toLocal();
    _disallowed = widget.row['disallowed_at'] != null;
  }

  Future<void> _toggleDisallow() async {
    final next = !_disallowed;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'manager_disallow_shift',
        params: {'p_shift_id': widget.row['id'], 'p_disallow': next},
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 1),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (_clockOut != null && !_clockOut!.isAfter(_clockIn)) {
      setState(() => _error = 'Clock out must be after clock in.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'manager_update_shift',
        params: {
          'p_shift_id': widget.row['id'],
          'p_clock_in_at': _clockIn.toUtc().toIso8601String(),
          'p_clock_out_at': _clockOut?.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  String _fmt(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final h12 = ((local.hour + 11) % 12) + 1;
    final mm = local.minute.toString().padLeft(2, '0');
    final am = local.hour < 12 ? 'AM' : 'PM';
    return '${local.year}-$m-$day  $h12:$mm $am';
  }

  @override
  Widget build(BuildContext context) {
    final email = (widget.row['user_email'] ?? '').toString();
    final autoClosed = (widget.row['auto_closed'] as bool?) ?? false;
    return AlertDialog(
      title: const Text('Override shift'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (email.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  email,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (_disallowed)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block, size: 18, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This shift is disallowed and excluded from totals.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (autoClosed && !_disallowed)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto-closed after 9 PM using a 4h cap.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _FieldRow(
              label: 'Clock in',
              value: _fmt(_clockIn),
              onTap: _saving
                  ? null
                  : () async {
                      final picked = await _pick(_clockIn);
                      if (picked != null) setState(() => _clockIn = picked);
                    },
            ),
            const SizedBox(height: 8),
            _FieldRow(
              label: 'Clock out',
              value: _clockOut == null ? '— (still open)' : _fmt(_clockOut!),
              onTap: _saving
                  ? null
                  : () async {
                      final picked = await _pick(_clockOut ?? DateTime.now());
                      if (picked != null) setState(() => _clockOut = picked);
                    },
              trailing: _clockOut == null
                  ? null
                  : TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _clockOut = null),
                      child: const Text('Clear'),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _saving ? null : _toggleDisallow,
          icon: Icon(
            _disallowed ? Icons.refresh : Icons.block,
            size: 16,
            color: _disallowed ? Colors.black87 : Colors.red.shade700,
          ),
          label: Text(
            _disallowed ? 'Re-allow shift' : 'Disallow shift',
            style: TextStyle(
              color: _disallowed ? Colors.black87 : Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: _disallowed ? Colors.black26 : Colors.red.shade300,
            ),
          ),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (trailing != null) trailing!,
            const Icon(Icons.edit_calendar, size: 18, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}
