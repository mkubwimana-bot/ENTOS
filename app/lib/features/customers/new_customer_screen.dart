import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _TenantContext {
  const _TenantContext({required this.tenantId, required this.userId});

  final String tenantId;
  final String userId;
}

final newCustomerTenantProvider = FutureProvider.autoDispose<_TenantContext>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id, membership_status')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows as List).isEmpty) {
    throw Exception('No active tenant membership found for this user.');
  }

  final tenantId = membershipRows.first['tenant_id'] as String;
  return _TenantContext(tenantId: tenantId, userId: userId);
});

class NewCustomerScreen extends ConsumerStatefulWidget {
  const NewCustomerScreen({super.key});

  @override
  ConsumerState<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends ConsumerState<NewCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _creditLimitController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _save(_TenantContext tenant) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final openingBalanceText = _openingBalanceController.text.trim();
      final creditLimitText = _creditLimitController.text.trim();

      final insertedRows = await ref.read(supabaseClientProvider).from('parties').insert({
        'tenant_id': tenant.tenantId,
        'party_code': _codeController.text.trim(),
        'party_name': _nameController.text.trim(),
        'party_kind': 'individual',
        'primary_phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'opening_balance': openingBalanceText.isEmpty ? 0 : double.parse(openingBalanceText),
        'customer_credit_limit': creditLimitText.isEmpty ? null : double.parse(creditLimitText),
        'status': 'active',
        'is_credit_eligible': true,
        'created_by': tenant.userId,
      }).select('id').limit(1);

      final partyId = (insertedRows as List).first['id'] as String;

      final customerTypeRows = await ref
          .read(supabaseClientProvider)
          .from('party_types')
          .select('id')
          .eq('type_code', 'customer')
          .limit(1);
      final customerTypeId = (customerTypeRows as List).first['id'] as String;

      await ref.read(supabaseClientProvider).from('party_type_links').insert({
        'tenant_id': tenant.tenantId,
        'party_id': partyId,
        'party_type_id': customerTypeId,
        'is_primary': true,
      });

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not save customer. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateCode(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Enter customer code';
    if (code.length < 3) return 'Use at least 3 characters';
    return null;
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter customer name';
    return null;
  }

  String? _validateOptionalMoney(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Amount must be zero or greater';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(newCustomerTenantProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Customer'),
        actions: const [MainMenuNavAction()],
      ),
      body: tenantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load customer setup: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(newCustomerTenantProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (tenant) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _codeController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Customer code',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateCode,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Customer name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _openingBalanceController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Opening balance (RWF, optional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateOptionalMoney,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _creditLimitController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Credit limit (RWF, optional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateOptionalMoney,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSubmitting ? null : () => _save(tenant),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save customer'),
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
}
