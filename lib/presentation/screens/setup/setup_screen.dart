// lib/presentation/screens/setup/setup_screen.dart
// SCR-001 /setup — 초기 설정/프로필 생성

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../application/profile/profile_use_case.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const _headerBgLight = Color(0xFF2d4a22);
  static const _headerBgDark = Color(0xFF051a0f);

  final _p1NameCtrl = TextEditingController(text: '나');
  final _p2NameCtrl = TextEditingController(text: '파트너');
  Color _p1Color = const Color(0xFF3A5A40);
  Color _p2Color = const Color(0xFF415A77);
  bool _saving = false;

  // 프로필 1 이름 유효성 오류 메시지
  String? _p1NameError;

  @override
  void dispose() {
    _p1NameCtrl.dispose();
    _p2NameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 유효성 검사
    final p1Name = _p1NameCtrl.text.trim();
    if (p1Name.isEmpty) {
      setState(() => _p1NameError = '이름을 입력해주세요');
      return;
    }
    setState(() {
      _p1NameError = null;
      _saving = true;
    });

    try {
      final useCase = ref.read(profileUseCaseProvider);

      await useCase.upsert(
        id: 1,
        name: p1Name,
        colorHex: _colorToHex(_p1Color),
      );
      await useCase.upsert(
        id: 2,
        name: _p2NameCtrl.text.trim().isEmpty ? '파트너' : _p2NameCtrl.text.trim(),
        colorHex: _colorToHex(_p2Color),
      );

      // active_profile_id를 1로 명시 설정
      await useCase.switchProfile(1);

      // activeProfileProvider 갱신 → go_router redirect가 /dashboard로 이동
      ref.invalidate(activeProfileProvider);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? _headerBgDark : _headerBgLight;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: GrainOverlay(
        child: CustomScrollView(
          slivers: [
            // ── SliverAppBar ──────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: headerBg,
              foregroundColor: Colors.white,
              expandedHeight: 140,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fortune Garden',
                      style: GoogleFonts.newsreader(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '시작하기 전에 프로필을 설정해주세요',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
                background: Container(color: headerBg),
              ),
            ),

            // ── 본문 ──────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── 안내 배너 ──────────────────────────────
                  _InfoBanner(isDark: isDark),
                  const SizedBox(height: 24),

                  // ── 섹션 레이블 ────────────────────────────
                  _SectionLabel('프로필 설정'),
                  const SizedBox(height: 8),
                  Text(
                    '두 사람의 이름과 구분 색상을 입력해주세요.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),

                  // ── 프로필 1 카드 ──────────────────────────
                  _ProfileCard(
                    label: '프로필 1 (나)',
                    controller: _p1NameCtrl,
                    color: _p1Color,
                    nameError: _p1NameError,
                    onColorChanged: (c) => setState(() => _p1Color = c),
                    onNameChanged: (_) {
                      if (_p1NameError != null) {
                        setState(() => _p1NameError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // ── 프로필 2 카드 ──────────────────────────
                  _ProfileCard(
                    label: '프로필 2 (파트너)',
                    controller: _p2NameCtrl,
                    color: _p2Color,
                    onColorChanged: (c) => setState(() => _p2Color = c),
                  ),
                  const SizedBox(height: 32),

                  // ── 계좌 등록 안내 ─────────────────────────
                  _AccountGuide(isDark: isDark, cs: cs),
                  const SizedBox(height: 32),

                  // ── 시작하기 버튼 ──────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              '시작하기',
                              style: GoogleFonts.newsreader(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 안내 배너
// ─────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.eco_outlined, size: 22, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fortune Garden에 오신 것을 환영합니다',
                  style: GoogleFonts.newsreader(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '2인 가구를 위한 가계부 앱입니다. 각자의 거래를 분리하거나 함께 볼 수 있습니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 섹션 레이블
// ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 프로필 카드
// ─────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.label,
    required this.controller,
    required this.color,
    required this.onColorChanged,
    this.nameError,
    this.onNameChanged,
  });

  final String label;
  final TextEditingController controller;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final String? nameError;
  final ValueChanged<String>? onNameChanged;

  // 커스텀 팔레트
  static const _palette = [
    Color(0xFF3A5A40), // 포레스트 그린
    Color(0xFF415A77), // 스틸 블루
    Color(0xFF9F86C0), // 소프트 퍼플
    Color(0xFFE0B1CB), // 블러쉬 핑크
    Color(0xFFBB8588), // 로즈 모브
    Color(0xFF92898A), // 웜 그레이
    Color(0xFFC6AC8F), // 샌드 베이지
    Color(0xFFCCBCBC), // 미스티 로즈
    Color(0xFFF5D491), // 소프트 골드
    Color(0xFFA1C181), // 세이지 그린
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 카드 헤더: 컬러 프리뷰 + 레이블
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 이름 입력
            TextField(
              controller: controller,
              onChanged: onNameChanged,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                labelText: '이름',
                errorText: nameError,
                prefixIcon: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 색상 레이블
            Text(
              '구분 색상',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),

            // 색상 팔레트
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette.map((c) {
                final isSelected = color == c;
                return GestureDetector(
                  onTap: () => onColorChanged(c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: isDark ? Colors.white : Colors.black87,
                              width: 2.5,
                            )
                          : Border.all(
                              color: cs.outlineVariant.withOpacity(0.4),
                              width: 1,
                            ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: c.withOpacity(0.45),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: _contrastColor(c),
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // 배경 색에 따른 체크 아이콘 색상 (밝기 기준)
  Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.35 ? Colors.black87 : Colors.white;
  }
}

// ─────────────────────────────────────────────────────────
// 계좌 등록 안내
// ─────────────────────────────────────────────────────────

class _AccountGuide extends StatelessWidget {
  const _AccountGuide({required this.isDark, required this.cs});
  final bool isDark;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('계좌 등록 안내'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _GuideItem(
                  step: '1',
                  icon: Icons.check_circle_outline,
                  title: '프로필 설정 완료',
                  subtitle: '아래 시작하기 버튼을 누르면 완료됩니다.',
                  cs: cs,
                  done: true,
                ),
                _GuideDivider(cs: cs),
                _GuideItem(
                  step: '2',
                  icon: Icons.account_balance_outlined,
                  title: '계좌 추가',
                  subtitle: '설정 → 계좌 관리에서 은행/카드 계좌를 등록하세요.',
                  cs: cs,
                ),
                _GuideDivider(cs: cs),
                _GuideItem(
                  step: '3',
                  icon: Icons.upload_file_outlined,
                  title: 'CSV 파일 가져오기',
                  subtitle: '은행 앱에서 내보낸 CSV를 가져와 거래 내역을 불러오세요.',
                  cs: cs,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cs,
    this.done = false,
  });

  final String step;
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme cs;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final activeColor = done ? cs.primary.withOpacity(0.6) : cs.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: activeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: activeColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: done ? cs.onSurfaceVariant : cs.onSurface,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuideDivider extends StatelessWidget {
  const _GuideDivider({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, top: 6, bottom: 6),
      child: Container(
        width: 1,
        height: 16,
        color: cs.outlineVariant.withOpacity(0.5),
      ),
    );
  }
}
