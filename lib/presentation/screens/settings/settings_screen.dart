// lib/presentation/screens/settings/settings_screen.dart
// SCR-010 /settings — 앱 설정

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repository_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('프로필 관리'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profiles'),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('카테고리 설정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/categories'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('계좌 관리'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/accounts'),
          ),
          const Divider(),
          StreamBuilder<String?>(
            stream: ref
                .watch(settingsRepositoryProvider)
                .watchValue('theme', defaultValue: 'system'),
            builder: (context, snap) {
              final val = snap.data ?? 'system';
              return ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('테마'),
                trailing: DropdownButton<String>(
                  value: val,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('시스템')),
                    DropdownMenuItem(value: 'light', child: Text('라이트')),
                    DropdownMenuItem(value: 'dark', child: Text('다크')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(settingsRepositoryProvider).set('theme', v);
                    }
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
