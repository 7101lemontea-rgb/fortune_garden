// lib/presentation/screens/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/entities/view_mode.dart';
import '../../../application/report/report_use_case.dart';
import '../../providers/app_providers.dart';
import 'dashboard_charts.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final viewModeAsync = ref.watch(viewModeProvider);
    final txListAsync = ref.watch(transactionListProvider);
    final categoryExpAsync = ref.watch(categoryExpensesProvider);
    final monthlyTrendAsync = ref.watch(monthlyTrendProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileName =
        ref.watch(activeProfileProvider).valueOrNull?.name ?? '';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: GrainOverlay(
        child: RefreshIndicator(
          color: isDark ? AppTheme.incomeDark : AppTheme.incomeLight,
          displacement: 80,
          onRefresh: () async {
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(transactionListProvider);
            ref.invalidate(categoryExpensesProvider);
            ref.invalidate(monthlyTrendProvider);
          },
          child: CustomScrollView(
            slivers: [
              // ── 히어로 헤더 ───────────────────────────────
              SliverAppBar(
                expandedHeight: 200,
                collapsedHeight: 60,
                floating: false,
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor:
                    isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22),

                // 1. SliverAppBar의 중앙 정렬 설정
                centerTitle: true,

                // 2. FlexibleSpaceBar 하나로 통합
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true, // 제목을 중앙으로
                  titlePadding:
                      const EdgeInsets.only(bottom: 60), // 접혔을 때 글자 위치 미세 조정
                  title: Text(
                    'Fortune Garden',
                    style: GoogleFonts.newsreader(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                    ),
                  ),
                  collapseMode: CollapseMode.parallax,
                  background: _HeroHeader(
                    profileName: profileName,
                    isDark: isDark,
                  ),
                ),

                actions: [
                  viewModeAsync.when(
                    data: (mode) => _ViewModeChip(
                      mode: mode,
                      profileName: mode == ViewMode.personal
                          ? ref.watch(activeProfileProvider).valueOrNull?.name
                          : null,
                      onTap: () => ref.read(viewModeProvider.notifier).setMode(
                          mode == ViewMode.combined
                              ? ViewMode.personal
                              : ViewMode.combined),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_outline,
                        color: Color.fromARGB(255, 255, 255, 255), size: 22),
                    onPressed: () => context.go('/profiles'),
                  ),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Transform.translate(
                      offset: const Offset(0, 8),
                      child: Column(
                        children: [
                          summaryAsync.when(
                            data: (s) => _SummaryCard(summaries: s),
                            loading: () => const _CardSkeleton(height: 160),
                            error: (e, _) => _ErrorCard(message: '$e'),
                          ),
                          const SizedBox(height: 16),
                          const _MonthNavigator(),
                          const SizedBox(height: 16),
                          _ChartCard(
                            child: categoryExpAsync.when(
                              data: (d) => DashboardDonutChart(data: d),
                              loading: () => const _ChartLoading(),
                              error: (e, _) => _ChartError(message: '$e'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _ChartCard(
                            child: monthlyTrendAsync.when(
                              data: (d) => DashboardBarChart(data: d),
                              loading: () => const _ChartLoading(),
                              error: (e, _) => _ChartError(message: '$e'),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                '최근 거래',
                                style: GoogleFonts.gowunBatang(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => context.go('/transactions'),
                                child: Row(
                                  children: [
                                    Text(
                                      '전체 보기',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Icon(Icons.chevron_right,
                                        size: 16, color: colorScheme.primary),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          txListAsync.when(
                            data: (txns) => txns.isEmpty
                                ? _EmptyTxn(
                                    onImport: () => context.go('/import'))
                                : _TxnList(txns: txns.take(10).toList()),
                            loading: () => const _CardSkeleton(height: 200),
                            error: (e, _) => _ErrorCard(message: '$e'),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/transactions/new'),
        child: const Icon(Icons.add, size: 26),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 히어로 헤더
// ════════════════════════════════════════════════════════════

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.profileName, required this.isDark});
  final String profileName;
  final bool isDark;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '좋은 새벽이에요';
    if (h < 12) return '좋은 아침이에요';
    if (h < 17) return '좋은 오후예요';
    if (h < 21) return '좋은 저녁이에요';
    return '좋은 밤이에요';
  }

  String _greetingEmoji() {
    final h = DateTime.now().hour;
    if (h < 6) return '🌙';
    if (h < 12) return '🌤';
    if (h < 17) return '☀️';
    if (h < 21) return '🌇';
    return '🌙';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = DateFormat('yyyy년 M월 d일 EEEE', 'ko_KR').format(now);
    final bgColor = isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: bgColor),
          Image.asset(
            'assets/images/Group 12.png',
            fit: BoxFit.fitWidth,
            alignment: Alignment.bottomCenter,
          ),
          Positioned(
            left: 150,
            bottom: -20,
            width: 200,
            height: 200,
            child: Lottie.asset(
              'assets/images/Plant_Moving.json',
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
          Positioned(
            right: 100,
            bottom: 0,
            width: 240,
            height: 240,
            child: Lottie.asset(
              'assets/images/Hanging_Plant.json',
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(),
            ),
          ),
          Positioned(
            left: 370,
            right: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(_greetingEmoji(),
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Text(
                      profileName.isNotEmpty ? '${_greeting()}!' : _greeting(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.62),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                // const SizedBox(height: 5),
                // Text(
                //   '가계부',
                //   style: GoogleFonts.gowunBatang(
                //     fontSize: 40,
                //     fontWeight: FontWeight.w700,
                //     fontStyle: FontStyle.italic,
                //     color: Colors.white,
                //     height: 1.0,
                //   ),
                // ),
                const SizedBox(height: 5),
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.48),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 월 이동 바
// ════════════════════════════════════════════════════════════

class _MonthNavigator extends ConsumerWidget {
  const _MonthNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedMonthProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrentMonth = selected.isCurrentMonth;
    final label = DateFormat('yyyy년 M월', 'ko_KR')
        .format(DateTime(selected.year, selected.month));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
        Row(
          children: [
            _NavButton(
              icon: Icons.chevron_left,
              onTap: () => ref.read(selectedMonthProvider.notifier).prev(),
            ),
            const SizedBox(width: 6),
            _NavButton(
              icon: Icons.chevron_right,
              onTap: isCurrentMonth
                  ? null
                  : () => ref.read(selectedMonthProvider.notifier).next(),
              disabled: isCurrentMonth,
            ),
            if (!isCurrentMonth) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => ref.read(selectedMonthProvider.notifier).reset(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: colorScheme.primary.withOpacity(0.35)),
                  ),
                  child: Text(
                    '오늘',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(
      {required this.icon, required this.onTap, this.disabled = false});
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: disabled
              ? colorScheme.surfaceContainerLow
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Icon(icon,
            size: 18,
            color: disabled
                ? colorScheme.outlineVariant
                : colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 뷰 모드 칩
// ════════════════════════════════════════════════════════════

class _ViewModeChip extends StatelessWidget {
  const _ViewModeChip(
      {required this.mode, required this.onTap, this.profileName});
  final ViewMode mode;
  final VoidCallback onTap;
  final String? profileName;

  @override
  Widget build(BuildContext context) {
    final isCombined = mode == ViewMode.combined;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCombined ? Icons.people_outline : Icons.person_outline,
              size: 13,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(width: 4),
            Text(
              isCombined ? '통합' : (profileName ?? '개인'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 요약 카드
// ════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summaries});
  final List<MonthlySummary> summaries;

  String _fmt(int amount) =>
      NumberFormat('#,###', 'ko_KR').format(amount.abs());

  String _compact(int amount) {
    final a = amount.abs();
    if (a >= 100000000) return '${(a / 100000000).toStringAsFixed(1)}억';
    if (a >= 10000) return '${(a / 10000).toStringAsFixed(0)}만';
    return NumberFormat('#,###', 'ko_KR').format(a);
  }

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final income = summaries.fold<int>(0, (s, e) => s + e.income);
    final expense = summaries.fold<int>(0, (s, e) => s + e.expense);
    final net = income + expense;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final netColor = net >= 0 ? incomeColor : expenseColor;
    final cardBg = isDark ? const Color(0xFF1a3d2b) : Colors.white;
    final pillBg = isDark ? const Color(0xFF0d2a1d) : const Color(0xFFF7F4EB);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 달 순수지',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${net >= 0 ? '+' : '-'}${_compact(net)}',
                      style: GoogleFonts.gowunBatang(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: netColor,
                        height: 1.0,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 4),
                      child: Text(
                        '원',
                        style: TextStyle(
                          fontSize: 13,
                          color: netColor.withOpacity(0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  net >= 0 ? '수입이 지출보다 많아요 👍' : '지출이 수입보다 많아요',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryPill(
                        label: '수입',
                        value: _compact(income),
                        color: incomeColor,
                        bgColor: pillBg,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryPill(
                        label: '지출',
                        value: _compact(expense),
                        color: expenseColor,
                        bgColor: pillBg,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (summaries.length > 1) ...[
            Divider(
                height: 1, color: colorScheme.outlineVariant.withOpacity(0.28)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Column(
                children: summaries.map((s) {
                  final c = Color(int.parse(
                      'FF${s.colorHex.replaceAll('#', '')}',
                      radix: 16));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: c, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(s.profileName,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface)),
                        const Spacer(),
                        Text('+${_fmt(s.income)}원',
                            style: TextStyle(
                                color: incomeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Text('-${_fmt(s.expense)}원',
                            style: TextStyle(
                                color: expenseColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: color.withOpacity(0.72),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.1)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1, left: 2),
                    child: Text('원',
                        style: TextStyle(
                            fontSize: 10,
                            color: color.withOpacity(0.62),
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 차트 카드 컨테이너
// ════════════════════════════════════════════════════════════

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a3d2b) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.38)),
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════
// 거래 목록
// ════════════════════════════════════════════════════════════

class _TxnList extends StatelessWidget {
  const _TxnList({required this.txns});
  final List<Transaction> txns;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a3d2b) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.38)),
      ),
      child: Column(
        children: txns.asMap().entries.map((entry) {
          final i = entry.key;
          final txn = entry.value;
          return Column(
            children: [
              _TxnTile(txn: txn),
              if (i < txns.length - 1)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withOpacity(0.2),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final Transaction txn;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(txn.txnDate);
    final isExpense = txn.amount < 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = isExpense
        ? (isDark ? AppTheme.expenseDark : AppTheme.expenseLight)
        : (isDark ? AppTheme.incomeDark : AppTheme.incomeLight);
    final iconBg = isDark ? const Color(0xFF0d2a1d) : const Color(0xFFF2EFE6);

    return InkWell(
      onTap: () => context.go('/transactions/${txn.id}'),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isExpense
                    ? Icons.shopping_bag_outlined
                    : Icons.savings_outlined,
                size: 17,
                color: amountColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('M월 d일 (E)', 'ko_KR').format(dt),
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isExpense ? '-' : '+'}${NumberFormat('#,###', 'ko_KR').format(txn.amount.abs())}',
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '원',
                  style: TextStyle(
                      fontSize: 10,
                      color: amountColor.withOpacity(0.58),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 빈 상태
// ════════════════════════════════════════════════════════════

class _EmptyTxn extends StatelessWidget {
  const _EmptyTxn({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.32)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined,
              size: 44, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text('거래 내역이 없습니다',
              style: TextStyle(fontSize: 14, color: colorScheme.outline)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('CSV 가져오기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 공용 로딩 / 에러 위젯
// ════════════════════════════════════════════════════════════

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('오류: $message',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12)),
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
          child: Text('차트 로드 실패: $message',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ),
      );
}
