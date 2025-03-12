import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/chat_provider.dart';
import 'package:kintai_app/models/chat_room.dart';
import 'package:kintai_app/screens/chat/chat_room_screen.dart';
import 'package:kintai_app/screens/chat/new_group_screen.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCompanyRoom());
  }

  Future<void> _ensureCompanyRoom() async {
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) return;
    await ref.read(chatServiceProvider).getOrCreateCompanyRoom(companyId);
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;

    if (user == null || companyId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_initialized) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final roomsAsync = ref.watch(
        chatRoomsProvider((companyId: companyId, userId: user.uid)));

    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewGroupScreen()),
        ),
        child: const Icon(Icons.group_add),
      ),
      body: roomsAsync.when(
        data: (rooms) {
          if (rooms.isEmpty) {
            return const Center(child: Text('チャットルームがありません'));
          }
          return ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) => _RoomTile(room: rooms[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final ChatRoom room;
  const _RoomTile({required this.room});

  @override
  Widget build(BuildContext context) {
    final timeStr = room.lastMessageAt != null
        ? DateFormat('HH:mm').format(room.lastMessageAt!)
        : '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: room.isCompanyWide
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          room.isCompanyWide ? Icons.business : Icons.group,
          color: room.isCompanyWide
              ? Colors.white
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(room.name),
      subtitle: room.lastMessage != null
          ? Text(
              '${room.lastMessageBy ?? ''}: ${room.lastMessage}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : const Text('メッセージなし', style: TextStyle(color: Colors.grey)),
      trailing: Text(timeStr,
          style: Theme.of(context).textTheme.bodySmall),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            roomId: room.id,
            roomName: room.name,
          ),
        ),
      ),
    );
  }
}
