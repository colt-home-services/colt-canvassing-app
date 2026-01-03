import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/chs_colors.dart';
import 'features/auth/sign_in_page.dart';
import 'features/canvassing/towns_page.dart';
import 'core/routing/role_gate_page.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wohhowvhvmatnraomcsd.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndvaGhvd3Zodm1hdG5yYW9tY3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzc3MzM0OTEsImV4cCI6MjA1MzMwOTQ5MX0.eHyCvgBSczm1bWff4BmIyklLeYQ4ovWaoSYl0Uv9Y_8',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce, // ✅ recommended for Flutter Web
    ),
  );

  runApp(const CHSApp());
}

class CHSApp extends StatelessWidget {
  const CHSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Colt Home Services',
      theme: ThemeData(
        primaryColor: kChsPrimary,
        scaffoldBackgroundColor: kChsBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: kChsPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // While auth state is initializing
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.data!.session;

        if (session != null) {
          // ✅ User is logged in → route based on role
          return const RoleGatePage();
        }

        // ❌ Not logged in → Sign in
        return const SignInPage();
      },
    );
  }
}
