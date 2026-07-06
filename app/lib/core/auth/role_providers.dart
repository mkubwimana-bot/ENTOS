import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';

/// True when the signed-in user is an active owner or manager for their tenant.
final canVoidTransactionsProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows as List).isEmpty) return false;

  final tenantId = membershipRows.first['tenant_id'] as String;

  final roleRows = await client
      .from('user_roles')
      .select('roles!inner(role_code)')
      .eq('user_id', userId)
      .eq('tenant_id', tenantId)
      .eq('is_active', true);

  for (final row in roleRows as List<dynamic>) {
    final map = row as Map<String, dynamic>;
    final role = map['roles'] as Map<String, dynamic>?;
    final code = role?['role_code'] as String?;
    if (code == 'owner' || code == 'manager') return true;
  }
  return false;
});
