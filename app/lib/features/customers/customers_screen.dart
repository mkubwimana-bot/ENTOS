import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import 'edit_customer_screen.dart';
import 'new_customer_screen.dart';

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

final customerListProvider = FutureProvider.autoDispose<List<CustomerListItem>>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
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

  return balanceRows.map((row) {
    final map = row as Map<String, dynamic>;
    final partyId = map['party_id'] as String;
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
  }).toList();
});

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(customerListProvider);
    await ref.read(customerListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customerListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: const [MainMenuNavAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const NewCustomerScreen()),
          );
          if (created == true) {
            ref.invalidate(customerListProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New Customer'),
      ),
      body: customersAsync.when(
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
                  'Could not load customers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(customerListProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (customers) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: customers.isEmpty
              ? const Center(child: Text('No customers yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Owed: ${formatRwf(customer.balance)}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              'Opening ${formatRwf(customer.openingBalance)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Invoiced ${formatRwf(customer.totalInvoiced)} · Paid ${formatRwf(customer.totalPaid)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        onTap: () async {
                          final updated = await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => EditCustomerScreen(
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
      ),
    );
  }
}
