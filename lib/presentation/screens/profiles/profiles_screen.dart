// lib/presentation/screens/profiles/profiles_screen.dart

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../application/profile/profile_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

// ── Provider (화면 전용) ───────────────────────────────────
final _profilesProvider = FutureProvider.autoDispose<List<Profile>>(
  (ref) => ref.read(profileUseCaseProvider).getAll(),
);

// ── 헤더 배경색 (로컬 상수) ───────────────────────────────
const _headerBgLight = Color(0xFF2d4a22);
const _headerBgDark = Color(0xFF051a0f);

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(_profilesProvider);
    final activeAsync = ref.watch(activeProfileProvider);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final headerBg = isLight ? _headerBgLight : _headerBgDark;

    return Scaffold(
      body: GrainOverlay(
        child: CustomScrollView(
          slivers: [
            // ── 헤더 ──────────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: 100,
              backgroundColor: headerBg,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
                title: Text(
                  '프로필 관리',
                  style: GoogleFonts.gowunBatang(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // ── 본문 ──────────────────────────────────────
            profilesAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(child: Text('오류: $e')),
              ),
              data: (profiles) {
                final activeId = activeAsync.valueOrNull?.id;
                return SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList.separated(
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ProfileCard(
                      profile: profiles[i],
                      isActive: profiles[i].id == activeId,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// _ProfileCard
// ═══════════════════════════════════════════════════════════

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({
    required this.profile,
    required this.isActive,
  });

  final Profile profile;
  final bool isActive;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.profile.name);
  late Color _color = _hexToColor(widget.profile.colorHex);
  bool _editing = false;

  // ── 헬퍼 ────────────────────────────────────────────────

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  // ── 색상 피커 다이얼로그 ──────────────────────────────────
  Future<void> _pickColor() async {
    Color picked = _color;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '색상 선택',
          style: GoogleFonts.gowunBatang(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: picked,
            onColorChanged: (c) => picked = c,
            width: 40,
            height: 40,
            borderRadius: 22,
            spacing: 5,
            runSpacing: 5,
            wheelDiameter: 200,
            heading: Text(
              '테마 색상',
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
            subheading: Text(
              '색조 선택',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            wheelSubheading: Text(
              '직접 선택',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            showMaterialName: false,
            showColorName: false,
            showColorCode: true,
            copyPasteBehavior: const ColorPickerCopyPasteBehavior(
              longPressMenu: true,
            ),
            pickersEnabled: const <ColorPickerType, bool>{
              ColorPickerType.both: false,
              ColorPickerType.primary: true,
              ColorPickerType.accent: false,
              ColorPickerType.bw: false,
              ColorPickerType.custom: false,
              ColorPickerType.wheel: true,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _color = picked);
    }
  }

  // ── 저장 ────────────────────────────────────────────────
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(profileUseCaseProvider).upsert(
          id: widget.profile.id,
          name: name,
          colorHex: _colorToHex(_color),
        );
    ref.invalidate(activeProfileProvider);
    ref.invalidate(_profilesProvider);
    if (mounted) setState(() => _editing = false);
  }

  // ── 활성 전환 ────────────────────────────────────────────
  Future<void> _switchProfile() async {
    await ref.read(profileUseCaseProvider).switchProfile(widget.profile.id);
    ref.invalidate(activeProfileProvider);
    ref.invalidate(_profilesProvider);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 카드 헤더 행 ───────────────────────────────
            Row(
              children: [
                // 색상 아바타
                GestureDetector(
                  onTap: _editing ? _pickColor : null,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: _color,
                        radius: 22,
                        child: _editing
                            ? const Icon(Icons.colorize,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 이름 / 활성 뱃지
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.profile.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (widget.isActive) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '현재 활성',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 편집 토글
                IconButton(
                  icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = !_editing),
                ),
              ],
            ),

            // ── 편집 모드 ──────────────────────────────────
            if (_editing) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '이름',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),

              // 색상 선택 버튼
              OutlinedButton.icon(
                onPressed: _pickColor,
                icon: CircleAvatar(
                  backgroundColor: _color,
                  radius: 10,
                ),
                label: const Text('프로필 색상 변경'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(height: 16),

              // 저장 버튼
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('저장'),
                ),
              ),
            ],

            // ── 뷰 모드 (비편집) — 활성 전환 버튼 ──────────
            if (!_editing && !widget.isActive) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withOpacity(0.4),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _switchProfile,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('이 프로필로 전환'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
