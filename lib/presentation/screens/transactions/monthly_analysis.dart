// lib/presentation/screens/transactions/monthly_analysis.dart
//
// Fortune Garden — 거래 내역 분석 카드
//
// AI API 미사용. 순수 Dart 산술 연산만 사용.
// ref.watch 기반으로 월 변경 시 즉시 갱신.
//
// 구성:
//   MonthlyAnalysis          — 분석 수치 데이터 클래스
//   monthlyAnalysisProvider  — 이번 달 + 전달 데이터를 받아 분석 수치 계산
//   AnalysisCard             — _SummaryPanel에 삽입하는 위젯

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/repositories/transaction_filter.dart';
import '../../../application/transaction/transaction_use_case.dart';
import '../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────
// 변동비 카테고리 ID (Seed 기준 하드코딩)
// 식비(1), 의류(3), 문화/여가(5), 교육(6)
// ─────────────────────────────────────────────────────────
const _flexibleCategoryIds = {1, 3, 5, 6};

// ─────────────────────────────────────────────────────────
// 전달 거래 목록 Provider
// ─────────────────────────────────────────────────────────
final _prevMonthTransactionListProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) {
  final selected = ref.watch(selectedMonthProvider);
  final prev = selected.prev;
  final filter = TransactionFilter(
    fromDate: prev.monthStartMs,
    toDate: prev.monthEndMs,
    limit: 500,
  );
  return ref.read(transactionUseCaseProvider).getList(filter);
});

// ─────────────────────────────────────────────────────────
// MonthlyAnalysis — 분석 수치 데이터 클래스
// ─────────────────────────────────────────────────────────
class MonthlyAnalysis {
  const MonthlyAnalysis({
    required this.spendingPace,
    required this.dailyPace,
    required this.flexibleRatio,
    required this.prevFlexibleRatio,
    required this.peakWeekday,
    required this.peakCategory,
    required this.totalExpense,
    required this.prevSamePeriodExpense,
    required this.daysElapsed,
    required this.daysInMonth,
  });

  /// 지출 속도: (이번 달 누적 / 전달 동기 누적 - 1) * 100
  /// 양수 = 빠름, 음수 = 느림
  final double spendingPace;

  /// 이번 달 남은 일수 기준 일일 평균 지출 페이스 (원)
  /// = 현재 총 지출 / 경과 일수
  final int dailyPace;

  /// 가변적 지출 비중 (%)
  final double flexibleRatio;

  /// 전달 가변적 지출 비중 (%)
  final double prevFlexibleRatio;

  /// 지출이 가장 많은 요일 (1=월 ~ 7=일)
  final int peakWeekday;

  /// 지출이 가장 많은 카테고리명
  final String peakCategory;

  /// 이번 달 총 지출 (절댓값)
  final int totalExpense;

  /// 전달 동기(같은 일수까지) 누적 지출 (절댓값)
  final int prevSamePeriodExpense;

  /// 이번 달 경과 일수
  final int daysElapsed;

  /// 이번 달 총 일수
  final int daysInMonth;

  // ── 해석용 게터 ──────────────────────────────────────

  /// 지출 속도가 빠른지 (전달보다 느리거나 같으면 절약)
  bool get isOverPace => spendingPace > 0;

  /// 가변적 지출 비중이 전달보다 증가했는지
  bool get isFlexibleIncreased => flexibleRatio > prevFlexibleRatio;

  /// 요일 이름 (한국어)
  String get peakWeekdayLabel =>
      ['월', '화', '수', '목', '금', '토', '일'][peakWeekday - 1];
}

