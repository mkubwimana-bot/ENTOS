import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/party/party_list_providers.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../purchases/edit_supplier_screen.dart';
import '../purchases/new_supplier_screen.dart';
import 'edit_customer_screen.dart';
import 'new_customer_screen.dart';

enum _PartyListKind { customers, suppliers }

class CustomerListItem {
  const CustomerListItem({
    required this.partyId,
    required this.partyCode,
    required this.partyName,
    required this.status,
    required this.openingBalance,
    required this.totalInvoiced,
    required this.totalPaid,
    required this.balance,
    required this.creditLimit,
  });

  final String partyId;
  final String partyCode;
  final String partyName;
  final String status;
  final double openingBalance;
  final double totalInvoiced;
  final double totalPaid;
  final double balance;
  final double? creditLimit;
}

class SupplierListItem {
  const SupplierListItem({
    required this.partyId,
    required this.partyCode,
    required this.partyName,
    required this.status,
  });

  final String partyId;
  final String partyCode;
  final String partyName;
  final String status;
}

final customerListProvider = FutureProvider.autoDispose<List<CustomerListItem>>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final customerParties = await ref.watch(customerPartiesProvider.future);
  final customerIds = customerParties.map((p) => p.id).toSet();
  if (customerIds.isEmpty) return [];

  final results = await Future.wait<dynamic>([
    client
        .from('vw_customer_balances')
        .select(
          'party_id, party_code, party_name, opening_balance, total_invoiced, total_paid, balance',
        )
        .order('party_name'),
    client
        .from('parties')
        .select('id, status, customer_credit_limit')
        .isFilter('deleted_at', null),
  ]);

  final balanceRows = results[0] as List<dynamic>;
  final partyRows = results[1] as List<dynamic>;

  final partyMetaById = <String, Map<String, dynamic>>{};
  for (final row in partyRows) {
    final map = row as Map<String, dynamic>;
    partyMetaById[map['id'] as String] = map;
  }

  return balanceRows
      .map((row) {
        final map = row as Map<String, dynamic>;
        final partyId = map['party_id'] as String;
        if (!customerIds.contains(partyId)) return null;
        final meta = partyMetaById[partyId];
        return CustomerListItem(
          partyId: partyId,
          partyCode: map['party_code'] as String? ?? '',
          partyName: map['party_name'] as String? ?? 'Unnamed customer',
          status: meta?['status'] as String? ?? 'unknown',
          openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
          totalInvoiced: (map['total_invoiced'] as num?)?.toDouble() ?? 0,
          totalPaid: (map['total_paid'] as num?)?.toDouble() ?? 0,
          balance: (map['balance'] as num?)?.toDouble() ?? 0,
          creditLimit: (meta?['customer_credit_limit'] as num?)?.toDouble(),
        );
      })
      .whereType<CustomerListItem>()
      .toList();
});

final supplierListProvider = FutureProvider.autoDispose<List<SupplierListItem>>(
  (ref) async {
    final client = ref.read(supabaseClientProvider);
    final suppliers = await ref.watch(supplierPartiesProvider.future);
    if (suppliers.isEmpty) return [];

    final partyRows = await client
        .from('parties')
        .select('id, party_code, party_name, status')
        .isFilter('deleted_at', null);

    final metaById = <String, Map<String, dynamic>>{};
    for (final row in partyRows as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      metaById[map['id'] as String] = map;
    }

    return suppliers.map((supplier) {
      final meta = metaById[supplier.id];
      return SupplierListItem(
        partyId: supplier.id,
        partyCode: meta?['party_code'] as String? ?? '',
        partyName: supplier.name,
        status: meta?['status'] as String? ?? 'unknown',
      );
    }).toList();
  },
);

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  _PartyListKind _listKind = _PartyListKind.customers;

  Future<void> _refresh() async {
    if (_listKind == _PartyListKind.customers) {
      ref.invalidate(customerListProvider);
      await ref.read(customerListProvider.future);
    } else {
      ref.invalidate(supplierListProvider);
      await ref.read(supplierListProvider.future);
    }
  }

  Future<void> _openCreateForm() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _listKind == _PartyListKind.customers
            ? const NewCustomerScreen()
            : const NewSupplierScreen(),
      ),
    );
    if (created == true) {
      ref.invalidate(customerListProvider);
      ref.invalidate(supplierListProvider);
      ref.invalidate(customerPartiesProvider);
      ref.invalidate(supplierPartiesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerListProvider);
    final suppliersAsync = ref.watch(supplierListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers & Suppliers'),
        actions: const [MainMenuNavAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateForm,
        icon: const Icon(Icons.add),
        label: Text(
          _listKind == _PartyListKind.customers
              ? 'New Customer'
              : 'New Supplier',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<_PartyListKind>(
              segments: const [
                ButtonSegment(
                  value: _PartyListKind.customers,
                  label: Text('Customers'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: _PartyListKind.suppliers,
                  label: Text('Suppliers'),
                  icon: Icon(Icons.local_shipping_outlined),
                ),
              ],
              selected: {_listKind},
              onSelectionChanged: (selection) {
                setState(() => _listKind = selection.first);
              },
            ),
          ),
          Expanded(
            child: _listKind == _PartyListKind.customers
                ? customersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorBody(
                      message: 'Could not load customers: $error',
                      onRetry: () => ref.invalidate(customerListProvider),
                    ),
                    data: (customers) => RefreshIndicator(
                      onRefresh: _refresh,
                      child: customers.isEmpty
                          ? const Center(child: Text('No customers yet'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: customers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final customer = customers[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(customer.partyName),
                                    subtitle: Text(
                                      '${customer.partyCode} • ${customer.status}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Owed: ${formatRwf(customer.balance)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelLarge,
                                        ),
                                        Text(
                                          'Opening ${formatRwf(customer.openingBalance)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        Text(
                                          'Invoiced ${formatRwf(customer.totalInvoiced)} · Paid ${formatRwf(customer.totalPaid)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      final updated =
                                          await Navigator.of(
                                            context,
                                          ).push<bool>(
                                            MaterialPageRoute<bool>(
                                              builder: (_) =>
                                                  EditCustomerScreen(
                                                    partyId: customer.partyId,
                                                  ),
                                            ),
                                          );
                                      if (updated == true) {
                                        ref.invalidate(customerListProvider);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  )
                : suppliersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorBody(
                      message: 'Could not load suppliers: $error',
                      onRetry: () => ref.invalidate(supplierListProvider),
                    ),
                    data: (suppliers) => RefreshIndicator(
                      onRefresh: _refresh,
                      child: suppliers.isEmpty
                          ? const Center(child: Text('No suppliers yet'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: suppliers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final supplier = suppliers[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(supplier.partyName),
                                    subtitle: Text(
                                      '${supplier.partyCode} • ${supplier.status}',
                                    ),
                                    leading: const Icon(
                                      Icons.local_shipping_outlined,
                                    ),
                                    onTap: () async {
                                      final updated =
                                          await Navigator.of(
                                            context,
                                          ).push<bool>(
                                            MaterialPageRoute<bool>(
                                              builder: (_) =>
                                                  EditSupplierScreen(
                                                    partyId: supplier.partyId,
                                                  ),
                                            ),
                                          );
                                      if (updated == true) {
                                        ref.invalidate(supplierListProvider);
                                        ref.invalidate(supplierPartiesProvider);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
