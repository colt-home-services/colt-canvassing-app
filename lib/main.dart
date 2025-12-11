import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/chs_colors.dart';
import 'features/auth/sign_in_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wohhowvhvmatnraomcsd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndvaGhvd3Zodm1hdG5yYW9tY3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzc3MzM0OTEsImV4cCI6MjA1MzMwOTQ5MX0.eHyCvgBSczm1bWff4BmIyklLeYQ4ovWaoSYl0Uv9Y_8',
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
      // Single entry point – all navigation happens via Navigator.push…
      home: const SignInPage(),
    );
  }
}
