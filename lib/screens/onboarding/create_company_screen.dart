import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';

class CreateCompanyScreen extends ConsumerStatefulWidget {
  const CreateCompanyScreen({super.key});

  @override
  ConsumerState<CreateCompanyScreen> createState() =>
      _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends ConsumerState<CreateCompanyScreen> {
  final _nameController = TextEditingController();
  bool _loading = false;

  Future<void> _create() async {
    if (_nameController.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) return;
      await ref.read(companyServiceProvider).createCompany(
            name: _nameController.text.trim(),
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
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会社を作成')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '会社名'),
              autofocus: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('作成'),
            ),
          ],
        ),
      ),
    );
  }
}
