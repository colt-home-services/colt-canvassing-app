import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../canvassing/towns_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _chsCodeController = TextEditingController();

  // UI state
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSignInTab = true; // true = Sign In, false = Sign Up
  bool _isLoading = false;

  static const Color _primaryPurple = Color(0xFF4B39EF);

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _chsCodeController.dispose();
    super.dispose();
  }

  // --------- Helpers ---------

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please enter email and password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      // navigate to TownsPage, replacing auth
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const TownsPage(),
        ),
      );
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final chsCode = _chsCodeController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        chsCode.isEmpty) {
      _showSnack('Please fill in all fields.');
      return;
    }

    if (password != confirmPassword) {
      _showSnack('Passwords do not match.');
      return;
    }

    // CHS code validation
    const String requiredChsCode = 'chs2025';
    if (chsCode != requiredChsCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid CHS code. Please check with the office.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'chs_code': chsCode,
        },
      );

      if (!mounted) return;

      _showSnack('Account created. Please sign in.');
      // Switch back to Sign In tab
      setState(() {
        _isSignInTab = true;
      });
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111315),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Colt Home Services',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // --- Tabs ---
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _isSignInTab = true),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: _isSignInTab
                                    ? Colors.black
                                    : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 180),
                              height: 4,
                              width: 130,
                              color: _isSignInTab
                                  ? _primaryPurple
                                  : Colors.transparent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 28),
                      GestureDetector(
                        onTap: () => setState(() => _isSignInTab = false),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sign Up',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: !_isSignInTab
                                    ? Colors.black
                                    : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 180),
                              height: 4,
                              width: 130,
                              color: !_isSignInTab
                                  ? _primaryPurple
                                  : Colors.transparent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  Text(
                    "Let's get started by filling out the form below.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Email
                  _buildRoundedField(
                    label: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 18),

                  // Password
                  _buildRoundedField(
                    label: 'Password',
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onToggleObscure: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),

                  if (!_isSignInTab) ...[
                    const SizedBox(height: 18),
                    _buildRoundedField(
                      label: 'Confirm Password',
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      onToggleObscure: () {
                        setState(() {
                          _obscureConfirmPassword =
                              !_obscureConfirmPassword;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildRoundedField(
                      label: 'Enter CHS Code',
                      controller: _chsCodeController,
                    ),
                  ],

                  const SizedBox(height: 26),

                  // Button
                  SizedBox(
                    width: double.infinity,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                if (_isSignInTab) {
                                  _handleSignIn();
                                } else {
                                  _handleSignUp();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryPurple,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isSignInTab ? 'Sign In' : 'Create Account',
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Reusable rounded field (radius 40)
  Widget _buildRoundedField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(40),
            borderSide: BorderSide(
              color: Colors.grey.shade300,
              width: 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(40),
            borderSide: const BorderSide(
              color: _primaryPurple,
              width: 1.6,
            ),
          ),
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: onToggleObscure,
                ),
        ),
      ),
    );
  }
}
