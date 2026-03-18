import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kintai_app/models/chat_room.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _roomsRef(String companyId) =>
      _db.collection('companies').doc(companyId).collection('chatRooms');

  CollectionReference _messagesRef(String companyId, String roomId) =>
      _roomsRef(companyId).doc(roomId).collection('messages');

  /// 全体チャットルームを取得（なければ作成）
  Future<ChatRoom> getOrCreateCompanyRoom(String companyId) async {
    final snap = await _roomsRef(companyId)
        .where('type', isEqualTo: 'company')
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      return ChatRoom.fromFirestore(snap.docs.first);
    }

    final ref = _roomsRef(companyId).doc();
    await ref.set({
      'type': 'company',
      'name': '全体チャット',
      'memberIds': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return ChatRoom.fromFirestore(doc);
  }

  /// グループチャット作成
  Future<ChatRoom> createGroupRoom({
    required String companyId,
    required String name,
    required List<String> memberIds,
  }) async {
    final ref = _roomsRef(companyId).doc();
    await ref.set({
      'type': 'group',
      'name': name,
      'memberIds': memberIds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return ChatRoom.fromFirestore(doc);
  }

  /// チャットルーム一覧（全体＋自分が参加しているグループ）
  Stream<List<ChatRoom>> watchRooms(String companyId, String userId) {
    return _roomsRef(companyId).snapshots().map((snap) {
      final rooms = snap.docs.map(ChatRoom.fromFirestore).where((r) {
        if (r.isCompanyWide) return true;
        return r.memberIds.contains(userId);
      }).toList();
      // 全体チャットを先頭に
      rooms.sort((a, b) {
        if (a.isCompanyWide) return -1;
        if (b.isCompanyWide) return 1;
        final aTime = a.lastMessageAt ?? DateTime(2000);
        final bTime = b.lastMessageAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
      return rooms;
    });
  }

  /// メッセージ取得（リアルタイム）
  Stream<List<ChatMessage>> watchMessages(String companyId, String roomId) {
    return _messagesRef(companyId, roomId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map(ChatMessage.fromFirestore).toList().reversed.toList());
  }

  /// メッセージ送信
  Future<void> sendMessage({
    required String companyId,
    required String roomId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final batch = _db.batch();

    batch.set(_messagesRef(companyId, roomId).doc(), {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ルームのlastMessage更新
    batch.update(_roomsRef(companyId).doc(roomId), {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageBy': senderName,
    });

    await batch.commit();
  }
}
