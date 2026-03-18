import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/models/company.dart';
import 'package:kintai_app/models/employee.dart';
import 'package:kintai_app/providers/company_provider.dart';

class MonthlySummaryScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const MonthlySummaryScreen({super.key, this.embedded = false});

  @override
  ConsumerState<MonthlySummaryScreen> createState() =>
      _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends ConsumerState<MonthlySummaryScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  bool _loading = false;
  List<_EmployeeSummary> _summaries = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) return;
    setState(() => _loading = true);

    try {
      final db = FirebaseFirestore.instance;

      // Get company settings
      final companyDoc = await db.collection('companies').doc(companyId).get();
      final company = Company.fromFirestore(companyDoc);
      final standardMinutes = company.standardWorkMinutes;

      // Get employees
      final empSnap = await db
          .collection('companies')
          .doc(companyId)
          .collection('employees')
          .get();
      final employees = {
        for (final doc in empSnap.docs) doc.id: Employee.fromFirestore(doc)
      };

      // Get attendance
      final start = '$_year-${_month.toString().padLeft(2, '0')}-01';
      final endMonth = _month == 12 ? 1 : _month + 1;
      final endYear = _month == 12 ? _year + 1 : _year;
      final end = '$endYear-${endMonth.toString().padLeft(2, '0')}-01';

      final attSnap = await db
          .collection('companies')
          .doc(companyId)
          .collection('attendances')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThan: end)
          .get();

      // Group by user
      final byUser = <String, List<Attendance>>{};
      for (final doc in attSnap.docs) {
        final att = Attendance.fromFirestore(doc);
        byUser.putIfAbsent(att.userId, () => []).add(att);
      }

      final summaries = <_EmployeeSummary>[];
      for (final entry in employees.entries) {
        final records = byUser[entry.key] ?? [];
        final emp = entry.value;

        double totalMinutes = 0;
        double overtimeMinutes = 0;
        int workDays = 0;
        int directDays = 0;

        for (final att in records) {
          if (att.clockOut != null) {
            final mins = att.clockOut!.difference(att.clockIn).inMinutes;
            totalMinutes += mins;
            if (mins > standardMinutes) overtimeMinutes += mins - standardMinutes;
            workDays++;
          } else {
            workDays++; // Clocked in but not out yet
          }
          if (att.type == 'manual_direct') directDays++;
        }

        summaries.add(_EmployeeSummary(
          name: emp.name,
          email: emp.email,
          workDays: workDays,
          totalHours: totalMinutes / 60,
          overtimeHours: overtimeMinutes / 60,
          directDays: directDays,
        ));
      }

      summaries.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _summaries = summaries);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
        children: [
          // Month selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
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
          ),
          const Divider(height: 1),

          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator())),

          if (!_loading && _summaries.isEmpty)
            const Expanded(child: Center(child: Text('データがありません'))),

          if (!_loading && _summaries.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _summaries.length,
                itemBuilder: (context, i) {
                  final s = _summaries[i];
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _StatChip(
                                  label: '出勤',
                                  value: '${s.workDays}日',
                                  color: Colors.teal),
                              const SizedBox(width: 8),
                              _StatChip(
                                  label: '勤務',
                                  value: _formatHours(s.totalHours),
                                  color: Colors.blue),
                              const SizedBox(width: 8),
                              _StatChip(
                                label: '残業',
                                value: _formatHours(s.overtimeHours),
                                color: s.overtimeHours > 40
                                    ? Colors.red
                                    : Colors.orange,
                              ),
                              if (s.directDays > 0) ...[
                                const SizedBox(width: 8),
                                _StatChip(
                                    label: '直行直帰',
                                    value: '${s.directDays}日',
                                    color: Colors.purple),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(),
      body: body,
    );
  }

  String _formatHours(double hours) {
    final h = hours.toInt();
    final m = ((hours - h) * 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}m';
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color)),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _EmployeeSummary {
  final String name;
  final String email;
  final int workDays;
  final double totalHours;
  final double overtimeHours;
  final int directDays;

  _EmployeeSummary({
    required this.name,
    required this.email,
    required this.workDays,
    required this.totalHours,
    required this.overtimeHours,
    required this.directDays,
  });
}
