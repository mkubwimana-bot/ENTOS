import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_providers.dart';
import '../sales/offline_sale_queue.dart';
import '../sales/quick_sale_screen.dart';
import 'home_context_provider.dart';

class HomeDashboardTab extends ConsumerWidget {
  const HomeDashboardTab({
    required this.onOpenDrawer,
    required this.onSalesTap,
    required this.onProductsTap,
    required this.onCustomersTap,
    required this.onStockTap,
    required this.onReportsTap,
    required this.onSyncTap,
    super.key,
  });

  final VoidCallback onOpenDrawer;
  final VoidCallback onSalesTap;
  final VoidCallback onProductsTap;
  final VoidCallback onCustomersTap;
  final VoidCallback onStockTap;
  final VoidCallback onReportsTap;
  final VoidCallback onSyncTap;

  static const heroGreen = Color(0xFF3D9A50);
  static const heroGreenDark = Color(0xFF2E7D3E);
  static const ctaGreen = Color(0xFF1F6B31);

  Future<void> _openQuickSale(BuildContext context, WidgetRef ref) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const QuickSaleScreen()),
    );
    if (recorded == true) {
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(homeSalesTrendProvider);
      ref.invalidate(offlinePendingCountProvider);
    }
  }

  Widget _dashboardBody(
    BuildContext context,
    WidgetRef ref, {
    DashboardSummary? summary,
    required bool isOffline,
    required int pendingOfflineSales,
    double? trendPercent,
  }) {
    final syncSubtitle = pendingOfflineSales > 0
        ? '$pendingOfflineSales sale${pendingOfflineSales == 1 ? '' : 's'} waiting to sync'
        : isOffline
            ? 'Connect to the internet to sync'
            : summary!.pendingMobileCount > 0
                ? '${summary.pendingMobileCount} item(s) waiting to sync'
                : 'All sales synced';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodaySalesCard(
          amount: summary?.todaySales ?? 0,
          invoiceCount: summary?.todayInvoiceCount ?? 0,
          trendPercent: isOffline ? null : trendPercent,
          offline: isOffline,
          pendingOfflineSales: pendingOfflineSales,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _openQuickSale(context, ref),
          style: FilledButton.styleFrom(
            backgroundColor: ctaGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text(
            'New Sale',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _QuickActionCard(
              title: 'Sales & Payments',
              subtitle: 'Record sales, receive payments',
              icon: Icons.payments_outlined,
              iconColor: heroGreen,
              iconBackground: const Color(0xFFE8F5E9),
              onTap: onSalesTap,
            ),
            _QuickActionCard(
              title: 'Products',
              subtitle: 'Manage items, prices & stock',
              icon: Icons.shopping_cart_outlined,
              iconColor: const Color(0xFF1976D2),
              iconBackground: const Color(0xFFE3F2FD),
              onTap: onProductsTap,
            ),
            _QuickActionCard(
              title: 'Customers',
              subtitle: 'Manage customers & suppliers',
              icon: Icons.people_outline,
              iconColor: const Color(0xFF7B1FA2),
              iconBackground: const Color(0xFFF3E5F5),
              onTap: onCustomersTap,
            ),
            _QuickActionCard(
              title: 'Stock',
              subtitle: 'Check stock & movements',
              icon: Icons.inventory_2_outlined,
              iconColor: const Color(0xFFF57C00),
              iconBackground: const Color(0xFFFFF3E0),
              onTap: onStockTap,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'At a Glance',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
        ),
        const SizedBox(height: 12),
        if (isOffline)
          _GlanceCard(
            title: 'Offline sales',
            value: pendingOfflineSales == 0
                ? 'None waiting'
                : '$pendingOfflineSales to sync',
            icon: Icons.cloud_off_outlined,
            accent: const Color(0xFF546E7A),
            background: const Color(0xFFECEFF1),
            onTap: onSyncTap,
          )
        else
          Row(
            children: [
              Expanded(
                child: _GlanceCard(
                  title: 'Low Stock Items',
                  value: '${summary!.lowStockCount} items',
                  icon: Icons.inventory_outlined,
                  accent: const Color(0xFFF57C00),
                  background: const Color(0xFFFFF8E1),
                  onTap: onStockTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GlanceCard(
                  title: 'Customers Owing',
                  value: formatRwf(summary.moneyOwed),
                  icon: Icons.groups_outlined,
                  accent: const Color(0xFF1976D2),
                  background: const Color(0xFFE8EEF7),
                  onTap: onSalesTap,
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text(
          'More',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2332),
              ),
        ),
        const SizedBox(height: 8),
        _MoreTile(
          title: 'Reports',
          subtitle: 'Sales, expenses & profit',
          icon: Icons.bar_chart_outlined,
          onTap: onReportsTap,
        ),
        _MoreTile(
          title: 'Sync & Backup',
          subtitle: syncSubtitle,
          icon: Icons.cloud_outlined,
          onTap: onSyncTap,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contextAsync = ref.watch(homeContextProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final trendAsync = ref.watch(homeSalesTrendProvider);
    final pendingOffline =
        ref.watch(offlinePendingCountProvider).asData?.value ?? 0;

    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeContextProvider);
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(homeSalesTrendProvider);
            ref.invalidate(offlinePendingCountProvider);
            try {
              await ref.read(dashboardSummaryProvider.future);
            } catch (_) {
              // Offline — dashboard shows cached-friendly UI instead.
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              contextAsync.when(
                loading: () => const _HeaderSkeleton(),
                error: (error, _) {
                  if (isOfflineError(error)) {
                    final email =
                        ref.read(supabaseClientProvider).auth.currentUser?.email ??
                            'there';
                    return _HomeHeader(
                      userName: email.split('@').first,
                      businessLine: 'Offline · sync when back online',
                      onMenuTap: onOpenDrawer,
                      onAlertsTap: onSyncTap,
                      pendingAlerts: pendingOffline,
                    );
                  }
                  return const SizedBox.shrink();
                },
                data: (ctx) => _HomeHeader(
                  userName: ctx.userName,
                  businessLine: ctx.businessLine,
                  onMenuTap: onOpenDrawer,
                  onAlertsTap: onSyncTap,
                  pendingAlerts: ctx.pendingSyncCount,
                ),
              ),
              const SizedBox(height: 16),
              summaryAsync.when(
                loading: () => const _HeroSkeleton(),
                error: (error, _) {
                  if (isOfflineError(error)) {
                    return _dashboardBody(
                      context,
                      ref,
                      isOffline: true,
                      pendingOfflineSales: pendingOffline,
                    );
                  }
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Could not load today\'s sales. Pull down to retry.',
                      ),
                    ),
                  );
                },
                data: (summary) {
                  final trend = trendAsync.asData?.value;
                  return _dashboardBody(
                    context,
                    ref,
                    summary: summary,
                    isOffline: false,
                    pendingOfflineSales: pendingOffline,
                    trendPercent: trend,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.userName,
    required this.businessLine,
    required this.onMenuTap,
    required this.onAlertsTap,
    required this.pendingAlerts,
  });

  final String userName;
  final String businessLine;
  final VoidCallback onMenuTap;
  final VoidCallback onAlertsTap;
  final int pendingAlerts;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: onMenuTap,
          icon: const Icon(Icons.menu),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1A2332),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $userName 👋',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A2332),
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                businessLine,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HomeDashboardTab.heroGreenDark,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onAlertsTap,
              icon: const Icon(Icons.notifications_outlined),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A2332),
              ),
            ),
            if (pendingAlerts > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE53935),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TodaySalesCard extends StatelessWidget {
  const _TodaySalesCard({
    required this.amount,
    required this.invoiceCount,
    required this.trendPercent,
    this.offline = false,
    this.pendingOfflineSales = 0,
  });

  final double amount;
  final int invoiceCount;
  final double? trendPercent;
  final bool offline;
  final int pendingOfflineSales;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: offline
              ? [const Color(0xFF546E7A), const Color(0xFF455A64)]
              : [HomeDashboardTab.heroGreen, HomeDashboardTab.heroGreenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (offline ? const Color(0xFF546E7A) : HomeDashboardTab.heroGreen)
                .withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      offline ? 'You\'re offline' : 'Today\'s Sales',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (!offline) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (offline)
                  Text(
                    pendingOfflineSales > 0
                        ? '$pendingOfflineSales sale${pendingOfflineSales == 1 ? '' : 's'} saved on this device'
                        : 'Sales save on this device and sync when online',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  )
                else
                  Text(
                    formatRwf(amount),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                const SizedBox(height: 8),
                if (offline)
                  Text(
                    'Today\'s totals update after you reconnect',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  )
                else if (trendPercent != null)
                  Row(
                    children: [
                      Icon(
                        trendPercent! >= 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${trendPercent!.abs().toStringAsFixed(0)}% vs yesterday',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    invoiceCount == 0
                        ? 'No sales recorded today yet'
                        : '$invoiceCount sale${invoiceCount == 1 ? '' : 's'} today',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              offline ? Icons.cloud_off_outlined : Icons.show_chart,
              color: Colors.white.withValues(alpha: 0.95),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6EBF0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),
              const Spacer(),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlanceCard extends StatelessWidget {
  const _GlanceCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.background,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6EBF0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE6EBF0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A2332)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 56,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
