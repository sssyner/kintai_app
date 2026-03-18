import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/models/leave_request.dart';
import 'package:kintai_app/services/leave_service.dart';

final leaveServiceProvider = Provider((ref) => LeaveService());

final myLeavesProvider = StreamProvider.family<List<LeaveRequest>,
    ({String companyId, String userId})>((ref, params) {
  return ref
      .read(leaveServiceProvider)
      .watchMyRequests(params.companyId, params.userId);
});

final allLeavesProvider =
    StreamProvider.family<List<LeaveRequest>, String>((ref, companyId) {
  return ref.read(leaveServiceProvider).watchAllRequests(companyId);
});

final pendingLeavesProvider =
    StreamProvider.family<List<LeaveRequest>, String>((ref, companyId) {
  return ref.read(leaveServiceProvider).watchPendingRequests(companyId);
});

final todayLeavesProvider =
    StreamProvider.family<List<LeaveRequest>, String>((ref, companyId) {
  return ref.read(leaveServiceProvider).watchTodayLeaves(companyId);
});
