import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

/// Signed-in user's profile loaded from app_users.
class _Profile {
  const _Profile({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.languageCode,
    required this.lastLoginAt,
  });

  final String userId;
  final String fullName;
  final String email;
  final String? phone;
  final String languageCode;
  final DateTime? lastLoginAt;
}

const _languages = <String, String>{
  'en': 'English',
  'rw': 'Kinyarwanda',
  'fr': 'French',
};

final profileProvider = FutureProvider.autoDispose<_Profile>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final rows = await client
      .from('app_users')
      .select('full_name, email, phone, preferred_language_code, last_login_at')
      .eq('id', userId)
      .limit(1);
  if ((rows as List).isEmpty) {
    throw Exception('Profile not found.');
  }
  final row = rows.first;

  return _Profile(
    userId: userId,
    fullName: row['full_name'] as String? ?? '',
    email: row['email'] as String? ?? '',
    phone: row['phone'] as String?,
    languageCode: row['preferred_language_code'] as String? ?? 'en',
    lastLoginAt: DateTime.tryParse(row['last_login_at'] as String? ?? ''),
  );
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _passwordFormKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _initialized = false;
  String _languageCode = 'en';
  bool _isSaving = false;
  bool _isChangingPassword = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _passwordError;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _hydrate(_Profile profile) {
    if (_initialized) return;
    _fullNameController.text = profile.fullName;
    _phoneController.text = profile.phone ?? '';
    _languageCode = _languages.containsKey(profile.languageCode)
        ? profile.languageCode
        : 'en';
    _initialized = true;
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _saveProfile(_Profile profile) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final client = ref.read(supabaseClientProvider);
    try {
      final phone = _phoneController.text.trim();
      await client
          .from('app_users')
          .update({
            'full_name': _fullNameController.text.trim(),
            'phone': phone.isEmpty ? null : phone,
            'preferred_language_code': _languageCode,
          })
          .eq('id', profile.userId);

      if (!mounted) return;
      ref.invalidate(profileProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not save profile. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changePassword() async {
    setState(() => _passwordError = null);
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isChangingPassword = true);
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .updateUser(UserAttributes(password: _passwordController.text));
      if (!mounted) return;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _passwordFormKey.currentState!.reset();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on AuthException catch (e) {
      if (mounted) setState(() => _passwordError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _passwordError = 'Could not update password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a new password';
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
    final profileAsync = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: const [MainMenuNavAction()],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Could not load profile: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(profileProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          _hydrate(profile);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Account',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _fullNameController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _languageCode,
                          decoration: const InputDecoration(
                            labelText: 'Preferred language',
                            border: OutlineInputBorder(),
                          ),
                          items: _languages.entries
                              .map(
                                (e) => DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(
                                  () => _languageCode = value ?? 'en',
                                ),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(profile.email),
                        ),
                        if (profile.lastLoginAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last sign-in: ${_formatDateTime(profile.lastLoginAt!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () => _saveProfile(profile),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save profile'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 40),
                  Text(
                    'Change password',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Form(
                    key: _passwordFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !_isChangingPassword,
                          decoration: InputDecoration(
                            labelText: 'New password',
                            helperText: 'At least 6 characters',
                            border: const OutlineInputBorder(),
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
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscurePassword,
                          enabled: !_isChangingPassword,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateConfirmPassword,
                        ),
                        if (_passwordError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _passwordError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _isChangingPassword
                              ? null
                              : _changePassword,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _isChangingPassword
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Update password'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
