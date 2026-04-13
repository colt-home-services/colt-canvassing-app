import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../canvassing/towns_page.dart';

class BucketDrilldownPage extends StatefulWidget {
  final String userId; // uuid as string
  final String userEmail;
  final String workDateNy; // 'YYYY-MM-DD'

  /// Optional time window (e.g. a specific shift) — if provided, only events
  /// within [windowStart, windowEnd] are shown.
  final DateTime? windowStart;
  final DateTime? windowEnd;

  const BucketDrilldownPage({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.workDateNy,
    this.windowStart,
    this.windowEnd,
  });

  @override
  State<BucketDrilldownPage> createState() => _BucketDrilldownPageState();
}

class _BucketDrilldownPageState extends State<BucketDrilldownPage> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_Event> _events = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      DateTime start;
      DateTime endExclusive;
      if (widget.windowStart != null && widget.windowEnd != null) {
        start = widget.windowStart!;
        endExclusive = widget.windowEnd!;
      } else {
        final parts = widget.workDateNy.split('-').map(int.parse).toList();
        start = DateTime(parts[0], parts[1], parts[2]);
        endExclusive = start.add(const Duration(days: 1));
      }

      final raw = await _supabase
          .from('house_events')
          .select('id, address, created_at, event_type, lat, lon')
          .match({'user_id': widget.userId})
          .gte('created_at', start.toUtc().toIso8601String())
          .lt('created_at', endExclusive.toUtc().toIso8601String())
          .order('created_at', ascending: true);

      final events = (raw as List)
          .map((e) => _Event.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Group events into 15-minute buckets keyed by the bucket's start time (local).
  List<_Bucket> _buckets() {
    final map = <DateTime, List<_Event>>{};
    for (final e in _events) {
      final local = e.createdAt.toLocal();
      final bucketMinute = (local.minute ~/ 15) * 15;
      final key = DateTime(
        local.year,
        local.month,
        local.day,
        local.hour,
        bucketMinute,
      );
      map.putIfAbsent(key, () => []).add(e);
    }
    final out = map.entries
        .map((e) => _Bucket(start: e.key, events: e.value))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  String _fmtTime(DateTime d) {
    final h12 = ((d.hour + 11) % 12) + 1;
    final mm = d.minute.toString().padLeft(2, '0');
    final am = d.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $am';
  }

  String _bucketRangeLabel(DateTime start) {
    final end = start.add(const Duration(minutes: 15));
    return '${_fmtTime(start)} – ${_fmtTime(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.windowStart != null && widget.windowEnd != null
        ? '${widget.userEmail} • shift ${_fmtTime(widget.windowStart!.toLocal())}–${_fmtTime(widget.windowEnd!.toLocal())}'
        : '${widget.userEmail} • ${widget.workDateNy}';
    final buckets = _buckets();
    final totalKnocks =
        _events.where((e) => e.eventType == 'knocked').length;
    final totalAnswers =
        _events.where((e) => e.eventType == 'answered').length;
    final totalSignups =
        _events.where((e) => e.eventType == 'signed_up').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Houses per 15 min'),
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
            Text(
              subtitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _SummaryRow(
              knocks: totalKnocks,
              answers: totalAnswers,
              signups: totalSignups,
              bucketCount: buckets.length,
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
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
            if (!_loading && _error == null && buckets.isEmpty)
              const Expanded(
                child: Center(child: Text('No houses logged in this window.')),
              ),
            if (!_loading && _error == null && buckets.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: buckets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final b = buckets[i];
                    final knocks =
                        b.events.where((e) => e.eventType == 'knocked').length;
                    final answers = b.events
                        .where((e) => e.eventType == 'answered')
                        .length;
                    final signups = b.events
                        .where((e) => e.eventType == 'signed_up')
                        .length;
                    return Card(
                      elevation: 0,
                      color: Colors.blue.shade50,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        tilePadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        title: Text(
                          _bucketRangeLabel(b.start),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Wrap(
                            spacing: 10,
                            children: [
                              _Chip(label: '$knocks knocks', color: Colors.black87),
                              if (answers > 0)
                                _Chip(
                                    label: '$answers answered',
                                    color: Colors.blue.shade800),
                              if (signups > 0)
                                _Chip(
                                    label: '$signups signed up',
                                    color: Colors.green.shade800),
                            ],
                          ),
                        ),
                        children: b.events
                            .map((e) => ListTile(
                                  dense: true,
                                  leading: _eventIcon(e.eventType),
                                  title: Text(
                                    e.address,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    '${_fmtTime(e.createdAt.toLocal())} • ${e.eventType}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ))
                            .toList(),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _eventIcon(String type) {
    switch (type) {
      case 'signed_up':
        return Icon(Icons.check_circle, color: Colors.green.shade700);
      case 'answered':
        return Icon(Icons.door_front_door, color: Colors.blue.shade700);
      case 'knocked':
      default:
        return Icon(Icons.pan_tool_alt_outlined, color: Colors.black54);
    }
  }
}

class _Event {
  final int id;
  final String address;
  final DateTime createdAt;
  final String eventType;
  final double? lat;
  final double? lon;

  _Event({
    required this.id,
    required this.address,
    required this.createdAt,
    required this.eventType,
    this.lat,
    this.lon,
  });

  factory _Event.fromMap(Map<String, dynamic> m) => _Event(
        id: (m['id'] as num).toInt(),
        address: (m['address'] ?? '').toString(),
        createdAt: DateTime.parse(m['created_at'] as String),
        eventType: (m['event_type'] ?? '').toString(),
        lat: m['lat'] == null ? null : (m['lat'] as num).toDouble(),
        lon: m['lon'] == null ? null : (m['lon'] as num).toDouble(),
      );
}

class _Bucket {
  final DateTime start;
  final List<_Event> events;
  _Bucket({required this.start, required this.events});
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.knocks,
    required this.answers,
    required this.signups,
    required this.bucketCount,
  });
  final int knocks;
  final int answers;
  final int signups;
  final int bucketCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        _Chip(label: '$knocks knocks', color: Colors.black87, strong: true),
        _Chip(label: '$answers answered', color: Colors.blue.shade800),
        _Chip(label: '$signups signed up', color: Colors.green.shade800),
        _Chip(
          label:
              '$bucketCount bucket${bucketCount == 1 ? '' : 's'}',
          color: Colors.black54,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.strong = false});
  final String label;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}
