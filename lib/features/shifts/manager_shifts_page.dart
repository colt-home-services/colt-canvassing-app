import 'package:flutter/material.dart';

import 'manager_shifts_section.dart';

class ManagerShiftsPage extends StatefulWidget {
  const ManagerShiftsPage({super.key, this.initialRange});

  final DateTimeRange? initialRange;

  @override
  State<ManagerShiftsPage> createState() => _ManagerShiftsPageState();
}

class _ManagerShiftsPageState extends State<ManagerShiftsPage> {
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = widget.initialRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 14)), end: now);
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
      appBar: AppBar(
        title: const Text('Shifts'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(label),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: ManagerShiftsSection(range: _range),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
