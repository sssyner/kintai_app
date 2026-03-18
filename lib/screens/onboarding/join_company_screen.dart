import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';

class JoinCompanyScreen extends ConsumerStatefulWidget {
  const JoinCompanyScreen({super.key});

  @override
  ConsumerState<JoinCompanyScreen> createState() => _JoinCompanyScreenState();
}

class _JoinCompanyScreenState extends ConsumerState<JoinCompanyScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;

  Future<void> _join() async {
    if (_codeController.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) return;
      await ref.read(companyServiceProvider).joinCompany(
            inviteCode: _codeController.text.trim(),
            uid: user.uid,
            userName: user.displayName ?? user.email?.split('@').first ?? '',
            userEmail: user.email ?? '',
          );
      ref.invalidate(currentUserCompanyProvider);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on Exception catch (e) {
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
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('招待コードで参加')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: '招待コード',
                hintText: '例: A1B2C3D4',
              ),
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _join,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('参加'),
            ),
          ],
        ),
      ),
    );
  }
}
