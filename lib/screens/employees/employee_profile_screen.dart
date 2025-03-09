import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/models/employee.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/models/leave_request.dart';
import 'package:kintai_app/models/company.dart';
import 'package:kintai_app/providers/attendance_provider.dart';
import 'package:kintai_app/providers/leave_provider.dart';
import 'package:kintai_app/widgets/employee_avatar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeProfileScreen extends ConsumerStatefulWidget {
  final String companyId;
  final Employee employee;
  final bool isViewerAdmin;

  const EmployeeProfileScreen({
    super.key,
    required this.companyId,
    required this.employee,
    this.isViewerAdmin = false,
  });

  @override
  ConsumerState<EmployeeProfileScreen> createState() =>
      _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState
    extends ConsumerState<EmployeeProfileScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  bool _loading = false;
  List<Attendance> _attendances = [];
  List<LeaveRequest> _leaves = [];
  int _standardMinutes = 480;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;

      final companyDoc =
          await db.collection('companies').doc(widget.companyId).get();
      final company = Company.fromFirestore(companyDoc);
      _standardMinutes = company.standardWorkMinutes;

      // 管理者は出退勤も取得、一般はスキップ
      if (widget.isViewerAdmin) {
        final atts = await ref.read(attendanceServiceProvider).getByMonth(
            widget.companyId, widget.employee.userId, _year, _month);
        _attendances = atts;
      }

      // 休暇は全員取得
      final lvs = await ref.read(leaveServiceProvider).getByMonth(
          widget.companyId, widget.employee.userId, _year, _month);

      setState(() {
        _leaves = lvs;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    final isAdmin = widget.isViewerAdmin;

    // 集計（管理者のみ）
    int workDays = 0;
    double totalMinutes = 0;
    double overtimeMinutes = 0;
    if (isAdmin) {
      for (final att in _attendances) {
        if (att.clockOut != null) {
          final mins = att.clockOut!.difference(att.clockIn).inMinutes;
          totalMinutes += mins;
          if (mins > _standardMinutes) {
            overtimeMinutes += mins - _standardMinutes;
          }
          workDays++;
        } else {
          workDays++;
        }
      }
    }
    final approvedLeaves =
        _leaves.where((l) => l.status == 'approved').toList();

    return Scaffold(
      appBar: AppBar(title: Text(emp.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // プロフィール
          Center(child: EmployeeAvatar(employee: emp, radius: 40)),
          const SizedBox(height: 12),
          Center(
            child: Text(emp.name,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          if (isAdmin)
            Center(
              child: Text(emp.email,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          Center(
            child: Chip(
              label: Text(emp.isAdmin ? '管理者' : 'メンバー'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 20),

          // 月選択
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_month == 1) {
                      _month = 12;
                      _year--;
                    } else {
                      _month--;
                    }
                  });
                  _load();
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '$_year年$_month月',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_month == 12) {
                      _month = 1;
                      _year++;
                    } else {
                      _month++;
                    }
                  });
                  _load();
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            // サマリーカード（管理者: フル、一般: 休暇日数のみ）
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (isAdmin) ...[
                      _Stat(
                          label: '出勤',
                          value: '$workDays日',
                          color: Colors.teal),
                      _Stat(
                          label: '勤務',
                          value: _formatHours(totalMinutes / 60),
                          color: Colors.blue),
                      _Stat(
                          label: '残業',
                          value: _formatHours(overtimeMinutes / 60),
                          color: overtimeMinutes > 0
                              ? Colors.orange
                              : Colors.grey),
                    ],
                    _Stat(
                        label: '休暇',
                        value: '${approvedLeaves.length}日',
                        color: Colors.purple),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 休暇一覧（全員に見せる）
            if (approvedLeaves.isNotEmpty) ...[
              Text('休暇', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...approvedLeaves.map((l) => Card(
                    child: ListTile(
                      leading: Icon(Icons.event_busy,
                          color: Colors.orange.shade700),
                      title: Text('${l.date}  ${l.typeLabel}'),
                      subtitle: l.reason?.isNotEmpty == true
                          ? Text(l.reason!)
                          : null,
                    ),
                  )),
              const SizedBox(height: 16),
            ],
            if (approvedLeaves.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('この月の休暇はありません',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),

            // 出退勤一覧（管理者のみ）
            if (isAdmin) ...[
              const SizedBox(height: 16),
              Text('出退勤', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_attendances.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('この月の出退勤記録はありません',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ..._attendances.map((att) {
                final timeFormat = DateFormat('HH:mm');
                final duration =
                    att.clockOut?.difference(att.clockIn).inMinutes;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      att.type == 'manual_direct'
                          ? Icons.directions_walk
                          : att.type == 'auto_geofence'
                              ? Icons.location_on
                              : Icons.gps_fixed,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(att.date),
                    subtitle: Text(
                      '${timeFormat.format(att.clockIn)}'
                      '${att.clockOut != null ? ' → ${timeFormat.format(att.clockOut!)}' : ' (勤務中)'}'
                      '${duration != null ? '  (${_formatHours(duration / 60)})' : ''}',
                    ),
                    trailing: duration != null && duration > _standardMinutes
                        ? Text(
                            '+${_formatHours((duration - _standardMinutes) / 60)}',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  String _formatHours(double hours) {
    final h = hours.toInt();
    final m = ((hours - h) * 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}m';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
