import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/models/company.dart';
import 'package:kintai_app/models/employee.dart';

class OvertimeAlertWidget extends ConsumerWidget {
  final String companyId;
  const OvertimeAlertWidget({super.key, required this.companyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<_OvertimeResult>(
      future: _calcOvertime(companyId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final result = snap.data!;
        if (result.alerts.isEmpty) return const SizedBox.shrink();

        return Card(
          color: Colors.red.shade50,
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text('残業アラート',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700)),
                    const Spacer(),
                    Text('閾値: ${result.threshold.toInt()}h/月',
                        style: TextStyle(
                            fontSize: 12, color: Colors.red.shade400)),
                  ],
                ),
                const SizedBox(height: 12),
                ...result.alerts.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(a.name)),
                          Text(
                            '${a.overtimeHours.toStringAsFixed(1)}h',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: a.overtimeHours > result.threshold
                                  ? Colors.red
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_OvertimeResult> _calcOvertime(String companyId) async {
    final db = FirebaseFirestore.instance;

    // Get company settings
    final companyDoc = await db.collection('companies').doc(companyId).get();
    final company = Company.fromFirestore(companyDoc);
    final standardMinutes = company.standardWorkMinutes;
    final threshold = company.overtimeThresholdHours;

    final now = DateTime.now();
    final start =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final endMonth = now.month == 12 ? 1 : now.month + 1;
    final endYear = now.month == 12 ? now.year + 1 : now.year;
    final end = '$endYear-${endMonth.toString().padLeft(2, '0')}-01';

    final empSnap = await db
        .collection('companies')
        .doc(companyId)
        .collection('employees')
        .get();
    final employees = {
      for (final doc in empSnap.docs) doc.id: Employee.fromFirestore(doc)
    };

    final attSnap = await db
        .collection('companies')
        .doc(companyId)
        .collection('attendances')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThan: end)
        .get();

    final byUser = <String, double>{};
    for (final doc in attSnap.docs) {
      final att = Attendance.fromFirestore(doc);
      if (att.clockOut != null) {
        final mins = att.clockOut!.difference(att.clockIn).inMinutes;
        final overtime = mins > standardMinutes ? (mins - standardMinutes) / 60.0 : 0.0;
        byUser[att.userId] = (byUser[att.userId] ?? 0) + overtime;
      }
    }

    final alerts = <_OvertimeEntry>[];
    for (final entry in byUser.entries) {
      if (entry.value > threshold * 0.8) {
        alerts.add(_OvertimeEntry(
          name: employees[entry.key]?.name ?? entry.key,
          overtimeHours: entry.value,
        ));
      }
    }
    alerts.sort((a, b) => b.overtimeHours.compareTo(a.overtimeHours));
    return _OvertimeResult(alerts: alerts, threshold: threshold);
  }
}

class _OvertimeResult {
  final List<_OvertimeEntry> alerts;
  final double threshold;
  _OvertimeResult({required this.alerts, required this.threshold});
}

class _OvertimeEntry {
  final String name;
  final double overtimeHours;
  _OvertimeEntry({required this.name, required this.overtimeHours});
}
