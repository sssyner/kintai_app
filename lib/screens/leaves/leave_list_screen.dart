import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/leave_provider.dart';
import 'package:kintai_app/models/leave_request.dart';
import 'package:kintai_app/screens/leaves/leave_request_screen.dart';
import 'package:kintai_app/screens/employees/employee_profile_screen.dart';
import 'package:kintai_app/widgets/employee_avatar.dart';

class LeaveListScreen extends ConsumerWidget {
  const LeaveListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;
    final employee = ref.watch(currentEmployeeProvider).valueOrNull;

    if (user == null || companyId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isAdmin = employee?.isAdmin ?? false;
    final todayLeavesAsync = ref.watch(todayLeavesProvider(companyId));
    final pendingAsync =
        isAdmin ? ref.watch(pendingLeavesProvider(companyId)) : null;
    final myLeavesAsync = ref.watch(
        myLeavesProvider((companyId: companyId, userId: user.uid)));
    final employees = ref.watch(employeesProvider(companyId));
    final employeeMap = employees.valueOrNull
            ?.asMap()
            .map((_, e) => MapEntry(e.userId, e)) ??
        {};

    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LeaveRequestScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 今日の休暇者
          Text('今日の休暇者', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          todayLeavesAsync.when(
            data: (leaves) {
              if (leaves.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('今日の休暇者はいません',
                        style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return Column(
                children: leaves.map((l) {
                  final emp = employeeMap[l.userId];
                  return Card(
                    child: ListTile(
                      leading: EmployeeAvatar(
                          employee: emp, name: l.userName),
                      title: Text(l.userName),
                      trailing: Chip(
                        label: Text(l.typeLabel),
                        visualDensity: VisualDensity.compact,
                      ),
                      onTap: emp != null
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EmployeeProfileScreen(
                                    companyId: companyId,
                                    employee: emp,
                                    isViewerAdmin: isAdmin,
                                  ),
                                ),
                              )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('エラー: $e'),
          ),
          const SizedBox(height: 20),

          // 承認待ち（管理者のみ）
          if (isAdmin && pendingAsync != null) ...[
            Text('承認待ち', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            pendingAsync.when(
              data: (pending) {
                if (pending.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('承認待ちの申請はありません',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }
                return Column(
                  children: pending
                      .map((l) => _PendingCard(
                            leave: l,
                            companyId: companyId,
                            reviewerUid: user.uid,
                          ))
                      .toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('エラー: $e'),
            ),
            const SizedBox(height: 20),
          ],

          // 自分の申請
          Text('自分の申請', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          myLeavesAsync.when(
            data: (myLeaves) {
              if (myLeaves.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('申請はありません',
                        style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return Column(
                children: myLeaves.map((l) => _MyLeaveCard(leave: l)).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('エラー: $e'),
          ),
          const SizedBox(height: 80), // FABの余白
        ],
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  final LeaveRequest leave;
  final String companyId;
  final String reviewerUid;

  const _PendingCard({
    required this.leave,
    required this.companyId,
    required this.reviewerUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(leave.userName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Chip(
                  label: Text(leave.typeLabel),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                Text(leave.date),
              ],
            ),
            if (leave.reason != null && leave.reason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('理由: ${leave.reason}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => ref
                      .read(leaveServiceProvider)
                      .reject(companyId, leave.id, reviewerUid),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('却下'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => ref
                      .read(leaveServiceProvider)
                      .approve(companyId, leave.id, reviewerUid),
                  child: const Text('承認'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MyLeaveCard extends StatelessWidget {
  final LeaveRequest leave;
  const _MyLeaveCard({required this.leave});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (leave.status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _ => Colors.orange,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(leave.date),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(leave.typeLabel),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (leave.reason != null && leave.reason!.isNotEmpty)
                    Text('理由: ${leave.reason}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(leave.statusLabel,
                  style: TextStyle(
                      color: statusColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
