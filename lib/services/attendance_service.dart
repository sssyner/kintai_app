import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/models/attendance.dart';

class AttendanceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _attendancesRef(String companyId) =>
      _db.collection('companies').doc(companyId).collection('attendances');

  String _todayString() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<Attendance?> getTodayAttendance(
      String companyId, String userId) async {
    final snap = await _attendancesRef(companyId)
        .where('date', isEqualTo: _todayString())
        .get();
    final matches = snap.docs
        .map(Attendance.fromFirestore)
        .where((a) => a.userId == userId);
    return matches.isEmpty ? null : matches.first;
  }

  Stream<Attendance?> watchTodayAttendance(String companyId, String userId) {
    return _attendancesRef(companyId)
        .where('date', isEqualTo: _todayString())
        .snapshots()
        .map((snap) {
      final matches = snap.docs
          .map(Attendance.fromFirestore)
          .where((a) => a.userId == userId);
      return matches.isEmpty ? null : matches.first;
    });
  }

  Future<void> clockIn({
    required String companyId,
    required String userId,
    String? locationId,
    String? locationName,
    required String type,
    String? memo,
  }) async {
    await _attendancesRef(companyId).add({
      'userId': userId,
      'locationId': locationId,
      'locationName': locationName,
      'clockIn': FieldValue.serverTimestamp(),
      'clockOut': null,
      'date': _todayString(),
      'type': type,
      'memo': memo,
    });
  }

  Future<void> clockOut(String companyId, String attendanceId,
      {String? memo}) async {
    final data = <String, dynamic>{
      'clockOut': FieldValue.serverTimestamp(),
    };
    if (memo != null) data['memo'] = memo;
    await _attendancesRef(companyId).doc(attendanceId).update(data);
  }

  Stream<List<Attendance>> watchTodayAll(String companyId) {
    return _attendancesRef(companyId)
        .where('date', isEqualTo: _todayString())
        .snapshots()
        .map((snap) => snap.docs.map(Attendance.fromFirestore).toList());
  }

  Future<bool> autoClockIn({
    required String companyId,
    required String userId,
    String? locationId,
    String? locationName,
  }) async {
    final existing = await getTodayAttendance(companyId, userId);
    if (existing != null) return false;

    await clockIn(
      companyId: companyId,
      userId: userId,
      locationId: locationId,
      locationName: locationName,
      type: 'auto_geofence',
    );
    return true;
  }

  Future<bool> autoClockOut({
    required String companyId,
    required String userId,
  }) async {
    final existing = await getTodayAttendance(companyId, userId);
    if (existing == null || existing.isClockedOut) return false;

    await clockOut(companyId, existing.id);
    return true;
  }

  Future<List<Attendance>> getByMonth(
      String companyId, String userId, int year, int month) async {
    final start = '$year-${month.toString().padLeft(2, '0')}-01';
    final endMonth = month == 12 ? 1 : month + 1;
    final endYear = month == 12 ? year + 1 : year;
    final end = '$endYear-${endMonth.toString().padLeft(2, '0')}-01';

    final snap = await _attendancesRef(companyId)
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThan: end)
        .get();
    final list = snap.docs
        .map(Attendance.fromFirestore)
        .where((a) => a.userId == userId)
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }
}
