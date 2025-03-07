import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/services/export_service.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _loading = false;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エクスポートエラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final service = ExportService();

    return Scaffold(
      appBar: AppBar(title: const Text('CSVエクスポート')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Month/year picker for attendance
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('勤怠記録',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedYear,
                          decoration: const InputDecoration(labelText: '年'),
                          items: List.generate(5, (i) {
                            final y = DateTime.now().year - 2 + i;
                            return DropdownMenuItem(
                                value: y, child: Text('$y年'));
                          }),
                          onChanged: (v) =>
                              setState(() => _selectedYear = v ?? _selectedYear),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedMonth,
                          decoration: const InputDecoration(labelText: '月'),
                          items: List.generate(
                              12,
                              (i) => DropdownMenuItem(
                                  value: i + 1, child: Text('${i + 1}月'))),
                          onChanged: (v) => setState(
                              () => _selectedMonth = v ?? _selectedMonth),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _export(() => service.exportMonthlyAttendance(
                            companyId, _selectedYear, _selectedMonth)),
                    icon: const Icon(Icons.download),
                    label: Text('$_selectedYear年$_selectedMonth月の勤怠をエクスポート'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Employees
          Card(
            child: ListTile(
              leading: const Icon(Icons.people),
              title: const Text('従業員一覧'),
              subtitle: const Text('名前・メール・権限・参加日'),
              trailing: IconButton(
                onPressed: _loading
                    ? null
                    : () => _export(
                        () => service.exportEmployees(companyId)),
                icon: const Icon(Icons.download),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Locations
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('拠点一覧'),
              subtitle: const Text('拠点名・座標・半径'),
              trailing: IconButton(
                onPressed: _loading
                    ? null
                    : () => _export(
                        () => service.exportLocations(companyId)),
                icon: const Icon(Icons.download),
              ),
            ),
          ),

          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
