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
          .single(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = (snapshot.data!['role'] as String?) ?? 'canvasser';

        if (role == 'manager') return const ManagerDashboardPage();
        return const CanvasserDashboardPage();
      },
    );
  }
}
