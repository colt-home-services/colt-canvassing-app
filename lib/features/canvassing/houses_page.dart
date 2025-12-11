import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chs_companion/core/theme/chs_colors.dart';

import 'house_details_page.dart';

class HousesPage extends StatefulWidget {
  final String town;
  final String street;

  const HousesPage({
    super.key,
    required this.town,
    required this.street,
  });

  @override
  State<HousesPage> createState() => _HousesPageState();
}

class _HousesPageState extends State<HousesPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _housesFuture;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _housesFuture = _loadHouses();
  }

  Future<List<Map<String, dynamic>>> _loadHouses() async {
    final data = await _supabase.rpc(
      'get_houses_for_street',
      params: {
        'town_name': widget.town,
        'street_name': widget.street,
      },
    );

    final houses = (data as List<dynamic>).cast<Map<String, dynamic>>();

    // Sort by address for a stable, predictable order
    houses.sort((a, b) {
      final aAddr = (a['address'] ?? '') as String;
      final bAddr = (b['address'] ?? '') as String;
      return aAddr.toLowerCase().compareTo(bAddr.toLowerCase());
    });

    debugPrint(
      'Loaded ${houses.length} houses for ${widget.street}, ${widget.town}',
    );

    return houses;
  }

  String _statusForHouse(Map<String, dynamic> house) {
    final knocked = house['knocked'] == true;
    final answered = house['answered'] == true;
    final signedUp = house['signed_up'] == true;

    if (signedUp) return 'Signed Up';
    if (answered) return 'Answered • Not Signed Up';
    if (knocked) return 'Knocked • No Answer';
    return 'Not Visited';
  }

  Color _statusColorForHouse(Map<String, dynamic> house) {
    final knocked = house['knocked'] == true;
    final answered = house['answered'] == true;
    final signedUp = house['signed_up'] == true;

    if (signedUp) return Colors.green;
    if (answered) return Colors.blue;
    if (knocked) return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.street}, ${widget.town}';

    return Scaffold(
      backgroundColor: kChsBackground,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.home_outlined, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search for houses',
                prefixIcon: const Icon(Icons.search, color: kChsPrimary),
                filled: true,
                fillColor: kChsCard,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: const BorderSide(
                    color: kChsPrimary,
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: const BorderSide(
                    color: Color(0xFFE0E3E7),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: const BorderSide(
                    color: kChsPrimary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Houses list
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _housesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: kChsPrimary),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading houses: ${snapshot.error}',
                      style: const TextStyle(color: kChsTextSecondary),
                    ),
                  );
                }

                var houses = snapshot.data ?? [];

                if (_search.isNotEmpty) {
                  final query = _search.toLowerCase();
                  houses = houses
                      .where((h) => ((h['address'] ?? '') as String)
                          .toLowerCase()
                          .contains(query))
                      .toList();
                }

                if (houses.isEmpty) {
                  return const Center(
                    child: Text(
                      'No houses found.',
                      style: TextStyle(color: kChsTextSecondary),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: houses.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: Color(0xFFE0E3E7),
                  ),
                  itemBuilder: (context, index) {
                    final house = houses[index];
                    final address = (house['address'] ?? '') as String;
                    final status = _statusForHouse(house);
                    final statusColor = _statusColorForHouse(house);

                    return Material(
                      color: kChsCard,
                      child: ListTile(
                        title: Text(
                          address,
                          style: const TextStyle(
                            color: kChsTextPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: kChsTextSecondary,
                        ),
                        onTap: () async {
                          // Push to house details
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => HouseDetailsPage(
                                address: address,
                                town: widget.town,
                                street: widget.street,
                              ),
                            ),
                          );

                          // Refresh houses after returning from details page
                          setState(() {
                            _housesFuture = _loadHouses();
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
