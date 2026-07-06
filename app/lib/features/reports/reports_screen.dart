import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../../core/widgets/report_period_filter.dart';
import '../sales/offline_sale_queue.dart';
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

final dailySalesReportProvider = FutureProvider.autoDispose<List<DailySalesRow>>(
  (ref) async {
    final period = ref.watch(reportPeriodProvider);
    final range = period.range;
    final rows = await ref
        .read(supabaseClientProvider)
        .from('vw_daily_sales')
        .select(
          'invoice_date, invoice_count, total_sales, total_paid, total_balance',
        )
        .gte('invoice_date', formatIsoDate(range.start))
        .lte('invoice_date', formatIsoDate(range.end))
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
  },
);

// --- Gross profit by product ---

class ProductProfitRow {
  const ProductProfitRow({
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

final productProfitReportProvider =
    FutureProvider.autoDispose<List<ProductProfitRow>>((ref) async {
      final period = ref.watch(reportPeriodProvider);
      final range = period.range;

      final rows = await ref
          .read(supabaseClientProvider)
          .from('invoice_lines')
          .select(
            'quantity, line_total, cost_price_snapshot, product_id, '
            'products(product_code, product_name), '
            'invoices!inner(invoice_date, status, voided_at)',
          )
          .eq('invoices.status', 'posted')
          .isFilter('invoices.voided_at', null)
          .gte('invoices.invoice_date', formatIsoDate(range.start))
          .lte('invoices.invoice_date', formatIsoDate(range.end));

      final byProduct =
          <
            String,
            ({String code, String name, double qty, double sales, double cost})
          >{};

      for (final row in rows as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        final productId = map['product_id'] as String;
        final product = map['products'] as Map<String, dynamic>?;
        final qty = (map['quantity'] as num?)?.toDouble() ?? 0;
        final lineTotal = (map['line_total'] as num?)?.toDouble() ?? 0;
        final unitCost = (map['cost_price_snapshot'] as num?)?.toDouble() ?? 0;
        final lineCost = unitCost * qty;

        final existing = byProduct[productId];
        if (existing == null) {
          byProduct[productId] = (
            code: product?['product_code'] as String? ?? '',
            name: product?['product_name'] as String? ?? 'Unnamed product',
            qty: qty,
            sales: lineTotal,
            cost: lineCost,
          );
        } else {
          byProduct[productId] = (
            code: existing.code,
            name: existing.name,
            qty: existing.qty + qty,
            sales: existing.sales + lineTotal,
            cost: existing.cost + lineCost,
          );
        }
      }

      final results =
          byProduct.values
              .map(
                (p) => ProductProfitRow(
                  productCode: p.code,
                  productName: p.name,
                  quantitySold: p.qty,
                  totalSales: p.sales,
                  estimatedCost: p.cost,
                  estimatedGrossProfit: p.sales - p.cost,
                ),
              )
              .toList()
            ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

      return results;
    });

// --- Receivables aging ---

class ReceivablesAgingRow {
  const ReceivablesAgingRow({
    required this.partyName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.outstanding,
    required this.agingBucket,
  });

  final String partyName;
  final String invoiceNumber;
  final String invoiceDate;
  final String? dueDate;
  final double outstanding;
  final String agingBucket;
}

const _agingBucketLabels = <String, String>{
  'current': 'Current',
  '1_30': '1-30 days overdue',
  '31_60': '31-60 days overdue',
  '61_90': '61-90 days overdue',
  'over_90': 'Over 90 days',
  'no_due_date': 'No due date',
};

const _agingBucketOrder = [
  'current',
  '1_30',
  '31_60',
  '61_90',
  'over_90',
  'no_due_date',
];

final receivablesAgingReportProvider =
    FutureProvider.autoDispose<List<ReceivablesAgingRow>>((ref) async {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('vw_receivables_aging')
          .select(
            'party_name, invoice_number, invoice_date, due_date, outstanding, aging_bucket',
          )
          .gt('outstanding', 0)
          .order('due_date');

      return (rows as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        return ReceivablesAgingRow(
          partyName: map['party_name'] as String? ?? 'Unnamed customer',
          invoiceNumber: map['invoice_number'] as String? ?? '',
          invoiceDate: map['invoice_date'] as String? ?? '',
          dueDate: map['due_date'] as String?,
          outstanding: (map['outstanding'] as num?)?.toDouble() ?? 0,
          agingBucket: map['aging_bucket'] as String? ?? 'no_due_date',
        );
      }).toList();
    });

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({this.embeddedInShell = false, super.key});

  /// When true, hides the main-menu action (used inside bottom navigation).
  final bool embeddedInShell;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  static const heroGreen = Color(0xFF3D9A50);
  static const heroGreenDark = Color(0xFF2E7D3E);
  static const pageBackground = Color(0xFFF4F6F8);

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showPeriod = _tabController.index != 2;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embeddedInShell)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Reports',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A2332),
              ),
            ),
          ),
        _ReportsTabBar(controller: _tabController),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DailySalesTab(showPeriod: showPeriod),
              _GrossProfitTab(showPeriod: showPeriod),
              const _ReceivablesAgingTab(),
            ],
          ),
        ),
      ],
    );

    if (widget.embeddedInShell) {
      return ColoredBox(
        color: pageBackground,
        child: SafeArea(bottom: false, child: body),
      );
    }

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: const Text('Reports'),
        actions: const [MainMenuNavAction()],
      ),
      body: body,
    );
  }
}

