import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

/// Current business profile loaded from tenant + default branch + warehouse.
class _BusinessSetup {
  const _BusinessSetup({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.warehouseId,
    required this.legalName,
    required this.tradingName,
    required this.businessType,
    required this.tinNumber,
    required this.currency,
    required this.onboardingStatus,
    required this.branchName,
    required this.branchPhone,
    required this.branchAddress,
    required this.warehouseName,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final String? warehouseId;
  final String legalName;
  final String? tradingName;
  final String? businessType;
  final String? tinNumber;
  final String currency;
  final String onboardingStatus;
  final String branchName;
  final String? branchPhone;
  final String? branchAddress;
  final String? warehouseName;
}

final businessSetupProvider = FutureProvider.autoDispose<_BusinessSetup>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id, default_branch_id, membership_status')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows as List).isEmpty) {
    throw Exception('No active tenant membership found for this user.');
  }

  final membership = membershipRows.first;
  final tenantId = membership['tenant_id'] as String;
  var branchId = membership['default_branch_id'] as String?;

  final tenantRows = await client
      .from('tenants')
      .select(
        'legal_name, trading_name, business_type, tin_number, default_currency, onboarding_status',
      )
      .eq('id', tenantId)
      .limit(1);
  if ((tenantRows as List).isEmpty) {
    throw Exception('Business record not found.');
  }
  final tenant = tenantRows.first;

  Map<String, dynamic> branch;
  if (branchId != null) {
    final rows = await client
        .from('branches')
        .select('id, name, phone, address_text')
        .eq('id', branchId)
        .limit(1);
    if ((rows as List).isEmpty) {
      throw Exception('Branch not found.');
    }
    branch = rows.first;
  } else {
    final rows = await client
        .from('branches')
        .select('id, name, phone, address_text')
        .eq('tenant_id', tenantId)
        .eq('is_default', true)
        .limit(1);
    if ((rows as List).isEmpty) {
      throw Exception('No default branch found for tenant.');
    }
    branch = rows.first;
    branchId = branch['id'] as String;
  }

  final warehouseRows = await client
      .from('warehouses')
      .select('id, name')
      .eq('tenant_id', tenantId)
      .eq('branch_id', branchId)
      .eq('is_default', true)
      .limit(1);
  final warehouse = (warehouseRows as List).isEmpty
      ? null
      : warehouseRows.first;

  return _BusinessSetup(
    tenantId: tenantId,
    userId: userId,
    branchId: branchId,
    warehouseId: warehouse?['id'] as String?,
    legalName: tenant['legal_name'] as String? ?? '',
    tradingName: tenant['trading_name'] as String?,
    businessType: tenant['business_type'] as String?,
    tinNumber: tenant['tin_number'] as String?,
    currency: tenant['default_currency'] as String? ?? 'RWF',
    onboardingStatus: tenant['onboarding_status'] as String? ?? 'not_started',
    branchName: branch['name'] as String? ?? '',
    branchPhone: branch['phone'] as String?,
    branchAddress: branch['address_text'] as String?,
    warehouseName: warehouse?['name'] as String?,
  );
});

class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _legalNameController = TextEditingController();
  final _tradingNameController = TextEditingController();
  final _businessTypeController = TextEditingController();
  final _tinController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchPhoneController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _warehouseNameController = TextEditingController();

  bool _initialized = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _legalNameController.dispose();
    _tradingNameController.dispose();
    _businessTypeController.dispose();
    _tinController.dispose();
    _branchNameController.dispose();
    _branchPhoneController.dispose();
    _branchAddressController.dispose();
    _warehouseNameController.dispose();
    super.dispose();
  }

  void _hydrate(_BusinessSetup setup) {
    if (_initialized) return;
    _legalNameController.text = setup.legalName;
    _tradingNameController.text = setup.tradingName ?? '';
    _businessTypeController.text = setup.businessType ?? '';
    _tinController.text = setup.tinNumber ?? '';
    _branchNameController.text = setup.branchName;
    _branchPhoneController.text = setup.branchPhone ?? '';
    _branchAddressController.text = setup.branchAddress ?? '';
    _warehouseNameController.text = setup.warehouseName ?? '';
    _initialized = true;
  }

  String? _trimmedOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save(_BusinessSetup setup) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final client = ref.read(supabaseClientProvider);
    try {
      await client
          .from('tenants')
          .update({
            'legal_name': _legalNameController.text.trim(),
            'trading_name': _trimmedOrNull(_tradingNameController),
            'business_type': _trimmedOrNull(_businessTypeController),
            'tin_number': _trimmedOrNull(_tinController),
            'onboarding_status': 'active',
            'updated_by': setup.userId,
          })
          .eq('id', setup.tenantId);

      await client
          .from('branches')
          .update({
            'name': _branchNameController.text.trim(),
            'phone': _trimmedOrNull(_branchPhoneController),
            'address_text': _trimmedOrNull(_branchAddressController),
            'updated_by': setup.userId,
          })
          .eq('id', setup.branchId);

      if (setup.warehouseId != null &&
          _warehouseNameController.text.trim().isNotEmpty) {
        await client
            .from('warehouses')
            .update({
              'name': _warehouseNameController.text.trim(),
              'updated_by': setup.userId,
            })
            .eq('id', setup.warehouseId!);
      }

      if (!mounted) return;
      ref.invalidate(businessSetupProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Business details saved.')));
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Could not save business details. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setupAsync = ref.watch(businessSetupProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Setup'),
        actions: const [MainMenuNavAction()],
      ),
      body: setupAsync.when(
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
                  'Could not load business details: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(businessSetupProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (setup) {
          _hydrate(setup);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (setup.onboardingStatus != 'active')
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Finish setting up your business. Confirm the '
                            'details below and save to activate.',
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Business',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _legalNameController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Legal name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter the business legal name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tradingNameController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Trading name (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _businessTypeController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Business type (optional)',
                        hintText: 'e.g. Retail shop, Restaurant',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tinController,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'TIN number (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(setup.currency),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Branch',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _branchNameController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Branch name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter the branch name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _branchPhoneController,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Branch phone (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _branchAddressController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Branch address (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Warehouse',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _warehouseNameController,
                      enabled: !_isSubmitting && setup.warehouseId != null,
                      decoration: InputDecoration(
                        labelText: setup.warehouseId == null
                            ? 'Warehouse (none found)'
                            : 'Warehouse name',
                        border: const OutlineInputBorder(),
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : () => _save(setup),
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
                            : const Text('Save business details'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
