import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteMapDialog extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String workDateNy;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final Set<String> selectedOutcomes;

  const RouteMapDialog({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.workDateNy,
    this.startTime,
    this.endTime,
    required this.selectedOutcomes,
  });

  @override
  State<RouteMapDialog> createState() => _RouteMapDialogState();
}

class _RouteMapDialogState extends State<RouteMapDialog> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _fetchRouteData();
  }

  Future<void> _fetchRouteData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Query house_events for GPS data
      final result = await _supabase
          .from('house_events')
          .select('lat, lon, created_at, event_type')
          .eq('user_id', widget.userId)
          .gte('created_at', '${widget.workDateNy} 00:00:00')
          .lte('created_at', '${widget.workDateNy} 23:59:59')
          .order('created_at', ascending: true) as List;

      var events = result
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Filter out events without GPS data
      events = events.where((e) {
        return e['lat'] != null && e['lon'] != null;
      }).toList();

      // Apply outcome filter if needed
      if (widget.selectedOutcomes.isNotEmpty &&
          widget.selectedOutcomes.length < 3) {
        events = events.where((e) {
          return widget.selectedOutcomes.contains(e['event_type']);
        }).toList();
      }

      // Apply time of day filter if specified
      if (widget.startTime != null || widget.endTime != null) {
        events = events.where((e) {
          try {
            final dt = DateTime.parse(e['created_at'].toString()).toLocal();
            final eventMinutes = dt.hour * 60 + dt.minute;

            final startMinutes = widget.startTime != null
                ? widget.startTime!.hour * 60 + widget.startTime!.minute
                : 0;
            final endMinutes = widget.endTime != null
                ? widget.endTime!.hour * 60 + widget.endTime!.minute
                : 24 * 60;

            return eventMinutes >= startMinutes && eventMinutes <= endMinutes;
          } catch (_) {
            return false;
          }
        }).toList();
      }

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

  LatLng _getMapCenter() {
    if (_events.isEmpty) {
      return LatLng(40.7128, -74.0060); // Default to NYC
    }

    final avgLat = _events
            .map((e) => (e['lat'] as num).toDouble())
            .reduce((a, b) => a + b) /
        _events.length;
    final avgLon = _events
            .map((e) => (e['lon'] as num).toDouble())
            .reduce((a, b) => a + b) /
        _events.length;

    return LatLng(avgLat, avgLon);
  }

  List<Marker> _buildMarkers() {
    return _events.asMap().entries.map((entry) {
      final index = entry.key;
      final event = entry.value;
      final lat = (event['lat'] as num).toDouble();
      final lon = (event['lon'] as num).toDouble();

      return Marker(
        point: LatLng(lat, lon),
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<LatLng> _getPolylinePoints() {
    return _events.map((e) {
      final lat = (e['lat'] as num).toDouble();
      final lon = (e['lon'] as num).toDouble();
      return LatLng(lat, lon);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.map, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route Map',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${widget.userEmail} • ${widget.workDateNy}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Map content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Error: $_error',
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _events.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.location_off,
                                      size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No location data for this day',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Events may have been logged without location services',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : FlutterMap(
                              options: MapOptions(
                                initialCenter: _getMapCenter(),
                                initialZoom: 14.0,
                                minZoom: 10,
                                maxZoom: 18,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.coltservices.chs_companion',
                                ),
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _getPolylinePoints(),
                                      strokeWidth: 2.0,
                                      color: Colors.blue,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: _buildMarkers(),
                                ),
                              ],
                            ),
            ),

            // Footer with event count
            if (!_loading && _events.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pin_drop, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      '${_events.length} location${_events.length != 1 ? 's' : ''} recorded',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
