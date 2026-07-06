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

final newSupplierTenantProvider = FutureProvider.autoDispose<_TenantContext>((
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

class NewSupplierScreen extends ConsumerStatefulWidget {
  const NewSupplierScreen({super.key});

  @override
  ConsumerState<NewSupplierScreen> createState() => _NewSupplierScreenState();
}

class _NewSupplierScreenState extends ConsumerState<NewSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save(_TenantContext tenant) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final partyCode = await client.rpc(
        'generate_party_code',
        params: {
          'target_tenant_id': tenant.tenantId,
          'party_kind': 'supplier',
        },
      ) as String;

      final insertedRows = await client.from('parties').insert({
        'tenant_id': tenant.tenantId,
        'party_code': partyCode,
        'party_name': _nameController.text.trim(),
        'party_kind': 'organization',
        'primary_phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'opening_balance': 0,
        'status': 'active',
        'is_credit_eligible': false,
        'created_by': tenant.userId,
      }).select('id').limit(1);

      final partyId = (insertedRows as List).first['id'] as String;

      final supplierTypeRows = await client
          .from('party_types')
          .select('id')
          .eq('type_code', 'supplier')
          .limit(1);
      if ((supplierTypeRows as List).isEmpty) {
        throw Exception('Supplier party type is not configured.');
      }
      final supplierTypeId = supplierTypeRows.first['id'] as String;

      await client.from('party_type_links').insert({
        'tenant_id': tenant.tenantId,
        'party_id': partyId,
        'party_type_id': supplierTypeId,
        'is_primary': true,
      });

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Could not save supplier. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter supplier name';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(newSupplierTenantProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Supplier'),
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
                Text(
                  'Could not load supplier setup: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(newSupplierTenantProvider),
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
                    controller: _nameController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Supplier name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
                          : const Text('Save supplier'),
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
