import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'streets_page.dart';

class TownsPage extends StatefulWidget {
  const TownsPage({super.key});

  @override
  State<TownsPage> createState() => _TownsPageState();
}

class _TownsPageState extends State<TownsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<String> _allTowns = [];
  List<String> _filteredTowns = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTowns();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTowns() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _supabase.rpc('get_towns');

      // data will be a List<dynamic> of towns (text)
      final towns = (data as List<dynamic>)
          .map((e) => (e as String).trim())
          .where((t) => t.isNotEmpty)
          .toList();

      debugPrint('Loaded ${towns.length} distinct towns via get_towns()');

      setState(() {
        _allTowns = towns;
        _filteredTowns = towns;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }


  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredTowns = List.from(_allTowns);
      } else {
        _filteredTowns = _allTowns
            .where((t) => t.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryPurple = Color(0xFF4B39EF);
    const background = Color(0xFFF1F4F8); // from your theme screenshot

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Towns',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTowns,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: background,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search for towns',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1.2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                    color: primaryPurple,
                    width: 1.6,
                  ),
                ),
              ),
            ),
          ),

          // Content
          Expanded(
            child: Container(
              color: background,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          'Error loading towns:\n$_errorMessage',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_filteredTowns.isEmpty) {
      return const Center(
        child: Text('No towns found.'),
      );
    }

    return ListView.separated(
      itemCount: _filteredTowns.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final town = _filteredTowns[index];
        return ListTile(
          tileColor: Colors.white,
          title: Text(
            town,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.black54),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StreetsPage(town: town),
              ),
            );
          },
        );
      },
    );
  }
}
