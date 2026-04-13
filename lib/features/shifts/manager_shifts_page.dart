import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'manager_shifts_section.dart';

class ManagerShiftsPage extends StatefulWidget {
  const ManagerShiftsPage({super.key, this.initialRange});

  final DateTimeRange? initialRange;

  @override
  State<ManagerShiftsPage> createState() => _ManagerShiftsPageState();
}

class _ManagerShiftsPageState extends State<ManagerShiftsPage> {
  late DateTimeRange _range;
  String? _selectedCanvasser; // null = all
  List<String> _canvassers = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = widget.initialRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 14)), end: now);
    _loadCanvassers();
  }

  Future<void> _loadCanvassers() async {
    try {
      final rows = await Supabase.instance.client
          .from('v_shifts_detail')
          .select('user_email')
          .order('user_email');
      final list = (rows as List)
          .map((e) => (e['user_email'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() => _canvassers = list);
    } catch (_) {}
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final label =
        '${_range.start.month}/${_range.start.day} - ${_range.end.month}/${_range.end.day}';
    return Scaffold(
      appBar: AppBar(title: const Text('Shifts')),
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
                  label: Text(label),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: DropdownButtonFormField<String?>(
                    value: _selectedCanvasser,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Canvasser',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All canvassers'),
                      ),
                      ..._canvassers.map((e) =>
                          DropdownMenuItem<String?>(value: e, child: Text(e))),
                    ],
                    onChanged: (v) => setState(() => _selectedCanvasser = v),
                  ),
                ),
                if (_selectedCanvasser != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedCanvasser = null),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: ManagerShiftsSection(
                  range: _range,
                  selectedCanvasserEmails: _selectedCanvasser == null
                      ? const []
                      : [_selectedCanvasser!],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
