// lib/presentation/screens/report/report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/entities/view_mode.dart';
import '../../../application/report/report_use_case.dart';
import '../../providers/app_providers.dart';
import '../dashboard/dashboard_charts.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewModeAsync = ref.watch(viewModeProvider);
    final selected = ref.watch(selectedMonthProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: GrainOverlay(
        child: CustomScrollView(
          slivers: [
            // ── 헤더 ────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              floating: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor:
                  isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22),
              title: Text(
                '리포트',
                style: GoogleFonts.newsreader(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: Colors.white,
                ),
              ),
              actions: [
                viewModeAsync.when(
                  data: (mode) => _ViewModeChip(
                    mode: mode,
                    onTap: () => ref.read(viewModeProvider.notifier).setMode(
                          mode == ViewMode.combined
                              ? ViewMode.personal
                              : ViewMode.combined,
                        ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 12),

                  // ── 월 이동 ──────────────────────────────
                  _MonthNavigator(selected: selected, ref: ref),
                  const SizedBox(height: 16),

                  // ── 요약 카드 ────────────────────────────
                  ref.watch(reportSummaryProvider).when(
                        data: (s) => _SummaryCard(summaries: s),
                        loading: () => const _CardSkeleton(height: 120),
                        error: (e, _) => _ErrorCard(message: '$e'),
                      ),
                  const SizedBox(height: 16),

                  // ── 카테고리 탭 (도넛 + 목록) ────────────
                  const _CategorySection(),
                  const SizedBox(height: 16),

                  // ── 월별 추이 바 차트 ─────────────────────
                  _ChartCard(
                    child: ref.watch(monthlyTrendProvider).when(
                          data: (d) => DashboardBarChart(data: d),
                          loading: () => const _ChartLoading(),
                          error: (e, _) => _ChartError(message: '$e'),
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

// ════════════════════════════════════════════════════════════
// 뷰모드 칩
// ════════════════════════════════════════════════════════════

class _ViewModeChip extends StatelessWidget {
  const _ViewModeChip({required this.mode, required this.onTap});
  final ViewMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCombined = mode == ViewMode.combined;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCombined ? Icons.people_outline : Icons.person_outline,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              isCombined ? '통합' : '개인',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 월 이동 바
// ════════════════════════════════════════════════════════════

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({required this.selected, required this.ref});
  final SelectedMonth selected;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canGoNext = !selected.isCurrentMonth;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => ref.read(selectedMonthProvider.notifier).prev(),
          icon: Icon(Icons.chevron_left, color: colorScheme.onSurface),
        ),
        Text(
          DateFormat('yyyy년 M월', 'ko_KR')
              .format(DateTime(selected.year, selected.month)),
          style: GoogleFonts.newsreader(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
            color: colorScheme.onSurface,
          ),
        ),
        IconButton(
          onPressed: canGoNext
              ? () => ref.read(selectedMonthProvider.notifier).next()
              : null,
          icon: Icon(
            Icons.chevron_right,
            color: canGoNext
                ? colorScheme.onSurface
                : colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 요약 카드
// ════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summaries});
  final List<MonthlySummary> summaries;

  String _fmt(int v) => NumberFormat('#,###원', 'ko_KR').format(v.abs());

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;

    final totalIncome = summaries.fold<int>(0, (s, e) => s + e.income);
    final totalExpense = summaries.fold<int>(0, (s, e) => s + e.expense);
    final net = totalIncome + totalExpense;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: '총 수입',
            value: _fmt(totalIncome),
            color: incomeColor,
            icon: Icons.arrow_upward_rounded,
          ),
          Divider(
            height: 20,
            color: colorScheme.outlineVariant.withOpacity(0.4),
          ),
          _SummaryRow(
            label: '총 지출',
            value: _fmt(totalExpense.abs()),
            color: expenseColor,
            icon: Icons.arrow_downward_rounded,
          ),
          Divider(
            height: 20,
            color: colorScheme.outlineVariant.withOpacity(0.4),
          ),
          _SummaryRow(
            label: '순수지',
            value: '${net >= 0 ? '+' : ''}${_fmt(net)}',
            color: net >= 0 ? incomeColor : expenseColor,
            icon: net >= 0
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.bold = false,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 16 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 카테고리 섹션 (수입/지출 탭 + 도넛 차트 + 목록)
// ════════════════════════════════════════════════════════════

class _CategorySection extends ConsumerStatefulWidget {
  const _CategorySection();

  @override
  ConsumerState<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends ConsumerState<_CategorySection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // 0 = 지출(isExpense: true), 1 = 수입(isExpense: false)
        ref.read(reportCategoryExpenseParamProvider.notifier).state =
            _tabController.index == 0;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 탭 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              tabs: const [
                Tab(text: '지출'),
                Tab(text: '수입'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 탭 콘텐츠 — 고정 높이로 TabBarView 감싸기
          SizedBox(
            height: 420,
            child: TabBarView(
              controller: _tabController,
              children: const [
                _CategoryTabContent(isExpense: true),
                _CategoryTabContent(isExpense: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTabContent extends ConsumerWidget {
  const _CategoryTabContent({required this.isExpense});
  final bool isExpense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIsExpense = ref.watch(reportCategoryExpenseParamProvider);
    final async = ref.watch(reportCategoryExpensesProvider);

    // 탭 전환 중 이전 탭 데이터 잠깐 보임 방지
    if (currentIsExpense != isExpense) {
      return const _ChartLoading();
    }

    return async.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _ChartError(message: '$e'),
      data: (data) => _CategoryTabBody(data: data, isExpense: isExpense),
    );
  }
}

class _CategoryTabBody extends StatelessWidget {
  const _CategoryTabBody({required this.data, required this.isExpense});
  final List<CategoryExpense> data;
  final bool isExpense;

  Color _hexToColor(String hex) =>
      Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

  String _fmt(int v) => NumberFormat('#,###원', 'ko_KR').format(v);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (data.isEmpty) {
      return Center(
        child: Text(
          isExpense ? '이번 달 지출 내역이 없습니다' : '이번 달 수입 내역이 없습니다',
          style: TextStyle(fontSize: 13, color: colorScheme.outline),
        ),
      );
    }

    final total = data.fold<int>(0, (s, e) => s + e.totalExpense);
    final amountColor = isExpense
        ? (isDark ? AppTheme.expenseDark : AppTheme.expenseLight)
        : (isDark ? AppTheme.incomeDark : AppTheme.incomeLight);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          // 도넛 차트
          DashboardDonutChart(data: data, isExpense: isExpense),
          const SizedBox(height: 16),
          // 카테고리 목록
          ...data.map((item) {
            final pct = total > 0 ? item.totalExpense / total : 0.0;
            final color = _hexToColor(item.colorHex);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.categoryName,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        '${(pct * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmt(item.totalExpense),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: amountColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // 비율 바
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor:
                          colorScheme.outlineVariant.withOpacity(0.2),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(color.withOpacity(0.8)),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 공용 위젯
// ════════════════════════════════════════════════════════════

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: child,
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 2,
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '오류: $message',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontSize: 12,
          ),
        ),
      );
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 2,
          ),
        ),
      );
}

class _ChartError extends StatelessWidget {
  const _ChartError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: Center(
          child: Text(
            '차트 로드 실패: $message',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
      );
}
