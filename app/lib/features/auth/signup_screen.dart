import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';

/// Email/password sign-up screen backed by Supabase Auth.
///
/// Two outcomes are possible depending on the Supabase project's auth settings:
///  - If email confirmation is OFF, `signUp` returns a session and the AuthGate
///    swaps to Home automatically (same as login).
///  - If email confirmation is ON (Supabase default), no session is returned;
///    the user must click the confirmation link in their inbox first. We show a
///    "check your email" message in that case.
///
/// NOTE: creating an auth user does NOT create the app's tenant/app_users rows.
/// A new sign-up can authenticate but will have no tenant yet, so RLS blocks
/// all business data until onboarding/tenant provisioning exists (future work).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _confirmationSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final response = await ref
          .read(supabaseClientProvider)
          .auth
          .signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      // A null session means email confirmation is required before sign-in.
      if (response.session == null && mounted) {
        setState(() => _confirmationSent = true);
      }
      // If a session exists, the auth-state stream fires and the AuthGate
      // replaces this screen with Home automatically.
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not create your account. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 6) return 'Use at least 6 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Re-enter your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _confirmationSent
                  ? _ConfirmationMessage(email: _emailController.text.trim())
                  : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'SME-OS',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a new account',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enabled: !_isSubmitting,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            enabled: !_isSubmitting,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              helperText: 'At least 6 characters',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscurePassword,
                            enabled: !_isSubmitting,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _signUp(),
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: _validateConfirmPassword,
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _signUp,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Create account'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('I already have an account'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmationMessage extends StatelessWidget {
  const _ConfirmationMessage({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64),
        const SizedBox(height: 16),
        Text(
          'Confirm your email',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a confirmation link to $email. '
          'Open it to activate your account, then sign in.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Text('Back to sign in'),
          ),
        ),
      ],
    );
  }
}
