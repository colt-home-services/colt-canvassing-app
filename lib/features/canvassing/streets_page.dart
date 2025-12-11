import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chs_companion/core/theme/chs_colors.dart';
import 'houses_page.dart';

class StreetsPage extends StatefulWidget {
  final String town;

  const StreetsPage({super.key, required this.town});

  @override
  State<StreetsPage> createState() => _StreetsPageState();
}

class _StreetsPageState extends State<StreetsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late Future<List<String>> _streetsFuture;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _streetsFuture = _loadStreets();
  }

  Future<List<String>> _loadStreets() async {
    const int pageSize = 500; // must be <= 1000 for Supabase
    int offset = 0;
    final List<String> allStreets = [];

    while (true) {
      final data = await _supabase.rpc(
        'get_streets_for_town',
        params: {
          'town_name': widget.town,
          'page_limit': pageSize,
          'page_offset': offset,
        },
      );

      final batch = (data as List<dynamic>)
          .map((e) => (e as String).trim())
          .where((s) => s.isNotEmpty)
          .toList();

      allStreets.addAll(batch);

      // If we got less than a full page, we're done
      if (batch.length < pageSize) {
        break;
      }

      offset += pageSize;
    }

    // Remove any duplicates across pages (just in case) and sort nicely
    final streets = allStreets.toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    debugPrint(
      'Loaded ${streets.length} distinct streets for town ${widget.town}',
    );

    return streets;
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kChsBackground,
      appBar: AppBar(
        title: Text(
          'Streets in ${widget.town}',
          style: const TextStyle(
            fontSize: 20,
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
            child: Icon(Icons.search, color: Colors.white),
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
                hintText: 'Search for streets',
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

          // Streets list
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _streetsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: kChsPrimary),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading streets: ${snapshot.error}',
                      style: const TextStyle(color: kChsTextSecondary),
                    ),
                  );
                }

                var streets = snapshot.data ?? [];
                if (_search.isNotEmpty) {
                  final query = _search.toLowerCase();
                  streets = streets
                      .where((s) => s.toLowerCase().contains(query))
                      .toList();
                }

                if (streets.isEmpty) {
                  return const Center(
                    child: Text(
                      'No street results found.',
                      style: TextStyle(color: kChsTextSecondary),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: streets.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: Color(0xFFE0E3E7),
                  ),
                  itemBuilder: (context, index) {
                    final street = streets[index];
                    return Material(
                      color: kChsCard,
                      child: ListTile(
                        title: Text(
                          street,
                          style: const TextStyle(
                            color: kChsTextPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: kChsTextSecondary,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => HousesPage(
                                town: widget.town,
                                street: street,
                              ),
                            ),
                          );
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

