import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';

class PartyOption {
  const PartyOption({
    required this.id,
    required this.name,
    this.balance,
  });

  final String id;
  final String name;
  final double? balance;
}

List<PartyOption> _parsePartyTypeLinks(List<dynamic> rows, String typeCode) {
  final parties = <PartyOption>[];
  final seenIds = <String>{};
  for (final row in rows) {
    final map = row as Map<String, dynamic>;
    final partyTypes = map['party_types'] as Map<String, dynamic>?;
    if (partyTypes?['type_code'] != typeCode) continue;
    final party = map['parties'] as Map<String, dynamic>?;
    if (party == null) continue;
    if ((party['status'] as String?) != 'active') continue;
    final id = party['id'] as String?;
    if (id == null || seenIds.contains(id)) continue;
    seenIds.add(id);
    parties.add(
      PartyOption(
        id: id,
        name: party['party_name'] as String? ?? 'Unnamed',
      ),
    );
  }
  parties.sort((a, b) => a.name.compareTo(b.name));
  return parties;
}

final customerPartiesProvider =
    FutureProvider.autoDispose<List<PartyOption>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('party_type_links')
      .select('parties(id, party_name, status), party_types(type_code)');
  return _parsePartyTypeLinks(rows as List<dynamic>, 'customer');
});

final supplierPartiesProvider =
    FutureProvider.autoDispose<List<PartyOption>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('party_type_links')
      .select('parties(id, party_name, status), party_types(type_code)');
  return _parsePartyTypeLinks(rows as List<dynamic>, 'supplier');
});

final debtorCustomersProvider =
    FutureProvider.autoDispose<List<PartyOption>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final results = await Future.wait<dynamic>([
    client
        .from('party_type_links')
        .select('parties(id, party_name, status), party_types(type_code)'),
    client
        .from('vw_customer_balances')
        .select('party_id, balance')
        .gt('balance', 0),
  ]);

  final customers = _parsePartyTypeLinks(results[0] as List<dynamic>, 'customer');
  final balanceByParty = <String, double>{};
  for (final row in results[1] as List<dynamic>) {
    final map = row as Map<String, dynamic>;
    balanceByParty[map['party_id'] as String] =
        (map['balance'] as num?)?.toDouble() ?? 0;
  }

  return customers
      .where((c) => (balanceByParty[c.id] ?? 0) > 0)
      .map(
        (c) => PartyOption(
          id: c.id,
          name: c.name,
          balance: balanceByParty[c.id],
        ),
      )
      .toList();
});
