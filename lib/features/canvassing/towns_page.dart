import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/routing/role_gate_page.dart';
import '../../core/data/towns_cache.dart';


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

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _bootstrap();

    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 120), _applyFilter);
    });
  }

  Future<void> _bootstrap() async {
    final cached = await TownsCache.read();
    if (cached != null && mounted) {
      setState(() {
        _allTowns = cached;
        _filteredTowns = cached;
        _isLoading = false;
      });
    }
    _refreshInBackground();
  }

  Future<void> _refreshInBackground() async {
    try {
      final towns = await TownsCache.refresh(_supabase);
      if (!mounted) return;
      if (_listsEqual(towns, _allTowns)) return;
      setState(() {
        _allTowns = towns;
        _errorMessage = null;
        _isLoading = false;
        _applyFilterSync();
      });
    } catch (e) {
      if (!mounted) return;
      if (_allTowns.isNotEmpty) return; // keep showing cached list silently
      setState(() {
        _errorMessage = e is PostgrestException && e.code == '57014'
            ? 'Loading towns took too long. Tap Retry.'
            : e.toString();
        _isLoading = false;
      });
    }
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _applyFilterSync() {
    final q = _searchController.text.trim().toUpperCase();
    _filteredTowns = q.isEmpty
        ? List.from(_allTowns)
        : _allTowns.where((t) => t.startsWith(q)).toList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllTowns() async {
    if (_allTowns.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() => _errorMessage = null);
    }
    await _refreshInBackground();
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toUpperCase();

    setState(() {
      if (q.isEmpty) {
        _filteredTowns = List.from(_allTowns);
        return;
      }

      // Prefix feels best here and is fast
      _filteredTowns = _allTowns.where((t) => t.startsWith(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryPurple = Color(0xFF4B39EF);
    const background = Color(0xFFF1F4F8);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Towns', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loadAllTowns,
          ),
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoleGatePage()),
              );
            },
          ),
          TextButton(
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.signOut();
                // AuthGate will automatically redirect to SignInPage
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Logout failed: $e')),
                );
              }
            },
            child: const Text(
              'Log out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: background,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search towns',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: primaryPurple, width: 1.6),
                ),
              ),
            ),
          ),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Error loading towns:\n$_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadAllTowns,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredTowns.isEmpty) {
      return const Center(child: Text('No towns found.'));
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
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.black54),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StreetsPage(town: town)),
            );
          },
        );
      },
    );
  }
}