class _ReportsTabBar extends StatelessWidget {
  const _ReportsTabBar({required this.controller});

  final TabController controller;

  static const _tabs = [
    (label: 'Daily Sales', icon: Icons.bar_chart_outlined),
    (label: 'Gross Profit', icon: Icons.pie_chart_outline),
    (label: 'Aging', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => controller.animateTo(i),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _tabs[i].icon,
                                size: 18,
                                color: controller.index == i
                                    ? _ReportsScreenState.heroGreen
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _tabs[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: controller.index == i
                                        ? _ReportsScreenState.heroGreen
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: controller.index == i
                                  ? _ReportsScreenState.heroGreen
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _periodTotalLabel(ReportPeriodKind kind) {
  switch (kind) {
    case ReportPeriodKind.today:
      return 'Total for today';
    case ReportPeriodKind.thisWeek:
      return 'Total for this week';
    case ReportPeriodKind.thisMonth:
      return 'Total for this month';
    case ReportPeriodKind.custom:
      return 'Total for selected period';
  }
}

class _ReportsSummaryCard extends StatelessWidget {
  const _ReportsSummaryCard({
    required this.label,
    required this.amount,
    this.subtitle = 'Applies to Daily Sales & Gross Profit',
  });

  final String label;
  final double amount;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bar_chart,
              color: _ReportsScreenState.heroGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatRwf(amount),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _ReportsScreenState.heroGreen,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.show_chart,
              color: _ReportsScreenState.heroGreenDark,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsPeriodSection extends ConsumerWidget {
  const _ReportsPeriodSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final notifier = ref.read(reportPeriodProvider.notifier);

    Future<void> pickCustom() async {
      final initialRange = DateTimeRange(
        start: period.customStart ?? period.range.start,
        end: period.customEnd ?? period.range.end,
      );
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: initialRange,
      );
      if (picked == null) return;
      notifier.setCustom(picked.start, picked.end);
    }

    Widget periodChip({
      required String label,
      required ReportPeriodKind kind,
      VoidCallback? onTap,
    }) {
      final selected = period.kind == kind;
      return Expanded(
        child: Material(
          color: selected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap ?? () => notifier.setKind(kind),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? _ReportsScreenState.heroGreen
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check,
                      size: 14,
                      color: _ReportsScreenState.heroGreen,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? _ReportsScreenState.heroGreenDark
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select Period',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A2332),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            periodChip(label: 'Today', kind: ReportPeriodKind.today),
            const SizedBox(width: 8),
            periodChip(label: 'This week', kind: ReportPeriodKind.thisWeek),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            periodChip(label: 'This month', kind: ReportPeriodKind.thisMonth),
            const SizedBox(width: 8),
            periodChip(
              label: 'Custom',
              kind: ReportPeriodKind.custom,
              onTap: pickCustom,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                period.label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
        if (period.kind == ReportPeriodKind.custom) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: pickCustom,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: const Text('Change dates'),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Applies to Daily Sales & Gross Profit',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _DailySalesTab extends ConsumerWidget {
  const _DailySalesTab({required this.showPeriod});

  final bool showPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(dailySalesReportProvider);
    final period = ref.watch(reportPeriodProvider);

    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: isOfflineError(error)
            ? 'Connect to the internet to load reports.'
            : 'Could not load report. Pull down to retry.',
        onRetry: () => ref.invalidate(dailySalesReportProvider),
      ),
      data: (rows) {
        final periodTotal = rows.fold<double>(
          0,
          (sum, row) => sum + row.totalSales,
        );
        return _ReportScroll(
          emptyMessage: 'No sales in this period',
          onRefresh: () async {
            ref.invalidate(dailySalesReportProvider);
            await ref.read(dailySalesReportProvider.future);
          },
          header: [
            _ReportsSummaryCard(
              label: _periodTotalLabel(period.kind),
              amount: periodTotal,
            ),
            const SizedBox(height: 20),
            if (showPeriod) const _ReportsPeriodSection(),
            const SizedBox(height: 20),
            Text(
              'Daily Summary',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
            ),
            const SizedBox(height: 10),
          ],
          rows: rows,
          rowBuilder: (row) => _DailySalesRowCard(row: row as DailySalesRow),
        );
      },
    );
  }
}

class _GrossProfitTab extends ConsumerWidget {
  const _GrossProfitTab({required this.showPeriod});

  final bool showPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(productProfitReportProvider);
    final period = ref.watch(reportPeriodProvider);

    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: isOfflineError(error)
            ? 'Connect to the internet to load reports.'
            : 'Could not load report. Pull down to retry.',
        onRetry: () => ref.invalidate(productProfitReportProvider),
      ),
      data: (rows) {
        final totalProfit = rows.fold<double>(
          0,
          (sum, row) => sum + row.estimatedGrossProfit,
        );

        return _ReportScroll(
          emptyMessage: 'No product sales in this period',
          onRefresh: () async {
            ref.invalidate(productProfitReportProvider);
            await ref.read(productProfitReportProvider.future);
          },
          header: [
            _ReportsSummaryCard(
              label: _periodTotalLabel(period.kind),
              amount: totalProfit,
              subtitle: 'Estimated gross profit for this period',
            ),
            const SizedBox(height: 20),
            if (showPeriod) const _ReportsPeriodSection(),
            const SizedBox(height: 20),
            Text(
              'By Product',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
            ),
            const SizedBox(height: 10),
          ],
          rows: rows,
          rowBuilder: (row) =>
              _ProductProfitRowCard(row: row as ProductProfitRow),
        );
      },
    );
  }
}

class _ReceivablesAgingTab extends ConsumerWidget {
  const _ReceivablesAgingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(receivablesAgingReportProvider);

    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ReportError(
        message: isOfflineError(error)
            ? 'Connect to the internet to load reports.'
            : 'Could not load report. Pull down to retry.',
        onRetry: () => ref.invalidate(receivablesAgingReportProvider),
      ),
      data: (rows) {
        final bucketTotals = <String, double>{};
        for (final bucket in _agingBucketOrder) {
          bucketTotals[bucket] = 0;
        }
        var totalOutstanding = 0.0;
        for (final row in rows) {
          bucketTotals[row.agingBucket] =
              (bucketTotals[row.agingBucket] ?? 0) + row.outstanding;
          totalOutstanding += row.outstanding;
        }

        return _ReportScroll(
          emptyMessage: 'No outstanding receivables',
          onRefresh: () async {
            ref.invalidate(receivablesAgingReportProvider);
            await ref.read(receivablesAgingReportProvider.future);
          },
          header: [
            _ReportsSummaryCard(
              label: 'Total outstanding',
              amount: totalOutstanding,
              subtitle: 'Unpaid customer invoices',
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final bucket in _agingBucketOrder)
                    if ((bucketTotals[bucket] ?? 0) > 0)
                      Chip(
                        label: Text(
                          '${_agingBucketLabels[bucket] ?? bucket}: '
                          '${formatRwf(bucketTotals[bucket]!)}',
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Outstanding Invoices',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
            ),
            const SizedBox(height: 10),
          ],
          rows: rows,
          rowBuilder: (row) => _AgingRowCard(row: row as ReceivablesAgingRow),
        );
      },
    );
  }
}

class _DailySalesRowCard extends StatelessWidget {
  const _DailySalesRowCard({required this.row});

