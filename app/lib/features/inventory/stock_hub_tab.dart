import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_providers.dart';
import '../purchases/new_purchase_screen.dart';
import '../purchases/purchases_list_screen.dart';
import '../sales/offline_sale_queue.dart';
import 'current_stock_screen.dart';
import 'inventory_valuation_screen.dart';
import 'low_stock_screen.dart';
import 'stock_adjustment_screen.dart';
import 'stock_movement_history_screen.dart';

class StockHubOverview {
  const StockHubOverview({
    required this.totalItems,
    required this.lowStockCount,
  });

  final int totalItems;
  final int lowStockCount;
}

final stockHubOverviewProvider =
    FutureProvider.autoDispose<StockHubOverview>((ref) async {
  final items = await ref.watch(currentStockProvider.future);
  final lowCount = items.where((item) => item.isLowStock).length;
  return StockHubOverview(
    totalItems: items.length,
    lowStockCount: lowCount,
  );
});

/// Stock hub shown on the bottom-nav Stock tab.
class StockHubTab extends ConsumerWidget {
  const StockHubTab({super.key});

  static const heroGreen = Color(0xFF3D9A50);
  static const heroGreenDark = Color(0xFF2E7D3E);
  static const ctaGreen = Color(0xFF1F6B31);
  static const warningOrange = Color(0xFFF57C00);
  static const pageBackground = Color(0xFFF4F6F8);

  Future<void> _openNewPurchase(BuildContext context, WidgetRef ref) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const NewPurchaseScreen()),
    );
    if (recorded == true) {
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(currentStockProvider);
      ref.invalidate(stockHubOverviewProvider);
    }
  }

  Future<void> _openStockAdjustment(BuildContext context, WidgetRef ref) async {
    final adjusted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const StockAdjustmentScreen()),
    );
    if (adjusted == true) {
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(currentStockProvider);
      ref.invalidate(stockHubOverviewProvider);
    }
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stock'),
        content: const Text(
          'Record New Purchase — add stock received from a supplier.\n\n'
          'Current Stock — see quantities on hand for each product.\n\n'
          'Low Stock — items at or below their reorder level.\n\n'
          'Purchase History, Stock Movement, Adjustments, and Inventory Value — '
          'full records and control tools.',
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
    final overviewAsync = ref.watch(stockHubOverviewProvider);

    return ColoredBox(
      color: pageBackground,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentStockProvider);
            ref.invalidate(stockHubOverviewProvider);
            try {
              await ref.read(stockHubOverviewProvider.future);
            } catch (_) {}
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _StockHeader(onHelpTap: () => _showHelp(context)),
              const SizedBox(height: 16),
              overviewAsync.when(
                loading: () => const _OverviewSkeleton(),
                error: (error, _) {
                  final offline = isOfflineError(error);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StockOverviewCard(
                        totalItems: 0,
                        lowStockCount: 0,
                        offline: offline,
                      ),
                      const SizedBox(height: 16),
                      _buildActions(context, ref),
                    ],
                  );
                },
                data: (overview) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StockOverviewCard(
                      totalItems: overview.totalItems,
                      lowStockCount: overview.lowStockCount,
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
        _RecordPurchaseButton(onTap: () => _openNewPurchase(context, ref)),
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
                  title: 'Current Stock',
                  subtitle: 'View available items and quantities',
                  icon: Icons.inventory_2_outlined,
                  iconColor: heroGreen,
                  background: const Color(0xFFE8F5E9),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CurrentStockScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionTile(
                  title: 'Low Stock',
                  subtitle: 'See items that need restocking',
                  icon: Icons.warning_amber_rounded,
                  iconColor: warningOrange,
                  background: const Color(0xFFFFF3E0),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LowStockScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Records & Control',
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
                _ControlTile(
                  title: 'Purchase History',
                  subtitle: 'View and search all purchases',
                  icon: Icons.assignment_outlined,
                  iconColor: heroGreen,
                  iconBackground: const Color(0xFFE8F5E9),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PurchasesListScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _ControlTile(
                  title: 'Stock Movement',
                  subtitle: 'Track stock in and stock out',
                  icon: Icons.sync_alt,
                  iconColor: heroGreen,
                  iconBackground: const Color(0xFFE8F5E9),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StockMovementHistoryScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _ControlTile(
                  title: 'Stock Adjustments',
                  subtitle: 'Correct damaged, lost or counted stock',
                  icon: Icons.tune,
                  iconColor: heroGreen,
                  iconBackground: const Color(0xFFE8F5E9),
                  onTap: () => _openStockAdjustment(context, ref),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _ControlTile(
                  title: 'Inventory Value',
                  subtitle: 'Check the value of your stock',
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: heroGreen,
                  iconBackground: const Color(0xFFE8F5E9),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InventoryValuationScreen(),
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

class _StockHeader extends StatelessWidget {
  const _StockHeader({required this.onHelpTap});

  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 48),
        Expanded(
          child: Text(
            'Stock',
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
              border: Border.all(color: StockHubTab.heroGreen, width: 1.5),
            ),
            child: const Icon(
              Icons.help_outline,
              size: 18,
              color: StockHubTab.heroGreen,
            ),
          ),
        ),
      ],
    );
  }
}

class _StockOverviewCard extends StatelessWidget {
  const _StockOverviewCard({
    required this.totalItems,
    required this.lowStockCount,
    this.offline = false,
  });

  final int totalItems;
  final int lowStockCount;
  final bool offline;

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
                      offline ? 'Offline' : 'Stock Overview',
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
                    'Stock totals update when online',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF546E7A),
                        ),
                  )
                else
                  Text(
                    '$totalItems item${totalItems == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: StockHubTab.heroGreen,
                        ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      offline
                          ? Icons.cloud_off_outlined
                          : Icons.warning_amber_rounded,
                      size: 16,
                      color: offline
                          ? const Color(0xFF546E7A)
                          : StockHubTab.warningOrange,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        offline
                            ? 'Purchases and adjustments need a connection'
                            : lowStockCount == 0
                                ? 'All items above reorder level'
                                : '$lowStockCount item${lowStockCount == 1 ? '' : 's'} low in stock',
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
              offline ? Icons.cloud_off_outlined : Icons.warehouse_outlined,
              color: offline
                  ? const Color(0xFF546E7A)
                  : StockHubTab.heroGreenDark,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordPurchaseButton extends StatelessWidget {
  const _RecordPurchaseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StockHubTab.ctaGreen,
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
                      'Record New Purchase',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Add purchased stock and update items',
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

class _ControlTile extends StatelessWidget {
  const _ControlTile({
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

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

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
