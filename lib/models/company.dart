import 'package:cloud_firestore/cloud_firestore.dart';

class Company {
  final String id;
  final String name;
  final String inviteCode;
  final DateTime createdAt;
  final int standardWorkMinutes; // 標準勤務時間（分）
  final double overtimeThresholdHours; // 月間残業アラート閾値（時間）

  Company({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdAt,
    this.standardWorkMinutes = 480, // デフォルト8時間
    this.overtimeThresholdHours = 45, // デフォルト45時間/月
  });

  factory Company.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Company(
      id: doc.id,
      name: data['name'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      standardWorkMinutes: (data['standardWorkMinutes'] as num?)?.toInt() ?? 480,
      overtimeThresholdHours: (data['overtimeThresholdHours'] as num?)?.toDouble() ?? 45,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'inviteCode': inviteCode,
        'createdAt': FieldValue.serverTimestamp(),
        'standardWorkMinutes': standardWorkMinutes,
        'overtimeThresholdHours': overtimeThresholdHours,
      };
}
