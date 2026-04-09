// lib/presentation/screens/settings/settings_screen.dart
// SCR-010 /settings — 앱 설정

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../providers/pin_notifier.dart';
import '../pin/pin_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinState = ref.watch(pinLockProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          // ── 계정 ────────────────────────────────────────────
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

          // ── 화면 ────────────────────────────────────────────
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

          const Divider(),

          // ── 보안 ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '보안',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),

          // PIN 활성화 토글
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('PIN 잠금'),
            subtitle: Text(
              pinState.isPinEnabled
                  ? '앱 시작 및 백그라운드 복귀 시 PIN 입력'
                  : 'PIN 잠금을 사용하지 않습니다',
            ),
            value: pinState.isPinEnabled,
            onChanged: pinState.isLoading
                ? null
                : (enabled) async {
                    if (enabled) {
                      // PIN 설정 화면으로 이동
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => PinScreen(
                            mode: PinScreenMode.setup,
                          ),
                        ),
                      );
                    } else {
                      // 비활성화 확인
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('PIN 잠금 해제'),
                          content: const Text('PIN 잠금을 비활성화할까요?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('비활성화'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref.read(pinLockProvider.notifier).disablePin();
                      }
                    }
                  },
          ),

          // PIN 변경 (PIN이 활성화된 경우에만 표시)
          if (pinState.isPinEnabled)
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('PIN 변경'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PinScreen(mode: PinScreenMode.change),
                  ),
                );
              },
            ),

          // 자동 잠금 시간 (PIN이 활성화된 경우에만 표시)
          if (pinState.isPinEnabled) const _AutoLockTile(),
        ],
      ),
    );
  }
}

// ── 자동 잠금 시간 설정 타일 ─────────────────────────────────────

class _AutoLockTile extends ConsumerWidget {
  const _AutoLockTile();

  static const _options = [
    (label: '즉시', seconds: 0),
    (label: '30초', seconds: 30),
    (label: '1분', seconds: 60),
    (label: '3분', seconds: 180),
    (label: '5분', seconds: 300),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<String?>(
      stream: ref
          .watch(settingsRepositoryProvider)
          .watchValue('auto_lock_seconds', defaultValue: '30'),
      builder: (context, snap) {
        final currentSeconds = int.tryParse(snap.data ?? '30') ?? 30;
        final currentLabel = _options
            .firstWhere(
              (o) => o.seconds == currentSeconds,
              orElse: () => _options[1],
            )
            .label;

        return ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('자동 잠금'),
          trailing: DropdownButton<int>(
            value: currentSeconds,
            underline: const SizedBox.shrink(),
            items: _options
                .map((o) => DropdownMenuItem(
                      value: o.seconds,
                      child: Text(o.label),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                ref
                    .read(settingsRepositoryProvider)
                    .set('auto_lock_seconds', v.toString());
              }
            },
          ),
        );
      },
    );
  }
}