// ─────────────────────────────────────────────────────────
// monthlyAnalysisProvider — 분석 수치 계산
// ─────────────────────────────────────────────────────────
final monthlyAnalysisProvider =
    FutureProvider.autoDispose<MonthlyAnalysis?>((ref) async {
  final selected = ref.watch(selectedMonthProvider);
  final thisList = await ref.watch(
    FutureProvider.autoDispose<List<Transaction>>((ref) {
      final filter = TransactionFilter(
        fromDate: selected.monthStartMs,
        toDate: selected.monthEndMs,
        limit: 500,
      );
      return ref.read(transactionUseCaseProvider).getList(filter);
    }).future,
  );
  final prevList = await ref.watch(_prevMonthTransactionListProvider.future);

  // 데이터 없으면 null 반환
  if (thisList.isEmpty) return null;

  final now = DateTime.now();
  final isCurrentMonth = selected.isCurrentMonth;

  // ── 경과 일수 / 이번 달 총 일수 ──────────────────────
  final daysInMonth = DateTime(selected.year, selected.month + 1, 0).day;
  final daysElapsed = isCurrentMonth ? now.day : daysInMonth; // 과거 달이면 전체 일수

  // ── 이번 달 총 지출 ───────────────────────────────────
  final thisExpense = thisList
      .where((t) => t.amount < 0)
      .fold<int>(0, (s, t) => s + t.amount.abs());

  // ── 전달 동기 지출 (같은 일수까지) ───────────────────
  final prevSamePeriod = prevList.where((t) {
    final dt = DateTime.fromMillisecondsSinceEpoch(t.txnDate);
    return t.amount < 0 && dt.day <= daysElapsed;
  }).fold<int>(0, (s, t) => s + t.amount.abs());

  // ── 지출 속도 계산 ────────────────────────────────────
  final double spendingPace =
      prevSamePeriod == 0 ? 0 : ((thisExpense / prevSamePeriod) - 1) * 100;

  // ── 일일 페이스 ───────────────────────────────────────
  final dailyPace = daysElapsed == 0 ? 0 : (thisExpense / daysElapsed).round();

  // ── 가변적 지출 비중 ──────────────────────────────────
  final thisFlexible = thisList
      .where((t) =>
          t.amount < 0 &&
          t.categoryId != null &&
          _flexibleCategoryIds.contains(t.categoryId))
      .fold<int>(0, (s, t) => s + t.amount.abs());

  final flexibleRatio =
      thisExpense == 0 ? 0.0 : (thisFlexible / thisExpense) * 100;

  final prevExpense = prevList
      .where((t) => t.amount < 0)
      .fold<int>(0, (s, t) => s + t.amount.abs());
  final prevFlexible = prevList
      .where((t) =>
          t.amount < 0 &&
          t.categoryId != null &&
          _flexibleCategoryIds.contains(t.categoryId))
      .fold<int>(0, (s, t) => s + t.amount.abs());
  final prevFlexibleRatio =
      prevExpense == 0 ? 0.0 : (prevFlexible / prevExpense) * 100;

  // ── 집중 소비 요일 ────────────────────────────────────
  final weekdayExpense = <int, int>{};
  for (final t in thisList.where((t) => t.amount < 0)) {
    final wd = DateTime.fromMillisecondsSinceEpoch(t.txnDate).weekday;
    weekdayExpense[wd] = (weekdayExpense[wd] ?? 0) + t.amount.abs();
  }
  final peakWeekday = weekdayExpense.isEmpty
      ? 1
      : weekdayExpense.entries.reduce((a, b) => a.value > b.value ? a : b).key;

  // ── 집중 소비 카테고리 ────────────────────────────────
  // categoryId별 지출 집계 → 카테고리 이름 조회
  final catExpense = <int, int>{};
  for (final t in thisList.where((t) => t.amount < 0)) {
    if (t.categoryId != null) {
      catExpense[t.categoryId!] =
          (catExpense[t.categoryId!] ?? 0) + t.amount.abs();
    }
  }

  String peakCategory = '미분류';
  if (catExpense.isNotEmpty) {
    // 카테고리 ID만 알고 있으므로 Seed 기준 이름 매핑
    const categoryNames = {
      1: '식비',
      2: '교통비',
      3: '의류',
      4: '의료/건강',
      5: '문화/여가',
      6: '교육',
      7: '공과금',
      8: '통신',
      9: '금융',
      10: '이체',
      11: '기타',
    };
    final topId =
        catExpense.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    peakCategory = categoryNames[topId] ?? '기타';
  }

  return MonthlyAnalysis(
    spendingPace: spendingPace,
    dailyPace: dailyPace,
    flexibleRatio: flexibleRatio,
    prevFlexibleRatio: prevFlexibleRatio,
    peakWeekday: peakWeekday,
    peakCategory: peakCategory,
    totalExpense: thisExpense,
    prevSamePeriodExpense: prevSamePeriod,
    daysElapsed: daysElapsed,
    daysInMonth: daysInMonth,
  );
});

