import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoom {
  final String id;
  final String type; // 'company' (全体) or 'group'
  final String name;
  final List<String> memberIds;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageBy;

  ChatRoom({
    required this.id,
    required this.type,
    required this.name,
    required this.memberIds,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageBy,
  });

  bool get isCompanyWide => type == 'company';

  factory ChatRoom.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return ChatRoom(
      id: doc.id,
      type: data['type'] ?? 'group',
      name: data['name'] ?? '',
      memberIds: List<String>.from(data['memberIds'] ?? []),
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageBy: data['lastMessageBy'] as String?,
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
