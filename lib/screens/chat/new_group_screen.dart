import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/chat_provider.dart';
import 'package:kintai_app/widgets/employee_avatar.dart';
import 'package:kintai_app/screens/chat/chat_room_screen.dart';

class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _nameController = TextEditingController();
  final _selectedIds = <String>{};
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('グループ名とメンバーを選択してください')),
      );
      return;
    }

    final user = ref.read(authStateProvider).valueOrNull;
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (user == null || companyId == null) return;

    // 自分も含める
    final members = {..._selectedIds, user.uid}.toList();

    setState(() => _creating = true);
    try {
      final room = await ref.read(chatServiceProvider).createGroupRoom(
            companyId: companyId,
            name: name,
            memberIds: members,
          );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              roomId: room.id,
              roomName: room.name,
            ),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;

    if (user == null || companyId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final employeesAsync = ref.watch(employeesProvider(companyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('グループ作成'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('作成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'グループ名',
                hintText: '例: 営業チーム',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('メンバーを選択',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: employeesAsync.when(
              data: (employees) {
                final others =
                    employees.where((e) => e.userId != user.uid).toList();
                if (others.isEmpty) {
                  return const Center(child: Text('他のメンバーがいません'));
                }
                return ListView.builder(
                  itemCount: others.length,
                  itemBuilder: (context, i) {
                    final emp = others[i];
                    final selected = _selectedIds.contains(emp.userId);
                    return CheckboxListTile(
                      secondary: EmployeeAvatar(employee: emp),
                      title: Text(emp.name),
                      subtitle: Text(emp.email),
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(emp.userId);
                          } else {
                            _selectedIds.remove(emp.userId);
                          }
                        });
                      },
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('エラー: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
