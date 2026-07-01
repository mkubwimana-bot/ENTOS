import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _SubscriptionInfo {
  const _SubscriptionInfo({
    required this.planName,
    required this.status,
    this.trialEndDate,
    this.currentPeriodEnd,
    required this.isFallback,
  });

  final String planName;
  final String status;
  final String? trialEndDate;
  final String? currentPeriodEnd;
  final bool isFallback;
}

final subscriptionStatusProvider =
    FutureProvider.autoDispose<_SubscriptionInfo>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows as List).isEmpty) {
    throw Exception('No active tenant membership found.');
  }
  final tenantId = membershipRows.first['tenant_id'] as String;

  final subRows = await client
      .from('subscriptions')
      .select(
        'status, trial_end_date, current_period_end, subscription_plans(plan_name)',
      )
      .eq('tenant_id', tenantId)
      .limit(1);

  if (subRows.isNotEmpty) {
    final sub = subRows.first;
    final plan = sub['subscription_plans'] as Map<String, dynamic>?;
    return _SubscriptionInfo(
      planName: plan?['plan_name'] as String? ?? 'Unknown plan',
      status: sub['status'] as String? ?? 'unknown',
      trialEndDate: sub['trial_end_date'] as String?,
      currentPeriodEnd: sub['current_period_end'] as String?,
      isFallback: false,
    );
  }

  final tenantRows = await client
      .from('tenants')
      .select('subscription_status')
      .eq('id', tenantId)
      .limit(1);
  final tenantStatus = tenantRows.isEmpty
      ? 'trial'
      : tenantRows.first['subscription_status'] as String? ?? 'trial';

  return _SubscriptionInfo(
    planName: 'Trial / not configured',
    status: tenantStatus,
    isFallback: true,
  );
});

String _formatStatusLabel(String status) {
  return status.replaceAll('_', ' ');
}

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'active':
    case 'trialing':
    case 'trial':
      return Theme.of(context).colorScheme.primary;
    case 'past_due':
      return Colors.orange.shade700;
    case 'suspended':
    case 'cancelled':
      return Theme.of(context).colorScheme.error;
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class SubscriptionStatusScreen extends ConsumerWidget {
  const SubscriptionStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(subscriptionStatusProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: const [MainMenuNavAction()],
      ),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load subscription: $error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(subscriptionStatusProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (info) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(info.planName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Text('Status', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(context, info.status)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _formatStatusLabel(info.status),
                        style: TextStyle(
                          color: _statusColor(context, info.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (info.trialEndDate != null) ...[
                      const SizedBox(height: 16),
                      Text('Trial ends', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(info.trialEndDate!),
                    ],
                    if (info.currentPeriodEnd != null) ...[
                      const SizedBox(height: 16),
                      Text('Current period ends',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(info.currentPeriodEnd!),
                    ],
                    if (info.isFallback) ...[
                      const SizedBox(height: 16),
                      Text(
                        'No detailed subscription record yet. Your account uses '
                        'the tenant trial status shown above.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Contact support to upgrade your plan or extend your trial.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
