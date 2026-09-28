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
          return _NamePromptGate(
            child: FutureBuilder<SavedCanvassingLocation?>(
              future: CanvassingLocationCache.read(),
              builder: (context, locationSnapshot) {
                if (locationSnapshot.connectionState ==
                    ConnectionState.waiting) {
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
                if (location != null &&
                    location.hasTown &&
                    location.hasStreet) {
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
            ),
          );
        }

        // ❌ Not logged in → Sign in
        return const SignInPage();
      },
    );
  }
}

class _NamePromptGate extends StatefulWidget {
  const _NamePromptGate({required this.child});

  final Widget child;

  @override
  State<_NamePromptGate> createState() => _NamePromptGateState();
}

class _NamePromptGateState extends State<_NamePromptGate> {
  bool _checked = false;
  bool _prompting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checked) {
      _checked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkName());
    }
  }

  Future<void> _checkName() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || !mounted) return;
    try {
      final profile = await client
          .from('profiles')
          .select('first_name, last_name')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted || profile == null) return;
      final first = (profile['first_name'] ?? '').toString().trim();
      final last = (profile['last_name'] ?? '').toString().trim();
      if (first.isNotEmpty && last.isNotEmpty) return;
      await _promptForName(client);
    } catch (error) {
      debugPrint('Could not check profile name: $error');
    }
  }

  Future<void> _promptForName(SupabaseClient client) async {
    if (_prompting || !mounted) return;
    _prompting = true;
    final first = TextEditingController();
    final last = TextEditingController();
    String? error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add your name'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter your first and last name to finish setting up your account.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: first,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                  TextField(
                    controller: last,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  final firstName = first.text.trim();
                  final lastName = last.text.trim();
                  if (firstName.isEmpty || lastName.isEmpty) {
                    setDialogState(
                      () => error = 'Enter both names to continue.',
                    );
                    return;
                  }
                  try {
                    await client.rpc(
                      'save_my_name',
                      params: {
                        'p_first_name': firstName,
                        'p_last_name': lastName,
                      },
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (_) {
                    setDialogState(
                      () =>
                          error = 'Could not save your name. Please try again.',
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      first.dispose();
      last.dispose();
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
