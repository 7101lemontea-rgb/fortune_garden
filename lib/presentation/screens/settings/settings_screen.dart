// lib/presentation/screens/settings/settings_screen.dart
// SCR-010 /settings — 앱 설정

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/pin_notifier.dart';
import '../pin/pin_screen.dart';

// ─────────────────────────────────────────────────────────
// SCR-010 메인 화면
// ─────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _headerBgLight = Color(0xFF2d4a22);
  static const _headerBgDark = Color(0xFF051a0f);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinState = ref.watch(pinLockProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? _headerBgDark : _headerBgLight;

    return Scaffold(
      body: GrainOverlay(
        child: CustomScrollView(
          slivers: [
            // ── SliverAppBar ────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: headerBg,
              foregroundColor: Colors.white,
              title: Text(
                '설정',
                style: GoogleFonts.newsreader(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),

            // ── 본문 ────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── 관리 섹션 ──────────────────────────────
                  _SectionLabel('관리'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _NavTile(
                      icon: Icons.person_outline,
                      label: '프로필 관리',
                      onTap: () => context.go('/profiles'),
                    ),
                    _Divider(),
                    _NavTile(
                      icon: Icons.category_outlined,
                      label: '카테고리 설정',
                      onTap: () => context.go('/categories'),
                    ),
                    _Divider(),
                    _NavTile(
                      icon: Icons.account_balance_outlined,
                      label: '계좌 관리',
                      onTap: () => context.go('/accounts'),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── 화면 섹션 ──────────────────────────────
                  _SectionLabel('화면'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _ThemeTile(ref: ref),
                  ]),

                  const SizedBox(height: 24),

                  // ── 보안 섹션 ──────────────────────────────
                  _SectionLabel('보안'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _PinToggleTile(pinState: pinState, ref: ref),
                    if (pinState.isPinEnabled) ...[
                      _Divider(),
                      _NavTile(
                        icon: Icons.password_outlined,
                        label: 'PIN 변경',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PinScreen(mode: PinScreenMode.change),
                          ),
                        ),
                      ),
                      _Divider(),
                      _AutoLockTile(ref: ref),
                    ],
                  ]),

                  const SizedBox(height: 24),

                  // ── 백업 섹션 ──────────────────────────────
                  _SectionLabel('백업'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _NavTile(
                      icon: Icons.upload_outlined,
                      label: 'DB 내보내기',
                      subtitle: '현재 데이터를 파일로 저장합니다',
                      onTap: () => _exportDb(context),
                    ),
                    _Divider(),
                    _NavTile(
                      icon: Icons.download_outlined,
                      label: 'DB 가져오기',
                      subtitle: '백업 파일로 데이터를 복원합니다',
                      onTap: () => _importDb(context, ref),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── 앱 정보 ────────────────────────────────
                  _SectionLabel('앱 정보'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _InfoTile(
                      icon: Icons.info_outline,
                      label: 'Fortune Garden',
                      value: 'v1.0.0',
                    ),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DB 내보내기 ─────────────────────────────────────────

  Future<void> _exportDb(BuildContext context) async {
    try {
      final dbFile = await _getDbFile();
      if (!dbFile.existsSync()) {
        _showSnack(context, 'DB 파일을 찾을 수 없습니다.');
        return;
      }

      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'fortune_garden_$now.db';

      if (Platform.isAndroid) {
        // Android: Downloads 폴더에 복사
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (!downloadsDir.existsSync()) {
          _showSnack(context, 'Downloads 폴더에 접근할 수 없습니다.');
          return;
        }
        final dest = File(p.join(downloadsDir.path, fileName));
        await dbFile.copy(dest.path);
        if (context.mounted) {
          _showSnack(context, 'Downloads/$fileName 에 저장되었습니다.');
        }
      } else if (Platform.isWindows) {
        // Windows: 저장 위치 선택
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'DB 백업 파일 저장',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['db'],
        );
        if (savePath == null) return; // 취소
        await dbFile.copy(savePath);
        if (context.mounted) {
          _showSnack(context, '저장 완료: $savePath');
        }
      } else {
        // 기타 플랫폼: 앱 Documents 내 복사
        final docsDir = await getApplicationDocumentsDirectory();
        final dest = File(p.join(docsDir.path, fileName));
        await dbFile.copy(dest.path);
        if (context.mounted) {
          _showSnack(context, '$fileName 에 저장되었습니다.');
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, '내보내기 실패: $e');
      }
    }
  }

  // ── DB 가져오기 ─────────────────────────────────────────

  Future<void> _importDb(BuildContext context, WidgetRef ref) async {
    // 경고 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DB 가져오기'),
        content: const Text(
          '현재 모든 데이터가 백업 파일로 교체됩니다.\n'
          '기존 데이터는 자동으로 백업된 후 덮어씌워집니다.\n\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('가져오기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // 파일 선택
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'DB 백업 파일 선택',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (result == null || result.files.single.path == null) return;

      final srcFile = File(result.files.single.path!);
      final dbFile = await _getDbFile();

      // 기존 DB 백업
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupPath = '${dbFile.path}.bak_$now';
      if (dbFile.existsSync()) {
        await dbFile.copy(backupPath);
      }

      // 파일 교체
      await srcFile.copy(dbFile.path);

      if (context.mounted) {
        _showRestartDialog(context);
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, '가져오기 실패: $e');
      }
    }
  }

  // ── 재시작 안내 다이얼로그 ───────────────────────────────

  void _showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('가져오기 완료'),
        content: const Text(
          'DB 파일이 교체되었습니다.\n'
          '변경 사항을 적용하려면 앱을 재시작해 주세요.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              exit(0); // 앱 종료 (재시작 유도)
            },
            child: const Text('앱 종료'),
          ),
        ],
      ),
    );
  }

  // ── 헬퍼 ────────────────────────────────────────────────

  Future<File> _getDbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'fortune_garden.db'));
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 공통 UI 컴포넌트
// ─────────────────────────────────────────────────────────

