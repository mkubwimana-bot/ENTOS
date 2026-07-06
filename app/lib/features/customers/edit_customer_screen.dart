import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _EditCustomerData {
  const _EditCustomerData({
    required this.partyId,
    required this.tenantId,
    required this.userId,
    required this.partyCode,
    required this.partyName,
    required this.phone,
    required this.openingBalance,
    required this.creditLimit,
    required this.creditTermsDays,
    required this.status,
    required this.balance,
    required this.totalInvoiced,
    required this.totalPaid,
  });

  final String partyId;
  final String tenantId;
  final String userId;
  final String partyCode;
  final String partyName;
  final String? phone;
  final double openingBalance;
  final double? creditLimit;
  final int? creditTermsDays;
  final String status;
  final double balance;
  final double totalInvoiced;
  final double totalPaid;
}

final editCustomerProvider = FutureProvider.autoDispose
    .family<_EditCustomerData, String>((ref, partyId) async {
      final client = ref.read(supabaseClientProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('You must be signed in.');

      final results = await Future.wait<dynamic>([
        client
            .from('parties')
            .select(
              'id, tenant_id, party_code, party_name, primary_phone, opening_balance, '
              'customer_credit_limit, customer_credit_terms_days, status',
            )
            .eq('id', partyId)
            .isFilter('deleted_at', null)
            .limit(1),
        client
            .from('vw_customer_balances')
            .select('balance, total_invoiced, total_paid')
            .eq('party_id', partyId)
            .maybeSingle(),
      ]);

      final partyRows = results[0] as List<dynamic>;
      if (partyRows.isEmpty) throw Exception('Customer not found.');
      final party = partyRows.first as Map<String, dynamic>;

      final balanceRow = results[1] as Map<String, dynamic>?;

      return _EditCustomerData(
        partyId: party['id'] as String,
        tenantId: party['tenant_id'] as String,
        userId: userId,
        partyCode: party['party_code'] as String? ?? '',
        partyName: party['party_name'] as String? ?? '',
        phone: party['primary_phone'] as String?,
        openingBalance: (party['opening_balance'] as num?)?.toDouble() ?? 0,
        creditLimit: (party['customer_credit_limit'] as num?)?.toDouble(),
        creditTermsDays: (party['customer_credit_terms_days'] as num?)?.toInt(),
        status: party['status'] as String? ?? 'active',
        balance: (balanceRow?['balance'] as num?)?.toDouble() ?? 0,
        totalInvoiced: (balanceRow?['total_invoiced'] as num?)?.toDouble() ?? 0,
        totalPaid: (balanceRow?['total_paid'] as num?)?.toDouble() ?? 0,
      );
    });

class EditCustomerScreen extends ConsumerStatefulWidget {
  const EditCustomerScreen({required this.partyId, super.key});

  final String partyId;

  @override
  ConsumerState<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends ConsumerState<EditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _creditTermsController = TextEditingController();

  String _status = 'active';
  bool _isSubmitting = false;
  bool _initialized = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    _creditLimitController.dispose();
    _creditTermsController.dispose();
    super.dispose();
  }

  void _initFromData(_EditCustomerData data) {
    if (_initialized) return;
    _nameController.text = data.partyName;
    _phoneController.text = data.phone ?? '';
    _openingBalanceController.text = data.openingBalance.toStringAsFixed(0);
    _creditLimitController.text = data.creditLimit?.toStringAsFixed(0) ?? '';
    _creditTermsController.text = (data.creditTermsDays ?? 30).toString();
    _status = data.status;
    _initialized = true;
  }

  Future<void> _save(_EditCustomerData data) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final openingBalanceText = _openingBalanceController.text.trim();
      final creditLimitText = _creditLimitController.text.trim();
      final creditTermsText = _creditTermsController.text.trim();

      await ref
          .read(supabaseClientProvider)
          .from('parties')
          .update({
            'party_name': _nameController.text.trim(),
            'primary_phone': _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            'opening_balance': openingBalanceText.isEmpty
                ? 0
                : double.parse(openingBalanceText),
            'customer_credit_limit': creditLimitText.isEmpty
                ? null
                : double.parse(creditLimitText),
            'customer_credit_terms_days': creditTermsText.isEmpty
                ? 30
                : int.parse(creditTermsText),
            'status': _status,
            'updated_by': data.userId,
          })
          .eq('id', data.partyId);

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not save customer. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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

  String? _validateCreditTerms(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter credit terms (days)';
    final parsed = int.tryParse(text);
    if (parsed == null) return 'Enter a whole number of days';
    if (parsed < 0) return 'Days must be zero or greater';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(editCustomerProvider(widget.partyId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Customer'),
        actions: const [MainMenuNavAction()],
      ),
      body: customerAsync.when(
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
                  'Could not load customer: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(editCustomerProvider(widget.partyId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          _initFromData(data);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Balance summary',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text('Amount owed: ${formatRwf(data.balance)}'),
                            Text(
                              'Invoiced ${formatRwf(data.totalInvoiced)} · '
                              'Paid ${formatRwf(data.totalPaid)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: data.partyCode,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Customer code',
                        border: OutlineInputBorder(),
                      ),
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Opening balance (RWF)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateOptionalMoney,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _creditLimitController,
                      enabled: !_isSubmitting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Credit limit (RWF, optional)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateOptionalMoney,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _creditTermsController,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Credit terms (days)',
                        helperText: 'Used to set due date on credit sales',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateCreditTerms,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: 'inactive',
                          child: Text('Inactive'),
                        ),
                        DropdownMenuItem(
                          value: 'blocked',
                          child: Text('Blocked'),
                        ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) =>
                                setState(() => _status = value ?? 'active'),
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
                      onPressed: _isSubmitting ? null : () => _save(data),
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
                            : const Text('Save changes'),
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
