import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chs_companion/core/theme/chs_colors.dart';

class HouseDetailsPage extends StatefulWidget {
  final String address;
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
    // Explicit type so no cast is needed later
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

  Future<void> _updateStatus({
    required String fieldBool,
    required String fieldTime,
    required String fieldUser,
    required String eventType, // 'knocked' | 'answered' | 'signed_up'
  }) async {
    print("Updating house for address == '${widget.address}'");
    final user = _supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in.')),
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final now = DateTime.now().toUtc();
      final userIdentifier = user.email ?? user.id;

      // 1) Update the current snapshot on houses
      await _supabase
          .from('houses')
          .update({
            fieldBool: true,
            fieldTime: now.toIso8601String(),
            fieldUser: userIdentifier,
          })
          .eq('address', widget.address);

      // 2) Insert a row into house_events (history)
      await _supabase.from('house_events').insert({
        'address': widget.address,
        'created_at': now.toIso8601String(),
        'user_id': user.id,
        'user_email': user.email,
        'event_type': eventType,
        'notes': null, // placeholder if we add notes later

        // DUMMY geo (replace later)
        'lat': 42.2743,
        'lon': -71.8077,
        'accuracy_m': 9999,
        'geo_source': 'dummy',
        'geo_error': null,
      });

      // 3) Refresh both the house snapshot and the event list
      setState(() {
        _houseFuture = _loadHouse();
        _eventsFuture = _loadEvents();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating house: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  // Small helper to make timestamps look nice
  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();

      // Date part
      final datePart =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

      // Time part in 12-hour format with AM/PM
      final hour24 = dt.hour; // 0–23
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
          height: 260, // keep it scrollable but not huge
          child: ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              final type = (event['event_type'] as String?) ?? '';
              final email = (event['user_email'] as String?) ?? 'Unknown user';
              final createdAt =
                  _formatTimestamp(event['created_at'] as String?);

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
                leading: CircleAvatar(
                  radius: 6,
                  backgroundColor: dotColor,
                ),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.address),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _houseFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text('Error loading house: ${snapshot.error}'),
            );
          }

          final house = snapshot.data!;
          final knocked = house['knocked'] == true;
          final answered = house['answered'] == true;
          final signedUp = house['signed_up'] == true;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address header
                Text(
                  widget.address,
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildEventHistory(),
              ],
            ),
          );
        },
      ),
    );
  }
}
