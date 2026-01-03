import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO: create these pages next (we’ll add files for them)
import '../../features/stats/manager/manager_dashboard_page.dart';
import '../../features/stats/canvasser/canvasser_dashboard_page.dart';

class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      // Shouldn't happen because AuthGate checks session, but safe fallback
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: supabase
          .from('profiles')
          .select('role')
          .eq('user_id', user.id)
          .single()
          .timeout(const Duration(seconds: 8)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'RoleGate error: ${snapshot.error}\n\n'
                  'Common causes:\n'
                  '- RLS blocking profiles\n'
                  '- No profile row for this user\n'
                  '- Network / Supabase unreachable',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final role = (snapshot.data?['role'] as String?) ?? 'canvasser';
        if (role == 'manager') return const ManagerDashboardPage();
        return const CanvasserDashboardPage();
      },
    );
  }
}
