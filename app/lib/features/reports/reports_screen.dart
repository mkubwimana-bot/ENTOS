import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

// --- Daily sales ---

class DailySalesRow {
  const DailySalesRow({
    required this.invoiceDate,
    required this.invoiceCount,
    required this.totalSales,
    required this.totalPaid,
    required this.totalBalance,
  });

  final String invoiceDate;
  final int invoiceCount;
  final double totalSales;
  final double totalPaid;
  final double totalBalance;
}

final dailySalesReportProvider =
    FutureProvider.autoDispose<List<DailySalesRow>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('vw_daily_sales')
      .select(
        'invoice_date, invoice_count, total_sales, total_paid, total_balance',
      )
      .order('invoice_date', ascending: false);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return DailySalesRow(
      invoiceDate: map['invoice_date'] as String? ?? '',
      invoiceCount: (map['invoice_count'] as num?)?.toInt() ?? 0,
      totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0,
      totalPaid: (map['total_paid'] as num?)?.toDouble() ?? 0,
      totalBalance: (map['total_balance'] as num?)?.toDouble() ?? 0,
    );
  }).toList();
});

// --- Customer balances ---

class CustomerBalanceRow {
  const CustomerBalanceRow({
    required this.partyCode,
    required this.partyName,
    required this.openingBalance,
    required this.totalInvoiced,
    required this.totalPaid,
    required this.balance,
  });

  final String partyCode;
  final String partyName;
  final double openingBalance;
  final double totalInvoiced;
  final double totalPaid;
  final double balance;
}

final customerBalancesReportProvider =
    FutureProvider.autoDispose<List<CustomerBalanceRow>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('vw_customer_balances')
      .select(
        'party_code, party_name, opening_balance, total_invoiced, total_paid, balance',
      )
      .gt('balance', 0)
      .order('balance', ascending: false);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return CustomerBalanceRow(
      partyCode: map['party_code'] as String? ?? '',
      partyName: map['party_name'] as String? ?? 'Unnamed customer',
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
      totalInvoiced: (map['total_invoiced'] as num?)?.toDouble() ?? 0,
      totalPaid: (map['total_paid'] as num?)?.toDouble() ?? 0,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
    );
  }).toList();
});

// --- Product sales ---

class ProductSalesRow {
  const ProductSalesRow({
    required this.productCode,
    required this.productName,
    required this.quantitySold,
    required this.totalSales,
    required this.estimatedCost,
    required this.estimatedGrossProfit,
  });

  final String productCode;
  final String productName;
  final double quantitySold;
  final double totalSales;
  final double estimatedCost;
  final double estimatedGrossProfit;
}

final productSalesReportProvider =
    FutureProvider.autoDispose<List<ProductSalesRow>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('vw_product_sales_summary')
      .select(
        'product_code, product_name, quantity_sold, total_sales, estimated_cost, estimated_gross_profit',
      )
      .order('total_sales', ascending: false);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return ProductSalesRow(
      productCode: map['product_code'] as String? ?? '',
      productName: map['product_name'] as String? ?? 'Unnamed product',
      quantitySold: (map['quantity_sold'] as num?)?.toDouble() ?? 0,
      totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0,
      estimatedCost: (map['estimated_cost'] as num?)?.toDouble() ?? 0,
      estimatedGrossProfit: (map['estimated_gross_profit'] as num?)?.toDouble() ?? 0,
    );
  }).toList();
});

// --- Gross profit ---

class GrossProfitRow {
  const GrossProfitRow({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    required this.estimatedCost,
    required this.estimatedGrossProfit,
  });

  final String invoiceNumber;
  final String invoiceDate;
  final double totalAmount;
  final double estimatedCost;
  final double estimatedGrossProfit;
}

