import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/services/attendance_service.dart';

final attendanceServiceProvider = Provider((ref) => AttendanceService());

final todayAttendanceProvider =
    StreamProvider.family<Attendance?, ({String companyId, String userId})>(
        (ref, params) {
  return ref
      .read(attendanceServiceProvider)
      .watchTodayAttendance(params.companyId, params.userId);
});

final todayAllAttendancesProvider =
    StreamProvider.family<List<Attendance>, String>((ref, companyId) {
  return ref.read(attendanceServiceProvider).watchTodayAll(companyId);
});