// ─────────────────────────────────────────────────────────
// AnalysisCard — _SummaryPanel에 삽입하는 위젯
// ─────────────────────────────────────────────────────────
class AnalysisCard extends ConsumerWidget {
  const AnalysisCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(monthlyAnalysisProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 섹션 레이블 ──────────────────────────────────
        Text(
          'ANALYSIS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // ── 카드 본문 ─────────────────────────────────────
        analysisAsync.when(
          loading: () => SizedBox(
            height: 160,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('분석 오류: $e',
                style: TextStyle(fontSize: 12, color: cs.error)),
          ),
          data: (analysis) {
            if (analysis == null) {
              return _AnalysisEmpty();
            }
            return Column(
              children: [
                // 지출 속도 분석
                _PaceSection(
                  analysis: analysis,
                  expenseColor: expenseColor,
                  incomeColor: incomeColor,
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withOpacity(0.4),
                ),
                const SizedBox(height: 16),
                // 지출 구조 분석
                _StructureSection(
                  analysis: analysis,
                  expenseColor: expenseColor,
                  incomeColor: incomeColor,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 지출 속도 분석 섹션
// ─────────────────────────────────────────────────────────
class _PaceSection extends StatelessWidget {
  const _PaceSection({
    required this.analysis,
    required this.expenseColor,
    required this.incomeColor,
  });

  final MonthlyAnalysis analysis;
  final Color expenseColor;
  final Color incomeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,###', 'ko_KR');
    final paceAbs = analysis.spendingPace.abs().toStringAsFixed(1);
    final allowance = fmt.format(analysis.dailyPace);

    final isOver = analysis.isOverPace;
    final statusColor = isOver ? expenseColor : incomeColor;
    final statusIcon = isOver ? Icons.trending_up : Icons.trending_down;

    // ── 문구 생성 ─────────────────────────────────────────
    final headline = isOver ? '지출 속도 주의' : '지출 속도 안정';

    final body = isOver
        ? '현재 지출 속도는 전월 동기 대비 $paceAbs% 빠르게 진행 중입니다. '
            '예산 준수를 위해 향후 일일 평균 $allowance원 이내로 소비 조정을 권장합니다.'
        : '현재 지출 속도는 전월 동기 대비 $paceAbs% 느리게 유지되고 있습니다. '
            '매우 안정적인 흐름이며 현재 패턴 유지 시 여유 자산 확보가 전망됩니다.';

    return _AnalysisTile(
      icon: statusIcon,
      iconColor: statusColor,
      headline: headline,
      headlineColor: statusColor,
      body: body,
      // 수치 배지 — 지출 속도 %
      badge: _PaceBadge(
        value: analysis.spendingPace,
        expenseColor: expenseColor,
        incomeColor: incomeColor,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 지출 구조 분석 섹션
// ─────────────────────────────────────────────────────────
class _StructureSection extends StatelessWidget {
  const _StructureSection({
    required this.analysis,
    required this.expenseColor,
    required this.incomeColor,
  });

  final MonthlyAnalysis analysis;
  final Color expenseColor;
  final Color incomeColor;

  @override
  Widget build(BuildContext context) {
    final ratio = analysis.flexibleRatio.toStringAsFixed(1);
    final isIncreased = analysis.isFlexibleIncreased;
    final statusColor = isIncreased ? expenseColor : incomeColor;
    final statusIcon =
        isIncreased ? Icons.donut_small_outlined : Icons.balance_outlined;

    final headline = isIncreased ? '가변 지출 비중 증가' : '가변 지출 비중 감소';

    final body = isIncreased
        ? '이달 지출의 $ratio%가 가변적 지출에 집중되어 있습니다. '
            '특히 ${analysis.peakWeekdayLabel}요일에 ${analysis.peakCategory} 소비가 '
            '집중되는 경향이 관찰됩니다.'
        : '가변적 지출 비중이 $ratio%로 전월 대비 감소하며 효율적인 자산 운용을 '
            '보여주고 있습니다. 전반적으로 균형 잡힌 소비 패턴이 유지되고 있습니다.';

    return _AnalysisTile(
      icon: statusIcon,
      iconColor: statusColor,
      headline: headline,
      headlineColor: statusColor,
      body: body,
      badge: _RatioBadge(
        ratio: analysis.flexibleRatio,
        prevRatio: analysis.prevFlexibleRatio,
        expenseColor: expenseColor,
        incomeColor: incomeColor,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 공용 분석 타일 레이아웃
// ─────────────────────────────────────────────────────────
class _AnalysisTile extends StatelessWidget {
  const _AnalysisTile({
    required this.icon,
    required this.iconColor,
    required this.headline,
    required this.headlineColor,
    required this.body,
    required this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final String headline;
  final Color headlineColor;
  final String body;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤드라인 행
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                headline,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: headlineColor,
                ),
              ),
            ),
            badge,
          ],
        ),
        const SizedBox(height: 10),
        // 본문 문구
        Text(
          body,
          style: TextStyle(
            fontSize: 12,
            height: 1.65,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 지출 속도 배지
// ─────────────────────────────────────────────────────────
class _PaceBadge extends StatelessWidget {
  const _PaceBadge({
    required this.value,
    required this.expenseColor,
    required this.incomeColor,
  });

  final double value;
  final Color expenseColor;
  final Color incomeColor;

  @override
  Widget build(BuildContext context) {
    final isOver = value > 0;
    final color = isOver ? expenseColor : incomeColor;
    final sign = isOver ? '+' : '';
    final label = '$sign${value.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 가변 지출 비중 배지
// ─────────────────────────────────────────────────────────
class _RatioBadge extends StatelessWidget {
  const _RatioBadge({
    required this.ratio,
    required this.prevRatio,
    required this.expenseColor,
    required this.incomeColor,
  });

  final double ratio;
  final double prevRatio;
  final Color expenseColor;
  final Color incomeColor;

  @override
  Widget build(BuildContext context) {
    final isIncreased = ratio > prevRatio;
    final color = isIncreased ? expenseColor : incomeColor;
    final arrow = isIncreased ? '↑' : '↓';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        '$arrow${ratio.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 데이터 없음 상태
// ─────────────────────────────────────────────────────────
class _AnalysisEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 80,
      child: Center(
        child: Text(
          '이번 달 거래 내역이 없어\n분석을 표시할 수 없습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: cs.onSurfaceVariant.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
