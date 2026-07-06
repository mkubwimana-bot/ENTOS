import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/party/party_list_providers.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../../core/widgets/transaction_date_field.dart';

enum _AllocationMode { byInvoice, autoAllocate }

class _ClearingDebtContext {
  const _ClearingDebtContext({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.customers,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final List<PartyOption> customers;
}

class _OpenInvoiceOption {
  const _OpenInvoiceOption({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.balanceAmount,
  });

  final String id;
  final String invoiceNumber;
  final String invoiceDate;
  final double balanceAmount;
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

final clearingDebtContextProvider =
    FutureProvider.autoDispose<_ClearingDebtContext>((ref) async {
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

  final customers = await ref.watch(debtorCustomersProvider.future);

  return _ClearingDebtContext(
    tenantId: tenantId,
    userId: userId,
    branchId: branchId,
    customers: customers,
  );
});

class ClearingDebtScreen extends ConsumerStatefulWidget {
  const ClearingDebtScreen({super.key});

  @override
  ConsumerState<ClearingDebtScreen> createState() =>
      _ClearingDebtScreenState();
}

class _ClearingDebtScreenState extends ConsumerState<ClearingDebtScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  _AllocationMode _allocationMode = _AllocationMode.byInvoice;
  String? _selectedCustomerId;
  String? _selectedInvoiceId;
  String _paymentMethod = 'cash';
  DateTime _transactionDate = TransactionDateField.todayDate();
  bool _isSubmitting = false;
  bool _isLoadingInvoices = false;
  bool _payOpeningBalance = false;
  String? _errorMessage;
  List<_OpenInvoiceOption> _openInvoices = [];
  List<_OpenInvoice> _autoInvoices = [];
  double _openingBalance = 0;

  double get _totalOwed =>
      _autoInvoices.fold<double>(0, (sum, i) => sum + i.balanceAmount) +
      _openingBalance;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerBalance(String customerId) async {
    setState(() {
      _isLoadingInvoices = true;
      _errorMessage = null;
      _selectedInvoiceId = null;
      _openInvoices = [];
      _autoInvoices = [];
      _payOpeningBalance = false;
      _openingBalance = 0;
      _amountController.clear();
    });

    try {
      final client = ref.read(supabaseClientProvider);
      final results = await Future.wait<dynamic>([
        client
            .from('invoices')
            .select('id, invoice_number, invoice_date, balance_amount')
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

      final rows = results[0] as List<dynamic>;
      final partyRows = results[1] as List<dynamic>;
      final openingBalance = partyRows.isEmpty
          ? 0.0
          : ((partyRows.first as Map<String, dynamic>)['opening_balance']
                      as num?)
                  ?.toDouble() ??
              0;

      final invoices = rows.map((row) {
        final map = row as Map<String, dynamic>;
        return _OpenInvoiceOption(
          id: map['id'] as String,
          invoiceNumber: map['invoice_number'] as String? ?? '—',
          invoiceDate: map['invoice_date'] as String? ?? '',
          balanceAmount: (map['balance_amount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _openInvoices = invoices;
        _autoInvoices = invoices
            .map(
              (i) => _OpenInvoice(
                id: i.id,
                invoiceDate: i.invoiceDate,
                balanceAmount: i.balanceAmount,
              ),
            )
            .toList();
        _openingBalance = openingBalance;

        if (_allocationMode == _AllocationMode.byInvoice) {
          if (invoices.isEmpty && openingBalance > 0) {
            _payOpeningBalance = true;
            _amountController.text = openingBalance.toStringAsFixed(0);
          } else if (invoices.length == 1) {
            _selectedInvoiceId = invoices.first.id;
            _amountController.text =
                invoices.first.balanceAmount.toStringAsFixed(0);
          }
        } else if (_totalOwed > 0) {
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
      if (mounted) setState(() => _isLoadingInvoices = false);
    }
  }

  void _onCustomerChanged(String? customerId) {
    setState(() {
      _selectedCustomerId = customerId;
      _selectedInvoiceId = null;
      _openInvoices = [];
      _autoInvoices = [];
      _payOpeningBalance = false;
      _openingBalance = 0;
      _amountController.clear();
    });
    if (customerId != null) {
      _loadCustomerBalance(customerId);
    }
  }

  void _onAllocationModeChanged(_AllocationMode mode) {
    setState(() {
      _allocationMode = mode;
      _selectedInvoiceId = null;
      _payOpeningBalance = false;
      _amountController.clear();
    });
    if (_selectedCustomerId != null) {
      _loadCustomerBalance(_selectedCustomerId!);
    }
  }

  void _onInvoiceChanged(String? invoiceId) {
    setState(() => _selectedInvoiceId = invoiceId);
    if (invoiceId == null) {
      _amountController.clear();
      return;
    }
    final invoice = _openInvoices.firstWhere((item) => item.id == invoiceId);
    _amountController.text = invoice.balanceAmount.toStringAsFixed(0);
  }

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter payment amount';
    if (parsed <= 0) return 'Amount must be greater than zero';
    return null;
  }

  Future<void> _saveByInvoice(_ClearingDebtContext ctx) async {
    final amount = double.parse(_amountController.text.trim());

    if (_payOpeningBalance) {
      if (amount > _openingBalance) {
        setState(
          () => _errorMessage =
              'Amount cannot exceed opening balance (${formatRwf(_openingBalance)}).',
        );
        return;
      }
    } else {
      if (_selectedInvoiceId == null) {
        setState(() => _errorMessage = 'Select an invoice.');
        return;
      }
      final invoice =
          _openInvoices.firstWhere((item) => item.id == _selectedInvoiceId);
      if (amount > invoice.balanceAmount) {
        setState(
          () => _errorMessage =
              'Amount cannot exceed invoice balance (${formatRwf(invoice.balanceAmount)}).',
        );
        return;
      }
    }

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
      'payment_date': TransactionDateField.toIsoDate(_transactionDate),
      'party_id': _selectedCustomerId,
      'payment_method': _paymentMethod,
      'amount': amount,
      'status': 'posted',
      'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      'created_by': ctx.userId,
      'posted_at': DateTime.now().toUtc().toIso8601String(),
    }).select('id').limit(1);

    final paymentId = (paymentRows as List).first['id'] as String;

    if (_payOpeningBalance) {
      await client
          .from('parties')
          .update({'opening_balance': _openingBalance - amount})
          .eq('id', _selectedCustomerId!);
    } else {
      final invoice =
          _openInvoices.firstWhere((item) => item.id == _selectedInvoiceId);
      await client.from('payment_allocations').insert({
        'tenant_id': ctx.tenantId,
        'payment_id': paymentId,
        'invoice_id': invoice.id,
        'allocated_amount': amount,
        'created_by': ctx.userId,
      });
    }
  }

  Future<void> _saveAutoAllocate(_ClearingDebtContext ctx) async {
    final amount = double.parse(_amountController.text.trim());
    if (_totalOwed <= 0) {
      setState(() => _errorMessage = 'This customer has nothing owing.');
      return;
    }
    if (amount > _totalOwed + 0.0001) {
      setState(
        () => _errorMessage =
            'Amount cannot exceed amount owed (${formatRwf(_totalOwed)}).',
      );
      return;
    }

    var remaining = amount;
    final allocations = <Map<String, dynamic>>[];
    for (final invoice in _autoInvoices) {
      if (remaining <= 0) break;
      final alloc =
          remaining < invoice.balanceAmount ? remaining : invoice.balanceAmount;
      allocations.add({'invoice_id': invoice.id, 'allocated_amount': alloc});
      remaining -= alloc;
    }
    final openingApplied =
        remaining < _openingBalance ? remaining : _openingBalance;

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
  }

  Future<void> _save(_ClearingDebtContext ctx) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      setState(() => _errorMessage = 'Select a customer.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (_allocationMode == _AllocationMode.byInvoice) {
        await _saveByInvoice(ctx);
      } else {
        await _saveAutoAllocate(ctx);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not record payment. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contextAsync = ref.watch(clearingDebtContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clearing Debt'),
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
                Text(
                  'Could not load payment setup: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(clearingDebtContextProvider),
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
                  SegmentedButton<_AllocationMode>(
                    segments: const [
                      ButtonSegment(
                        value: _AllocationMode.byInvoice,
                        label: Text('By invoice'),
                        icon: Icon(Icons.receipt_outlined),
                      ),
                      ButtonSegment(
                        value: _AllocationMode.autoAllocate,
                        label: Text('Auto allocate'),
                        icon: Icon(Icons.auto_fix_high_outlined),
                      ),
                    ],
                    selected: {_allocationMode},
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (selection) =>
                            _onAllocationModeChanged(selection.first),
                  ),
                  const SizedBox(height: 16),
                  if (_allocationMode == _AllocationMode.byInvoice) ...[
                    TransactionDateField(
                      selectedDate: _transactionDate,
                      enabled: !_isSubmitting,
                      onChanged: (date) =>
                          setState(() => _transactionDate = date),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCustomerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Customer',
                      border: OutlineInputBorder(),
                      helperText: 'Customers with outstanding receivables only',
                    ),
                    items: ctx.customers
                        .map(
                          (customer) => DropdownMenuItem<String>(
                            value: customer.id,
                            child: Text(
                              customer.balance != null
                                  ? '${customer.name} · ${formatRwf(customer.balance!)} owed'
                                  : customer.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting ? null : _onCustomerChanged,
                    validator: (value) =>
                        value == null ? 'Select customer' : null,
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingInvoices)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_selectedCustomerId != null &&
                      _allocationMode == _AllocationMode.autoAllocate)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Amount owed',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              formatRwf(_totalOwed),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: _totalOwed > 0
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_selectedCustomerId != null &&
                      _allocationMode == _AllocationMode.byInvoice &&
                      _openInvoices.isEmpty &&
                      !_isLoadingInvoices &&
                      _openingBalance > 0) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No open invoices. Apply this payment to the opening balance of '
                          '${formatRwf(_openingBalance)}.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ] else if (_selectedCustomerId != null &&
                      _openInvoices.isEmpty &&
                      !_isLoadingInvoices &&
                      _openingBalance <= 0) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'This customer has no outstanding balance.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ] else if (_allocationMode == _AllocationMode.byInvoice &&
                      _openInvoices.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedInvoiceId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Invoice',
                        border: OutlineInputBorder(),
                      ),
                      items: _openInvoices
                          .map(
                            (invoice) => DropdownMenuItem<String>(
                              value: invoice.id,
                              child: Text(
                                '${invoice.invoiceNumber} · '
                                '${formatRwf(invoice.balanceAmount)} due',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isSubmitting ? null : _onInvoiceChanged,
                      validator: (value) =>
                          _payOpeningBalance || value != null
                              ? null
                              : 'Select invoice',
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder(),
                    ),
                    items: _paymentMethods.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _paymentMethod = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountController,
                    enabled: !_isSubmitting &&
                        (_allocationMode == _AllocationMode.autoAllocate ||
                            _payOpeningBalance ||
                            _selectedInvoiceId != null),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount (RWF)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateAmount,
                  ),
                  if (_allocationMode == _AllocationMode.byInvoice) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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
                    onPressed: _isSubmitting ||
                            (_allocationMode == _AllocationMode.byInvoice &&
                                !_payOpeningBalance &&
                                (_selectedInvoiceId == null ||
                                    _openInvoices.isEmpty)) ||
                            (_allocationMode == _AllocationMode.byInvoice &&
                                _payOpeningBalance &&
                                _openingBalance <= 0)
                        ? null
                        : () => _save(ctx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Clear debt'),
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
