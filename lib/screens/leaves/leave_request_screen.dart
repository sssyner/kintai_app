import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/leave_provider.dart';

class LeaveRequestScreen extends ConsumerStatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  ConsumerState<LeaveRequestScreen> createState() =>
      _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends ConsumerState<LeaveRequestScreen> {
  String _type = 'paid';
  DateTime _date = DateTime.now();
  final _reasonController = TextEditingController();
  bool _loading = false;

  static const _types = {
    'paid': '有給休暇',
    'sick': '病欠',
    'half_am': '午前半休',
    'half_pm': '午後半休',
    'absence': '欠勤',
  };

  Future<void> _submit() async {
    final user = ref.read(authStateProvider).valueOrNull;
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    final employee = ref.read(currentEmployeeProvider).valueOrNull;
    if (user == null || companyId == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(leaveServiceProvider).createRequest(
            companyId: companyId,
            userId: user.uid,
            userName: employee?.name ?? user.displayName ?? '',
            type: _type,
            date: DateFormat('yyyy-MM-dd').format(_date),
            reason: _reasonController.text.isNotEmpty
                ? _reasonController.text
                : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('休暇を申請しました')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('休暇申請')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '種類'),
              items: _types.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'paid'),
            ),
            const SizedBox(height: 16),

            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日付'),
              subtitle: Text(DateFormat('yyyy/MM/dd (E)', 'ja').format(_date)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 16),

            // Reason
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: '理由（任意）',
                hintText: '例: 通院のため',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('申請する'),
            ),
          ],
        ),
      ),
    );
  }
}
