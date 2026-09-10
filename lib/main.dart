import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/data/canvassing_location_cache.dart';
import 'core/data/towns_cache.dart';
import 'core/theme/chs_colors.dart';
import 'features/auth/sign_in_page.dart';
import 'features/auth/update_password_page.dart';
import 'features/canvassing/house_details_page.dart';
import 'features/canvassing/houses_page.dart';
import 'features/canvassing/streets_page.dart';
import 'features/canvassing/towns_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wohhowvhvmatnraomcsd.supabase.co',
    anonKey: 'sb_publishable_jkXpbnJLw8nsWchfqfPgXw_8b85FH5l',
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

        final authState = snapshot.data!;
        final session = authState.session;

        // A password-reset link signs the user in with a real session, so
        // this check MUST come before the session check below — otherwise
        // they land in the app with their old password still active.
        if (authState.event == AuthChangeEvent.passwordRecovery) {
          return const UpdatePasswordPage();
        }

        if (session != null) {
          // Warm the towns cache so the first TownsPage open is instant.
          unawaited(TownsCache.refresh(supabase).catchError((_) => <String>[]));
          return FutureBuilder<SavedCanvassingLocation?>(
            future: CanvassingLocationCache.read(),
            builder: (context, locationSnapshot) {
              if (locationSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final location = locationSnapshot.data;
              if (location != null &&
                  location.hasTown &&
                  location.hasStreet &&
                  location.hasAddress) {
                return HouseDetailsPage(
                  town: location.town!,
                  street: location.street!,
                  address: location.address!,
                );
              }
              if (location != null && location.hasTown && location.hasStreet) {
                return HousesPage(
                  town: location.town!,
                  street: location.street!,
                );
              }
              if (location != null && location.hasTown) {
                return StreetsPage(town: location.town!);
              }
              return const TownsPage();
            },
          );
        }

        // ❌ Not logged in → Sign in
        return const SignInPage();
      },
    );
  }
}
