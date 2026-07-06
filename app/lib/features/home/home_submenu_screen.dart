import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One actionable item inside a home menu category.
class HomeSubMenuItem {
  const HomeSubMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, WidgetRef ref) onTap;
}

/// Second-level menu shown after the user picks a category with sub-items.
class HomeSubMenuScreen extends ConsumerWidget {
  const HomeSubMenuScreen({
    required this.title,
    required this.items,
    super.key,
  });

  final String title;
  final List<HomeSubMenuItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            child: ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => item.onTap(context, ref),
            ),
          );
        },
      ),
    );
  }
}
