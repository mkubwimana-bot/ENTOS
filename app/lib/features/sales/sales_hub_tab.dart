import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../dashboard/dashboard_providers.dart';
import '../payments/clearing_debt_screen.dart';
import '../payments/payments_list_screen.dart';
import '../sync/offline_auto_sync.dart';
import 'new_sale_screen.dart';
import 'offline_sale_queue.dart';
import 'quick_sale_screen.dart';
import 'sales_list_screen.dart';

/// Sales & payments hub shown on the bottom-nav Sales tab.
class SalesHubTab extends ConsumerWidget {
  const SalesHubTab({super.key});

  static const heroGreen = Color(0xFF3D9A50);
  static const heroGreenDark = Color(0xFF2E7D3E);
  static const ctaGreen = Color(0xFF1F6B31);
  static const pageBackground = Color(0xFFF4F6F8);

  Future<void> _openNewSale(BuildContext context, WidgetRef ref) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const NewSaleScreen()),
    );
    if (recorded == true) {
      ref.invalidate(dashboardSummaryProvider);
    }
  }

  Future<void> _openQuickSale(BuildContext context, WidgetRef ref) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const QuickSaleScreen()),
    );
    if (recorded == true) {
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(offlinePendingCountProvider);
      requestOfflineAutoSync(ref);
    }
  }

  Future<void> _openClearingDebt(BuildContext context, WidgetRef ref) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ClearingDebtScreen()),
    );
    if (recorded == true) {
      ref.invalidate(dashboardSummaryProvider);
    }
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sales & payments'),
        content: const Text(
          'Record New Sale — full invoice with customer, lines, and payment details.\n\n'
          'Quick Sale — fast cash sale with a saved product list (works offline after one online open).\n\n'
          'Receive Customer Payment — apply payment against customer debt.\n\n'
          'Sales History and Payment History — browse past records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final pendingOffline =
        ref.watch(offlinePendingCountProvider).asData?.value ?? 0;

    return ColoredBox(
      color: pageBackground,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(offlinePendingCountProvider);
            try {
              await ref.read(dashboardSummaryProvider.future);
            } catch (_) {}
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SalesHeader(onHelpTap: () => _showHelp(context)),
              const SizedBox(height: 16),
              summaryAsync.when(
                loading: () => const _SummarySkeleton(),
                error: (error, _) {
                  final offline = isOfflineError(error);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TodaySalesSummaryCard(
                        amount: 0,
                        invoiceCount: 0,
                        offline: offline,
                        pendingOfflineSales: pendingOffline,
                      ),
                      const SizedBox(height: 16),
                      _buildActions(context, ref),
                    ],
                  );
                },
                data: (summary) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodaySalesSummaryCard(
                      amount: summary.todaySales,
                      invoiceCount: summary.todayInvoiceCount,
                    ),
                    const SizedBox(height: 16),
                    _buildActions(context, ref),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecordNewSaleButton(onTap: () => _openNewSale(context, ref)),
        const SizedBox(height: 24),
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _QuickActionTile(
                  title: 'Quick Sale',
                  subtitle: 'Record a simple sale in seconds',
                  icon: Icons.bolt,
                  iconColor: heroGreen,
                  background: const Color(0xFFE8F5E9),
                  onTap: () => _openQuickSale(context, ref),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionTile(
                  title: 'Receive Customer Payment',
                  subtitle: 'Record payment from customer debt',
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: const Color(0xFF1976D2),
                  background: const Color(0xFFE3F2FD),
                  onTap: () => _openClearingDebt(context, ref),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Records & History',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6EBF0)),
            ),
            child: Column(
              children: [
                _HistoryTile(
                  title: 'Sales History',
                  subtitle: 'View and search all sales',
                  icon: Icons.grid_view_rounded,
                  iconColor: heroGreen,
                  iconBackground: const Color(0xFFE8F5E9),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SalesListScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _HistoryTile(
                  title: 'Payment History',
                  subtitle: 'View all received payments',
                  icon: Icons.receipt_long_outlined,
                  iconColor: const Color(0xFFF57C00),
                  iconBackground: const Color(0xFFFFF3E0),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PaymentsListScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SalesHeader extends StatelessWidget {
  const _SalesHeader({required this.onHelpTap});

  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 48),
        Expanded(
          child: Text(
            'Sales',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A2332),
                ),
          ),
        ),
        IconButton(
          onPressed: onHelpTap,
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SalesHubTab.heroGreen, width: 1.5),
            ),
            child: const Icon(
              Icons.help_outline,
              size: 18,
              color: SalesHubTab.heroGreen,
            ),
          ),
        ),
      ],
    );
  }
}

class _TodaySalesSummaryCard extends StatelessWidget {
  const _TodaySalesSummaryCard({
    required this.amount,
    required this.invoiceCount,
    this.offline = false,
    this.pendingOfflineSales = 0,
  });

  final double amount;
  final int invoiceCount;
  final bool offline;
  final int pendingOfflineSales;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBF0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      offline ? 'Offline' : 'Today\'s Sales',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (!offline) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (offline)
                  Text(
                    pendingOfflineSales > 0
                        ? '$pendingOfflineSales saved locally'
                        : 'Totals update when online',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF546E7A),
                        ),
                  )
                else
                  Text(
                    formatRwf(amount),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: SalesHubTab.heroGreen,
                        ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      offline ? Icons.cloud_off_outlined : Icons.trending_up,
                      size: 16,
                      color: offline
                          ? const Color(0xFF546E7A)
                          : SalesHubTab.heroGreen,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        offline
                            ? 'You can still record sales on this device'
                            : invoiceCount == 0
                                ? 'No sales recorded today yet'
                                : '$invoiceCount sale${invoiceCount == 1 ? '' : 's'} recorded today',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: offline
                  ? const Color(0xFFECEFF1)
                  : const Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              offline ? Icons.cloud_off_outlined : Icons.show_chart,
              color: offline
                  ? const Color(0xFF546E7A)
                  : SalesHubTab.heroGreenDark,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordNewSaleButton extends StatelessWidget {
  const _RecordNewSaleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SalesHubTab.ctaGreen,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Record New Sale',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Add a new sale with all details',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF1A2332),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
      onTap: onTap,
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ],
    );
  }
}
