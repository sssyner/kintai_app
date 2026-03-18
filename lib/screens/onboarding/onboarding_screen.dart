import 'package:flutter/material.dart';
import 'package:kintai_app/screens/onboarding/create_company_screen.dart';
import 'package:kintai_app/screens/onboarding/join_company_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.business,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('会社を設定',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('新しい会社を作成するか、招待コードで参加してください',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateCompanyScreen()),
                  ),
                  icon: const Icon(Icons.add_business),
                  label: const Text('会社を作成（管理者）'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const JoinCompanyScreen()),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  icon: const Icon(Icons.group_add),
                  label: const Text('招待コードで参加'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
