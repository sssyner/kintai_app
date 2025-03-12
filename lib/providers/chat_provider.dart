import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/models/chat_room.dart';
import 'package:kintai_app/services/chat_service.dart';

final chatServiceProvider = Provider((ref) => ChatService());

final chatRoomsProvider = StreamProvider.family<List<ChatRoom>,
    ({String companyId, String userId})>((ref, params) {
  return ref
      .read(chatServiceProvider)
      .watchRooms(params.companyId, params.userId);
});

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>,
    ({String companyId, String roomId})>((ref, params) {
  return ref
      .read(chatServiceProvider)
      .watchMessages(params.companyId, params.roomId);
});
