// lib/presentation/screens/accounts/accounts_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../application/profile/profile_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';

// ── Provider (화면 전용) ───────────────────────────────────
final _accountsProvider =
    FutureProvider.autoDispose<List<Account>>((ref) async {
  final profile =
      await ref.read(profileUseCaseProvider).getActiveProfile();
  if (profile == null) return [];
  return ref.read(accountRepositoryProvider).getByProfile(profile.id);
});

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(_accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('계좌 관리')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('오류: $e')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(child: Text('등록된 계좌가 없습니다'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            itemBuilder: (ctx, i) {
              final a = accounts[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(a.alias ?? a.institutionCode),
                  subtitle: Text(a.institutionCode),
                  trailing: Text(
                    '${NumberFormat('#,###', 'ko_KR').format(a.balance)}원',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  onTap: () => context.go('/import'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
