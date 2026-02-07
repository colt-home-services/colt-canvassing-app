import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chs_companion/core/theme/chs_colors.dart';
import 'package:chs_companion/core/utils/address_format.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;

class HouseDetailsPage extends StatefulWidget {
  final String address; // RAW DB key (keep)
  final String town;
  final String street;

  const HouseDetailsPage({
    super.key,
    required this.address,
    required this.town,
    required this.street,
  });

  @override
  State<HouseDetailsPage> createState() => _HouseDetailsPageState();
}

class _HouseDetailsPageState extends State<HouseDetailsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late Future<Map<String, dynamic>> _houseFuture;
  late Future<List<Map<String, dynamic>>> _eventsFuture;

  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _houseFuture = _loadHouse();
    _eventsFuture = _loadEvents();
  }

  Future<Map<String, dynamic>> _loadHouse() async {
    final Map<String, dynamic> response = await _supabase
        .from('houses')
        .select('*')
        .eq('address', widget.address)
        .single();

    return response;
  }

  Future<List<Map<String, dynamic>>> _loadEvents() async {
    final List<dynamic> response = await _supabase
        .from('house_events')
        .select('created_at, user_email, event_type, notes')
        .eq('address', widget.address)
        .order('created_at', ascending: false)
        .limit(20);

    return response.cast<Map<String, dynamic>>();
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusM = 6371000.0;
    double toRad(double deg) => deg * (3.141592653589793 / 180.0);

    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);

    final a =
        (Math.sin(dLat / 2) * Math.sin(dLat / 2)) +
        Math.cos(toRad(lat1)) *
            Math.cos(toRad(lat2)) *
            (Math.sin(dLon / 2) * Math.sin(dLon / 2));

    final c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  Future<
    ({
      double? lat,
      double? lon,
      double? accuracyM,
      String geoSource,
      String? geoError,
    })
  >
  _getGeoFixNonBlocking() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (
          lat: null,
          lon: null,
          accuracyM: null,
          geoSource: 'none',
          geoError: 'permission_denied',
        );
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          lat: null,
          lon: null,
          accuracyM: null,
          geoSource: 'none',
          geoError: 'location_services_disabled',
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      return (
        lat: pos.latitude,
        lon: pos.longitude,
        accuracyM: pos.accuracy,
        geoSource: 'browser_geolocation',
        geoError: null,
      );
    } catch (_) {
      return (
        lat: null,
        lon: null,
        accuracyM: null,
        geoSource: 'none',
        geoError: 'unavailable',
      );
    }
  }

  Future<void> _updateStatus({
    required String fieldBool,
    required String fieldTime,
    required String fieldUser,
    required String eventType, // 'knocked' | 'answered' | 'signed_up'
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in.')));
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final now = DateTime.now().toUtc();
      final userIdentifier = user.email ?? user.id;

      final fix = await _getGeoFixNonBlocking();

      // Block logging if location is unavailable
      if (fix.lat == null || fix.lon == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location required: Please enable location sharing to log knocks.',
            ),
          ),
        );
        return;
      }

      // 1) Update the snapshot on houses
      await _supabase
          .from('houses')
          .update({
            fieldBool: true,
            fieldTime: now.toIso8601String(),
            fieldUser: userIdentifier,
          })
          .eq('address', widget.address);

      // Fetch house coords
      final houseCoord = await _supabase
          .from('houses')
          .select('lat, lon')
          .eq('address', widget.address)
          .single();

      final houseLat = (houseCoord['lat'] as num?)?.toDouble();
      final houseLon = (houseCoord['lon'] as num?)?.toDouble();

      double? distanceM;
      String? geoError = fix.geoError;

      if (houseLat != null && houseLon != null) {
        distanceM = _haversineMeters(fix.lat!, fix.lon!, houseLat, houseLon);
      } else {
        if (geoError == null && (houseLat == null || houseLon == null)) {
          geoError = 'house_missing_coords';
        }
      }

      // 2) Insert history row
      await _supabase.from('house_events').insert({
        'address': widget.address,
        'created_at': now.toIso8601String(),
        'user_id': user.id,
        'user_email': user.email,
        'event_type': eventType,
        'notes': null,

        'lat': fix.lat,
        'lon': fix.lon,
        'accuracy_m': fix.accuracyM,
        'geo_source': fix.geoSource,
        'geo_error': geoError,
        'distance_m': distanceM,
      });

      // 3) Refresh UI
      setState(() {
        _houseFuture = _loadHouse();
        _eventsFuture = _loadEvents();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Status updated.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating house: $e')));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();

      final datePart =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

      final hour24 = dt.hour;
      final minute = dt.minute;
      final hour12 = (hour24 % 12 == 0) ? 12 : hour24 % 12;
      final ampm = hour24 >= 12 ? 'PM' : 'AM';

      final timePart =
          '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $ampm';

      return '$datePart $timePart';
    } catch (_) {
      return isoString;
    }
  }

  Widget _buildEventHistory() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Error loading history: ${snapshot.error}'),
          );
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'No activity recorded yet.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return SizedBox(
          height: 260,
          child: ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              final type = (event['event_type'] as String?) ?? '';
              final email = (event['user_email'] as String?) ?? 'Unknown user';
              final createdAt = _formatTimestamp(
                event['created_at'] as String?,
              );

              String label;
              Color dotColor;

              switch (type) {
                case 'signed_up':
                  label = 'Signed up';
                  dotColor = Colors.green;
                  break;
                case 'answered':
                  label = 'Answered';
                  dotColor = Colors.blue;
                  break;
                case 'knocked':
                  label = 'Knocked';
                  dotColor = Colors.orange;
                  break;
                default:
                  label = type;
                  dotColor = Colors.grey;
              }

              return ListTile(
                leading: CircleAvatar(radius: 6, backgroundColor: dotColor),
                title: Text(label),
                subtitle: Text('$email • $createdAt'),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _houseFuture,
      builder: (context, snapshot) {
        final loading =
            snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData;

        // While loading, show a scaffold with raw address (safe fallback)
        if (loading) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.address)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.address)),
            body: Center(child: Text('Error loading house: ${snapshot.error}')),
          );
        }

        final house = snapshot.data!;
        final zip = house['zip']?.toString();

        // ✅ Display address uses zip column (fixes missing leading zero)
        final displayAddress = addressWithZip(widget.address, zip);

        final knocked = house['knocked'] == true;
        final answered = house['answered'] == true;
        final signedUp = house['signed_up'] == true;

        return Scaffold(
          appBar: AppBar(title: Text(displayAddress)),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address header
                Text(
                  displayAddress,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${widget.street}, ${widget.town}'),

                const SizedBox(height: 16),

                // Current status snapshot
                Text('Knocked: ${knocked ? "Yes" : "No"}'),
                Text('Answered: ${answered ? "Yes" : "No"}'),
                Text('Signed up: ${signedUp ? "Yes" : "No"}'),
                const SizedBox(height: 24),

                // Buttons / updating state
                if (_isUpdating)
                  const Center(child: CircularProgressIndicator())
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: () => _updateStatus(
                          fieldBool: 'knocked',
                          fieldTime: 'knocked_time',
                          fieldUser: 'knocked_user',
                          eventType: 'knocked',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kChsPrimary.withOpacity(0.1),
                          foregroundColor: kChsPrimary,
                        ),
                        child: const Text('Mark Knocked'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _updateStatus(
                          fieldBool: 'answered',
                          fieldTime: 'answered_time',
                          fieldUser: 'answered_user',
                          eventType: 'answered',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kChsPrimary.withOpacity(0.1),
                          foregroundColor: kChsPrimary,
                        ),
                        child: const Text('Mark Answered'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _updateStatus(
                          fieldBool: 'signed_up',
                          fieldTime: 'signed_up_time',
                          fieldUser: 'signed_up_user',
                          eventType: 'signed_up',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kChsPrimary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Mark Signed Up'),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Event history section
                const Text(
                  'Recent activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildEventHistory(),
              ],
            ),
          ),
        );
      },
    );
  }
}