  final DailySalesRow row;

  @override
  Widget build(BuildContext context) {
    return _ReportRowCard(
      title: row.invoiceDate,
      subtitle:
          '${row.invoiceCount} invoice${row.invoiceCount == 1 ? '' : 's'}',
      amount: formatRwf(row.totalSales),
      amountDetail: 'Paid ${formatRwf(row.totalPaid)}',
    );
  }
}

class _ProductProfitRowCard extends StatelessWidget {
  const _ProductProfitRowCard({required this.row});

  final ProductProfitRow row;

  @override
  Widget build(BuildContext context) {
    return _ReportRowCard(
      title: row.productName,
      subtitle:
          '${row.productCode} · qty ${row.quantitySold.toStringAsFixed(0)}',
      amount: formatRwf(row.totalSales),
      amountDetail: 'Profit ${formatRwf(row.estimatedGrossProfit)}',
    );
  }
}

class _AgingRowCard extends StatelessWidget {
  const _AgingRowCard({required this.row});

  final ReceivablesAgingRow row;

  @override
  Widget build(BuildContext context) {
    return _ReportRowCard(
      title: row.partyName,
      subtitle:
          '${row.invoiceNumber} · ${_agingBucketLabels[row.agingBucket] ?? row.agingBucket}',
      amount: formatRwf(row.outstanding),
      amountDetail: row.dueDate != null ? 'Due ${row.dueDate}' : 'No due date',
    );
  }
}

class _ReportRowCard extends StatelessWidget {
  const _ReportRowCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountDetail,
  });

  final String title;
  final String subtitle;
  final String amount;
  final String amountDetail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EBF0)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1A2332),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _ReportsScreenState.heroGreen,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  amountDetail,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ReportScroll extends StatelessWidget {
  const _ReportScroll({
    required this.emptyMessage,
    required this.onRefresh,
    required this.header,
    required this.rows,
    required this.rowBuilder,
  });

  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final List<Widget> header;
  final List<dynamic> rows;
  final Widget Function(dynamic row) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ...header,
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            for (final row in rows) ...[
              rowBuilder(row),
              const SizedBox(height: 8),
            ],
        ],
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
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.grey.shade500,
            ),
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
