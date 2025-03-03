import 'package:cloud_firestore/cloud_firestore.dart';

class LeaveRequest {
  final String id;
  final String userId;
  final String userName;
  final String type; // 'paid', 'sick', 'half_am', 'half_pm', 'absence'
  final String date; // "2026-03-13"
  final String? reason;
  final String status; // 'pending', 'approved', 'rejected'
  final String? reviewedBy;
  final DateTime createdAt;

  LeaveRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.type,
    required this.date,
    this.reason,
    required this.status,
    this.reviewedBy,
    required this.createdAt,
  });

  String get typeLabel {
    switch (type) {
      case 'paid':
        return '有給休暇';
      case 'sick':
        return '病欠';
      case 'half_am':
        return '午前半休';
      case 'half_pm':
        return '午後半休';
      case 'absence':
        return '欠勤';
      default:
        return type;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '申請中';
      case 'approved':
        return '承認';
      case 'rejected':
        return '却下';
      default:
        return status;
    }
  }

  factory LeaveRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return LeaveRequest(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      type: data['type'] ?? 'paid',
      date: data['date'] ?? '',
      reason: data['reason'],
      status: data['status'] ?? 'pending',
      reviewedBy: data['reviewedBy'],
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        'type': type,
        'date': date,
        'reason': reason,
        'status': status,
        'reviewedBy': reviewedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
