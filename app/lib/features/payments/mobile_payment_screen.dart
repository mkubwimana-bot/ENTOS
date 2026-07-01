import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _MobilePaymentContext {
  const _MobilePaymentContext({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.customers,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final List<_CustomerOption> customers;
}

class _CustomerOption {
  const _CustomerOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _OpenInvoice {
  const _OpenInvoice({
    required this.id,
    required this.invoiceDate,
    required this.balanceAmount,
  });

  final String id;
  final String invoiceDate;
  final double balanceAmount;
}

const _paymentMethods = <String, String>{
  'cash': 'Cash',
  'momo': 'Mobile Money',
  'airtel': 'Airtel Money',
  'bank': 'Bank transfer',
  'card': 'Card',
  'other': 'Other',
};

final mobilePaymentContextProvider =
    FutureProvider.autoDispose<_MobilePaymentContext>((ref) async {
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

  if (branchId == null) {
    final branchRows = await client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('is_default', true)
        .limit(1);
    if ((branchRows as List).isEmpty) {
      throw Exception('No default branch found for tenant.');
    }
    branchId = branchRows.first['id'] as String;
  }

  final customerRows = await client
      .from('parties')
      .select('id, party_name')
      .eq('status', 'active')
      .isFilter('deleted_at', null)
      .order('party_name');

  final customers = (customerRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return _CustomerOption(
      id: map['id'] as String,
      name: map['party_name'] as String? ?? 'Unnamed customer',
    );
  }).toList();

  return _MobilePaymentContext(
    tenantId: tenantId,
    userId: userId,
    branchId: branchId,
    customers: customers,
  );
});

class MobilePaymentScreen extends ConsumerStatefulWidget {
  const MobilePaymentScreen({super.key});

  @override
  ConsumerState<MobilePaymentScreen> createState() =>
      _MobilePaymentScreenState();
}

class _MobilePaymentScreenState extends ConsumerState<MobilePaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  String? _selectedCustomerId;
  String _paymentMethod = 'cash';
  bool _isLoadingBalance = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<_OpenInvoice> _openInvoices = [];
  double _openingBalance = 0;

  double get _totalOwed =>
      _openInvoices.fold<double>(0, (sum, i) => sum + i.balanceAmount) +
      _openingBalance;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _onCustomerChanged(String? customerId) async {
    setState(() {
      _selectedCustomerId = customerId;
      _openInvoices = [];
      _openingBalance = 0;
      _amountController.clear();
      _errorMessage = null;
    });
    if (customerId == null) return;

    setState(() => _isLoadingBalance = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final results = await Future.wait<dynamic>([
        client
            .from('invoices')
            .select('id, invoice_date, balance_amount')
            .eq('status', 'posted')
            .isFilter('voided_at', null)
            .eq('party_id', customerId)
            .gt('balance_amount', 0)
            .order('invoice_date'),
        client
            .from('parties')
            .select('opening_balance')
            .eq('id', customerId)
            .limit(1),
      ]);

      final invoiceRows = results[0] as List<dynamic>;
      final partyRows = results[1] as List<dynamic>;
      final openingBalance = partyRows.isEmpty
          ? 0.0
          : ((partyRows.first as Map<String, dynamic>)['opening_balance']
                      as num?)
                  ?.toDouble() ??
              0;

      final invoices = invoiceRows.map((row) {
        final map = row as Map<String, dynamic>;
        return _OpenInvoice(
          id: map['id'] as String,
          invoiceDate: map['invoice_date'] as String? ?? '',
          balanceAmount: (map['balance_amount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _openInvoices = invoices;
        _openingBalance = openingBalance;
        if (_totalOwed > 0) {
          _amountController.text = _totalOwed.toStringAsFixed(0);
        }
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load customer balance.');
      }
    } finally {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter payment amount';
    if (parsed <= 0) return 'Amount must be greater than zero';
    return null;
  }

  Future<void> _save(_MobilePaymentContext ctx) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      setState(() => _errorMessage = 'Select a customer.');
      return;
    }

    final amount = double.parse(_amountController.text.trim());
    if (_totalOwed <= 0) {
      setState(() => _errorMessage = 'This customer has nothing owing.');
      return;
    }
    if (amount > _totalOwed + 0.0001) {
      setState(() => _errorMessage =
          'Amount cannot exceed amount owed (${formatRwf(_totalOwed)}).');
      return;
    }

    // Allocate oldest invoice first, then any remainder to opening balance.
    var remaining = amount;
    final allocations = <Map<String, dynamic>>[];
    for (final invoice in _openInvoices) {
      if (remaining <= 0) break;
      final alloc = remaining < invoice.balanceAmount
          ? remaining
          : invoice.balanceAmount;
      allocations.add({'invoice_id': invoice.id, 'allocated_amount': alloc});
      remaining -= alloc;
    }
    final openingApplied = remaining < _openingBalance ? remaining : _openingBalance;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final paymentNumber = await client.rpc(
        'get_next_document_number',
        params: {
          'target_tenant_id': ctx.tenantId,
          'target_branch_id': ctx.branchId,
          'target_sequence_code': 'payment',
        },
      ) as String;

      final paymentRows = await client.from('payments').insert({
        'tenant_id': ctx.tenantId,
        'branch_id': ctx.branchId,
        'payment_number': paymentNumber,
        'payment_date': DateTime.now().toIso8601String().substring(0, 10),
        'party_id': _selectedCustomerId,
        'payment_method': _paymentMethod,
        'amount': amount,
        'status': 'posted',
        'created_by': ctx.userId,
        'posted_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id').limit(1);

      final paymentId = (paymentRows as List).first['id'] as String;

      if (allocations.isNotEmpty) {
        await client.from('payment_allocations').insert([
          for (final a in allocations)
            {
              'tenant_id': ctx.tenantId,
              'payment_id': paymentId,
              'invoice_id': a['invoice_id'],
              'allocated_amount': a['allocated_amount'],
              'created_by': ctx.userId,
            }
        ]);
      }

      if (openingApplied > 0) {
        await client
            .from('parties')
            .update({'opening_balance': _openingBalance - openingApplied})
            .eq('id', _selectedCustomerId!);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _errorMessage = 'Could not record payment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contextAsync = ref.watch(mobilePaymentContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Payment'),
        actions: const [MainMenuNavAction()],
      ),
      body: contextAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load payment setup: $error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(mobilePaymentContextProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCustomerId,
                    decoration: const InputDecoration(
                      labelText: 'Customer',
                      border: OutlineInputBorder(),
                    ),
                    items: ctx.customers
                        .map(
                          (customer) => DropdownMenuItem<String>(
                            value: customer.id,
                            child: Text(customer.name),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting ? null : _onCustomerChanged,
                    validator: (value) =>
                        value == null ? 'Select a customer' : null,
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingBalance)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_selectedCustomerId != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Amount owed',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              formatRwf(_totalOwed),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: _totalOwed > 0
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder(),
                    ),
                    items: _paymentMethods.entries
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(
                            () => _paymentMethod = value ?? 'cash'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    enabled: !_isSubmitting,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (RWF)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateAmount,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSubmitting ? null : () => _save(ctx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Record payment'),
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
