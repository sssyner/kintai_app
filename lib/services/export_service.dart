import 'dart:io';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/models/employee.dart';
import 'package:kintai_app/models/location_geofence.dart';

class ExportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _timeFormat = DateFormat('HH:mm');

  Future<void> exportMonthlyAttendance(
      String companyId, int year, int month) async {
    // Get all employees
    final empSnap = await _db
        .collection('companies')
        .doc(companyId)
        .collection('employees')
        .get();
    final employees = {
      for (final doc in empSnap.docs) doc.id: Employee.fromFirestore(doc)
    };

    // Get attendance records
    final start = '$year-${month.toString().padLeft(2, '0')}-01';
    final endMonth = month == 12 ? 1 : month + 1;
    final endYear = month == 12 ? year + 1 : year;
    final end = '$endYear-${endMonth.toString().padLeft(2, '0')}-01';

    final attSnap = await _db
        .collection('companies')
        .doc(companyId)
        .collection('attendances')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThan: end)
        .orderBy('date')
        .get();

    final rows = <List<String>>[
      ['名前', 'メール', '日付', '出勤', '退勤', '勤務時間', '種別', '拠点', 'メモ'],
    ];

    for (final doc in attSnap.docs) {
      final att = Attendance.fromFirestore(doc);
      final emp = employees[att.userId];
      final hours = att.clockOut != null
          ? att.clockOut!.difference(att.clockIn).inMinutes / 60.0
          : 0.0;
      rows.add([
        emp?.name ?? att.userId,
        emp?.email ?? '',
        att.date,
        _timeFormat.format(att.clockIn),
        att.clockOut != null ? _timeFormat.format(att.clockOut!) : '',
        hours > 0 ? hours.toStringAsFixed(2) : '',
        att.type == 'manual_direct' ? '直行直帰' : 'GPS',
        att.locationName ?? '',
        att.memo ?? '',
      ]);
    }

    await _shareCsv(rows, '勤怠_$year年$month月.csv');
  }

  Future<void> exportEmployees(String companyId) async {
    final snap = await _db
        .collection('companies')
        .doc(companyId)
        .collection('employees')
        .get();

    final rows = <List<String>>[
      ['名前', 'メール', '権限', '参加日'],
    ];
    for (final doc in snap.docs) {
      final emp = Employee.fromFirestore(doc);
      rows.add([
        emp.name,
        emp.email,
        emp.isAdmin ? 'admin' : 'member',
        DateFormat('yyyy-MM-dd').format(emp.joinedAt),
      ]);
    }

    await _shareCsv(rows, '従業員一覧.csv');
  }

  Future<void> exportLocations(String companyId) async {
    final snap = await _db
        .collection('companies')
        .doc(companyId)
        .collection('locations')
        .get();

    final rows = <List<String>>[
      ['拠点名', '緯度', '経度', '半径(m)', '有効'],
    ];
    for (final doc in snap.docs) {
      final loc = LocationGeofence.fromFirestore(doc);
      rows.add([
        loc.name,
        loc.lat.toString(),
        loc.lng.toString(),
        loc.radius.toInt().toString(),
        loc.isActive ? 'はい' : 'いいえ',
      ]);
    }

    await _shareCsv(rows, '拠点一覧.csv');
  }

  Future<void> _shareCsv(List<List<String>> rows, String filename) async {
    final csvString = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csvString);
    await Share.shareXFiles([XFile(file.path)]);
  }
}