final grossProfitReportProvider =
    FutureProvider.autoDispose<List<GrossProfitRow>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('vw_gross_profit_simple')
      .select(
        'invoice_number, invoice_date, total_amount, estimated_cost, estimated_gross_profit',
      )
      .order('invoice_date', ascending: false);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return GrossProfitRow(
      invoiceNumber: map['invoice_number'] as String? ?? '',
      invoiceDate: map['invoice_date'] as String? ?? '',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      estimatedCost: (map['estimated_cost'] as num?)?.toDouble() ?? 0,
      estimatedGrossProfit: (map['estimated_gross_profit'] as num?)?.toDouble() ?? 0,
    );
  }).toList();
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          actions: const [MainMenuNavAction()],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Daily sales'),
              Tab(text: 'Balances'),
              Tab(text: 'Products'),
              Tab(text: 'Gross profit'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DailySalesTab(),
            _CustomerBalancesTab(),
            _ProductSalesTab(),
            _GrossProfitTab(),
          ],
        ),
      ),
    );
  }
}

class _DailySalesTab extends ConsumerWidget {
  const _DailySalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(dailySalesReportProvider);
    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: '$error',
        onRetry: () => ref.invalidate(dailySalesReportProvider),
      ),
      data: (rows) => _ReportList(
        emptyMessage: 'No sales recorded yet',
        onRefresh: () async {
          ref.invalidate(dailySalesReportProvider);
          await ref.read(dailySalesReportProvider.future);
        },
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return Card(
            child: ListTile(
              title: Text(row.invoiceDate),
              subtitle: Text(
                '${row.invoiceCount} invoice${row.invoiceCount == 1 ? '' : 's'}',
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRwf(row.totalSales),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Paid ${formatRwf(row.totalPaid)}',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _CustomerBalancesTab extends ConsumerWidget {
  const _CustomerBalancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(customerBalancesReportProvider);
    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: '$error',
        onRetry: () => ref.invalidate(customerBalancesReportProvider),
      ),
      data: (rows) => _ReportList(
        emptyMessage: 'No outstanding customer balances',
        onRefresh: () async {
          ref.invalidate(customerBalancesReportProvider);
          await ref.read(customerBalancesReportProvider.future);
        },
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return Card(
            child: ListTile(
              title: Text(row.partyName),
              subtitle: Text(
                '${row.partyCode} · invoiced ${formatRwf(row.totalInvoiced)} · paid ${formatRwf(row.totalPaid)}',
              ),
              trailing: Text(
                formatRwf(row.balance),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductSalesTab extends ConsumerWidget {
  const _ProductSalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(productSalesReportProvider);
    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: '$error',
        onRetry: () => ref.invalidate(productSalesReportProvider),
      ),
      data: (rows) => _ReportList(
        emptyMessage: 'No product sales yet',
        onRefresh: () async {
          ref.invalidate(productSalesReportProvider);
          await ref.read(productSalesReportProvider.future);
        },
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return Card(
            child: ListTile(
              title: Text(row.productName),
              subtitle: Text(
                '${row.productCode} · qty ${row.quantitySold.toStringAsFixed(0)}',
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRwf(row.totalSales),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Profit ${formatRwf(row.estimatedGrossProfit)}',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _GrossProfitTab extends ConsumerWidget {
  const _GrossProfitTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(grossProfitReportProvider);
    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: '$error',
        onRetry: () => ref.invalidate(grossProfitReportProvider),
      ),
      data: (rows) => _ReportList(
        emptyMessage: 'No invoices for profit estimate',
        onRefresh: () async {
          ref.invalidate(grossProfitReportProvider);
          await ref.read(grossProfitReportProvider.future);
        },
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return Card(
            child: ListTile(
              title: Text(row.invoiceNumber),
              subtitle: Text('${row.invoiceDate} · cost ${formatRwf(row.estimatedCost)}'),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRwf(row.totalAmount),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Profit ${formatRwf(row.estimatedGrossProfit)}',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.emptyMessage,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(child: Text(emptyMessage)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.message, required this.onRetry});

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