/// 섹션 레이블
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.primary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

/// 카드형 그룹 컨테이너
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

/// 카드 내부 구분선
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 52,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
    );
  }
}

/// 네비게이션 타일 (→ 이동)
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: Icon(Icons.chevron_right,
          size: 20, color: cs.onSurfaceVariant.withOpacity(0.6)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

/// 정보 표시 타일 (값만 표시, 탭 없음)
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 테마 선택 타일
// ─────────────────────────────────────────────────────────

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.ref});
  final WidgetRef ref;

  static const _options = [
    (value: 'system', label: '시스템'),
    (value: 'light', label: '라이트'),
    (value: 'dark', label: '다크'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<String?>(
      stream: ref
          .watch(settingsRepositoryProvider)
          .watchValue('theme', defaultValue: 'system'),
      builder: (context, snap) {
        final val = snap.data ?? 'system';

        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.palette_outlined,
                size: 20, color: cs.onSurfaceVariant),
          ),
          title: Text('테마', style: Theme.of(context).textTheme.bodyMedium),
          trailing: _ThemeSegmentedButton(
            value: val,
            options: _options,
            onChanged: (v) =>
                ref.read(settingsRepositoryProvider).set('theme', v),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        );
      },
    );
  }
}

class _ThemeSegmentedButton extends StatelessWidget {
  const _ThemeSegmentedButton({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<({String value, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: options
          .map((o) => ButtonSegment(value: o.value, label: Text(o.label)))
          .toList(),
      selected: {value},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) onChanged(set.first);
      },
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// PIN 토글 타일
// ─────────────────────────────────────────────────────────

class _PinToggleTile extends ConsumerWidget {
  const _PinToggleTile({required this.pinState, required this.ref});
  final PinLockState pinState;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final cs = Theme.of(context).colorScheme;

    return SwitchListTile(
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.lock_outline, size: 20, color: cs.onSurfaceVariant),
      ),
      title: Text('PIN 잠금', style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        pinState.isPinEnabled
            ? '앱 시작 및 백그라운드 복귀 시 PIN 입력'
            : 'PIN 잠금을 사용하지 않습니다',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: pinState.isPinEnabled,
      onChanged: pinState.isLoading
          ? null
          : (enabled) async {
              if (enabled) {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PinScreen(mode: PinScreenMode.setup),
                  ),
                );
              } else {
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
                  await widgetRef.read(pinLockProvider.notifier).disablePin();
                }
              }
            },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 자동 잠금 타일
// ─────────────────────────────────────────────────────────

class _AutoLockTile extends ConsumerWidget {
  const _AutoLockTile({required this.ref});
  final WidgetRef ref;

  static const _options = [
    (label: '즉시', seconds: 0),
    (label: '30초', seconds: 30),
    (label: '1분', seconds: 60),
    (label: '3분', seconds: 180),
    (label: '5분', seconds: 300),
  ];

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<String?>(
      stream: widgetRef
          .watch(settingsRepositoryProvider)
          .watchValue('auto_lock_seconds', defaultValue: '30'),
      builder: (context, snap) {
        final currentSeconds = int.tryParse(snap.data ?? '30') ?? 30;

        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.timer_outlined,
                size: 20, color: cs.onSurfaceVariant),
          ),
          title: Text('자동 잠금', style: Theme.of(context).textTheme.bodyMedium),
          trailing: DropdownButton<int>(
            value: _options.any((o) => o.seconds == currentSeconds)
                ? currentSeconds
                : 30,
            underline: const SizedBox.shrink(),
            isDense: true,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurface),
            items: _options
                .map((o) => DropdownMenuItem(
                      value: o.seconds,
                      child: Text(o.label),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                widgetRef
                    .read(settingsRepositoryProvider)
                    .set('auto_lock_seconds', v.toString());
              }
            },
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        );
      },
    );
  }
}
