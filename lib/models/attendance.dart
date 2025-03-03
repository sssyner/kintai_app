import 'package:cloud_firestore/cloud_firestore.dart';

class Attendance {
  final String id;
  final String userId;
  final String? locationId;
  final String? locationName;
  final DateTime clockIn;
  final DateTime? clockOut;
  final String date; // "2026-03-13"
  final String type; // "auto" or "manual_direct"
  final String? memo;

  Attendance({
    required this.id,
    required this.userId,
    this.locationId,
    this.locationName,
    required this.clockIn,
    this.clockOut,
    required this.date,
    required this.type,
    this.memo,
  });

  bool get isClockedOut => clockOut != null;

  factory Attendance.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Attendance(
      id: doc.id,
      userId: data['userId'] ?? '',
      locationId: data['locationId'],
      locationName: data['locationName'],
      clockIn: (data['clockIn'] as Timestamp?)?.toDate() ?? DateTime.now(),
      clockOut: (data['clockOut'] as Timestamp?)?.toDate(),
      date: data['date'] ?? '',
      type: data['type'] ?? 'auto',
      memo: data['memo'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'locationId': locationId,
        'locationName': locationName,
        'clockIn': Timestamp.fromDate(clockIn),
        'clockOut': clockOut != null ? Timestamp.fromDate(clockOut!) : null,
        'date': date,
        'type': type,
        'memo': memo,
      };
}
