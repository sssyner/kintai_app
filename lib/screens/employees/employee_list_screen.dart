import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/widgets/employee_avatar.dart';
import 'package:kintai_app/screens/employees/employee_profile_screen.dart';

class EmployeeListScreen extends ConsumerWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final employeesAsync = ref.watch(employeesProvider(companyId));
    final inviteCodeAsync = ref.watch(inviteCodeProvider(companyId));

    return Scaffold(
      appBar: AppBar(title: const Text('従業員一覧')),
      body: Column(
        children: [
          // Invite code card
          inviteCodeAsync.when(
            data: (code) => Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('招待コード',
                              style: TextStyle(fontSize: 12)),
                          Text(code,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('コピーしました')));
                      },
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Employee list
          Expanded(
            child: employeesAsync.when(
              data: (employees) {
                if (employees.isEmpty) {
                  return const Center(child: Text('従業員がいません'));
                }
                return ListView.builder(
                  itemCount: employees.length,
                  itemBuilder: (context, i) {
                    final emp = employees[i];
                    return ListTile(
                      leading: EmployeeAvatar(employee: emp),
                      title: Text(emp.name),
                      subtitle: Text(emp.email),
                      trailing: emp.isAdmin
                          ? Chip(
                              label: const Text('管理者'),
                              backgroundColor:
                                  Theme.of(context).colorScheme.primaryContainer,
                            )
                          : const Chip(label: Text('メンバー')),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EmployeeProfileScreen(
                            companyId: companyId,
                            employee: emp,
                            isViewerAdmin: true,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('エラー: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
