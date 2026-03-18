import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/location_provider.dart';
import 'package:kintai_app/screens/locations/location_edit_screen.dart';

class LocationListScreen extends ConsumerWidget {
  const LocationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final locationsAsync = ref.watch(locationsProvider(companyId));

    return Scaffold(
      appBar: AppBar(title: const Text('拠点管理')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LocationEditScreen(companyId: companyId)),
        ),
        child: const Icon(Icons.add),
      ),
      body: locationsAsync.when(
        data: (locations) {
          if (locations.isEmpty) {
            return const Center(child: Text('拠点がありません\n右下の＋ボタンで追加してください',
                textAlign: TextAlign.center));
          }
          return ListView.builder(
            itemCount: locations.length,
            itemBuilder: (context, i) {
              final loc = locations[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(Icons.location_on,
                      color: loc.isActive ? Colors.teal : Colors.grey),
                  title: Text(loc.name),
                  subtitle: Text(
                      '半径: ${loc.radius.toInt()}m  (${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)})'),
                  trailing: loc.isActive
                      ? const Chip(label: Text('有効'))
                      : const Chip(label: Text('無効')),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationEditScreen(
                          companyId: companyId, location: loc),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }
}
