import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../canvassing/towns_page.dart';
import 'bucket_drilldown_page.dart';

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

      var rows = (await query.order('work_date_ny', ascending: false) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Apply canvasser filter
      if (_selectedCanvassers.isNotEmpty) {
        rows = rows
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
        rows = await _applyAdvancedFilters(rows);
      }

      setState(() {
        _rows = rows;
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
    final hasSelections = _selectedCanvassers.isNotEmpty || _selectedZipCodes.isNotEmpty;

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
                          onPressed: () => _addManualZip(_zipTextController.text),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            _endTime != null ? _endTime!.format(context) : 'End',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          label: const Text('Knocked', style: TextStyle(fontSize: 12)),
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
                          label: const Text('Answered', style: TextStyle(fontSize: 12)),
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
                          label: const Text('Signed Up', style: TextStyle(fontSize: 12)),
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

            // if (_rows.isNotEmpty) ...[
            //   const SizedBox(height: 10),
            //   _summaryCard(),
            // ],
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
