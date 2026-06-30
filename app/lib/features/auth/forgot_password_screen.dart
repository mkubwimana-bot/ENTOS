import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_error_message.dart';
import '../../core/config/app_config.dart';
import '../../core/supabase/supabase_providers.dart';

/// Requests a password-reset email via Supabase Auth.
///
/// The email contains a deep link that opens this app on the user's phone.
/// Supabase emits [AuthChangeEvent.passwordRecovery] and [AuthGate] shows
/// [ResetPasswordScreen] so the user can set a new password in-app.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .resetPasswordForEmail(
            _emailController.text.trim(),
            redirectTo: AppConfig.authRedirectUrl,
          );
      if (mounted) setState(() => _emailSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = authErrorMessage(e));
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not send the reset email. Check your connection and try again.';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _emailSent
                  ? _ResetSentMessage(email: _emailController.text.trim())
                  : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Forgot your password?',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter your email and we will send you a link to reset it.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'dev@smeos.test cannot receive reset emails. '
                            'Use a real address for this test.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enabled: !_isSubmitting,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _sendResetEmail(),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: _validateEmail,
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
                            onPressed: _isSubmitting ? null : _sendResetEmail,
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
                                  : const Text('Send reset link'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Back to sign in'),
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

class _ResetSentMessage extends StatelessWidget {
  const _ResetSentMessage({required this.email});

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
          'Check your email',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'If an account exists for $email, a password-reset link is on its way. '
          'Open the link on this device to set a new password in the app.',
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
