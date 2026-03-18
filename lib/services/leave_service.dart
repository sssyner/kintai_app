import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/models/leave_request.dart';

class LeaveService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _leavesRef(String companyId) =>
      _db.collection('companies').doc(companyId).collection('leaves');

  String _todayString() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> createRequest({
    required String companyId,
    required String userId,
    required String userName,
    required String type,
    required String date,
    String? reason,
  }) async {
    await _leavesRef(companyId).add({
      'userId': userId,
      'userName': userName,
      'type': type,
      'date': date,
      'reason': reason,
      'status': 'pending',
      'reviewedBy': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 自分の申請一覧
  Stream<List<LeaveRequest>> watchMyRequests(
      String companyId, String userId) {
    return _leavesRef(companyId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(LeaveRequest.fromFirestore)
          .where((l) => l.userId == userId)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 全休暇一覧
  Stream<List<LeaveRequest>> watchAllRequests(String companyId) {
    return _leavesRef(companyId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(LeaveRequest.fromFirestore).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 今日の休暇者一覧（承認済み）
  Stream<List<LeaveRequest>> watchTodayLeaves(String companyId) {
    final today = _todayString();
    return _leavesRef(companyId)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map(LeaveRequest.fromFirestore)
          .where((l) => l.date == today && l.status == 'approved')
          .toList();
    });
  }

  /// 未承認の申請一覧
  Stream<List<LeaveRequest>> watchPendingRequests(String companyId) {
    return _leavesRef(companyId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(LeaveRequest.fromFirestore).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 月間の承認済み休暇（履歴カレンダー用）
  Future<List<LeaveRequest>> getByMonth(
      String companyId, String userId, int year, int month) async {
    final start = '$year-${month.toString().padLeft(2, '0')}-01';
    final endMonth = month == 12 ? 1 : month + 1;
    final endYear = month == 12 ? year + 1 : year;
    final end = '$endYear-${endMonth.toString().padLeft(2, '0')}-01';

    final snap = await _leavesRef(companyId).get();
    return snap.docs
        .map(LeaveRequest.fromFirestore)
        .where((l) =>
            l.userId == userId &&
            l.date.compareTo(start) >= 0 &&
            l.date.compareTo(end) < 0)
        .toList();
  }

  Future<void> approve(
      String companyId, String leaveId, String reviewerUid) async {
    await _leavesRef(companyId).doc(leaveId).update({
      'status': 'approved',
      'reviewedBy': reviewerUid,
    });
  }

  Future<void> reject(
      String companyId, String leaveId, String reviewerUid) async {
    await _leavesRef(companyId).doc(leaveId).update({
      'status': 'rejected',
      'reviewedBy': reviewerUid,
    });
  }

  Future<void> deleteRequest(String companyId, String leaveId) async {
    await _leavesRef(companyId).doc(leaveId).delete();
  }
}
