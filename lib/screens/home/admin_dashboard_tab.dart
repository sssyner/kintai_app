import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/attendance_provider.dart';
import 'package:kintai_app/providers/location_provider.dart';
import 'package:kintai_app/providers/gps_provider.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/screens/employees/employee_profile_screen.dart';
import 'package:kintai_app/widgets/overtime_alert_widget.dart';
import 'package:kintai_app/widgets/employee_avatar.dart';

class AdminDashboardTab extends ConsumerWidget {
  final bool embedded;
  const AdminDashboardTab({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;

    if (user == null || companyId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final myAttendance = ref.watch(
        todayAttendanceProvider((companyId: companyId, userId: user.uid)));
    final allAttendances = ref.watch(todayAllAttendancesProvider(companyId));
    final employees = ref.watch(employeesProvider(companyId));

    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // My attendance section
          Text('自分の打刻', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          myAttendance.when(
            data: (att) => _MyAttendanceCard(
              companyId: companyId,
              userId: user.uid,
              attendance: att,
            ),
            loading: () => const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()))),
            error: (e, _) => Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('エラー: $e'))),
          ),
          const SizedBox(height: 24),

          // Overtime alert
          OvertimeAlertWidget(companyId: companyId),

          const SizedBox(height: 24),

          // All employees today
          Text('本日の出勤状況', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          allAttendances.when(
            data: (list) {
              final employeeList = employees.valueOrNull ?? [];
              if (list.isEmpty) {
                return const Card(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('まだ出勤者はいません')));
              }
              return Column(
                children: list.map((att) {
                  final emp = employeeList
                      .where((e) => e.userId == att.userId)
                      .firstOrNull;
                  final name = emp?.name ?? att.userId;
                  final timeFormat = DateFormat('HH:mm');
                  return Card(
                    child: ListTile(
                      leading: EmployeeAvatar(
                        employee: emp,
                        name: name,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '出勤: ${timeFormat.format(att.clockIn)}'
                        '${att.clockOut != null ? '  退勤: ${timeFormat.format(att.clockOut!)}' : ''}'
                        '${att.type == 'manual_direct' ? '  (直行直帰)' : ''}',
                      ),
                      trailing: att.isClockedOut
                          ? const Text('退勤済',
                              style: TextStyle(color: Colors.green))
                          : const Text('出勤中',
                              style: TextStyle(color: Colors.orange)),
                      onTap: () {
                        if (emp != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmployeeProfileScreen(
                                companyId: companyId,
                                employee: emp,
                                isViewerAdmin: true,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('エラー: $e'),
          ),
        ],
      );

    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(),
      body: body,
    );
  }
}

class _MyAttendanceCard extends ConsumerStatefulWidget {
  final String companyId;
  final String userId;
  final Attendance? attendance;

  const _MyAttendanceCard({
    required this.companyId,
    required this.userId,
    required this.attendance,
  });

  @override
  ConsumerState<_MyAttendanceCard> createState() => _MyAttendanceCardState();
}

class _MyAttendanceCardState extends ConsumerState<_MyAttendanceCard> {
  bool _loading = false;

  Future<void> _clockIn() async {
    setState(() => _loading = true);
    try {
      final position = await ref.read(gpsServiceProvider).getCurrentPosition();
      final locations =
          ref.read(locationsProvider(widget.companyId)).valueOrNull ?? [];
      final gps = ref.read(gpsServiceProvider);
      final nearest = gps.findNearestGeofence(
          position.latitude, position.longitude, locations);
      final isInside = nearest != null &&
          gps.isInsideGeofence(position.latitude, position.longitude, nearest);

      await ref.read(attendanceServiceProvider).clockIn(
            companyId: widget.companyId,
            userId: widget.userId,
            locationId: isInside ? nearest.id : null,
            locationName: isInside ? nearest.name : null,
            type: 'auto',
          );
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clockOut() async {
    if (widget.attendance == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(attendanceServiceProvider)
          .clockOut(widget.companyId, widget.attendance!.id);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attendance;
    final isClockedIn = att != null && !att.isClockedOut;
    final isDone = att != null && att.isClockedOut;
    final timeFormat = DateFormat('HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (att != null)
              Text(
                '出勤: ${timeFormat.format(att.clockIn)}'
                '${att.clockOut != null ? '  退勤: ${timeFormat.format(att.clockOut!)}' : ''}',
              ),
            if (att == null) const Text('未出勤'),
            const SizedBox(height: 12),
            if (!isClockedIn && !isDone)
              FilledButton(
                onPressed: _loading ? null : _clockIn,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('出勤（GPS）'),
              ),
            if (isClockedIn)
              FilledButton(
                onPressed: _loading ? null : _clockOut,
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('退勤（GPS）'),
              ),
            if (isDone)
              const Text('本日の勤務完了',
                  style: TextStyle(color: Colors.green)),
          ],
        ),
      ),
    );
  }
}
