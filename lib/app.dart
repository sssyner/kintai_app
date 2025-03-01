import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/screens/auth/login_screen.dart';
import 'package:kintai_app/screens/onboarding/onboarding_screen.dart';
import 'package:kintai_app/screens/home/home_screen.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/theme.dart';

class KintaiApp extends ConsumerWidget {
  const KintaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '勤怠管理',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();
        return const _CompanyGate();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const LoginScreen(),
    );
  }
}

class _CompanyGate extends ConsumerWidget {
  const _CompanyGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyAsync = ref.watch(currentUserCompanyProvider);

    return companyAsync.when(
      data: (companyId) {
        if (companyId == null) return const OnboardingScreen();
        return const HomeScreen();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const OnboardingScreen(),
    );
  }
}
