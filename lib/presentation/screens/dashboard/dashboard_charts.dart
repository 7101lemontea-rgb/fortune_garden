// lib/presentation/screens/dashboard/dashboard_charts.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';

// ════════════════════════════════════════════════════════════
// DonutChart — 카테고리별 지출 비율
// ════════════════════════════════════════════════════════════

class DashboardDonutChart extends StatefulWidget {
  const DashboardDonutChart({
    super.key,
    required this.data,
    this.isExpense = true, // ★ v1.4: false이면 수입 도넛
  });
  final List<CategoryExpense> data;
  final bool isExpense;

  @override
  State<DashboardDonutChart> createState() => _DashboardDonutChartState();
}

class _DashboardDonutChartState extends State<DashboardDonutChart> {
  int _touchedIndex = -1;

  List<CategoryExpense> get _slices {
    if (widget.data.isEmpty) return [];
    final sorted = [...widget.data]
      ..sort((a, b) => b.totalExpense.compareTo(a.totalExpense));
    if (sorted.length <= 5) return sorted;

    final top5 = sorted.take(5).toList();
    final otherExpense =
        sorted.skip(5).fold<int>(0, (s, e) => s + e.totalExpense);
    return [
      ...top5,
      CategoryExpense(
        categoryId: null,
        categoryName: '기타',
        colorHex: '#8B9D77',
        totalExpense: otherExpense,
      ),
    ];
  }

  Color _hexToColor(String hex) =>
      Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

  String _fmt(int amount) => NumberFormat('#,###', 'ko_KR').format(amount);

  @override
  Widget build(BuildContext context) {
    final slices = _slices;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (slices.isEmpty) {
      return _ChartEmpty(
        message: widget.isExpense ? '이번 달 지출 내역이 없습니다' : '이번 달 수입 내역이 없습니다',
      );
    }

    final total = slices.fold<int>(0, (s, e) => s + e.totalExpense);
    final touched = _touchedIndex >= 0 && _touchedIndex < slices.length
        ? slices[_touchedIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartTitle(
          icon: Icons.donut_large_outlined,
          title: widget.isExpense ? '카테고리별 지출' : '카테고리별 수입',
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 210,
          child: Row(
            children: [
              // ── 도넛 ──────────────────────────────────
              Expanded(
                flex: 5,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2.5,
                        centerSpaceRadius: 46,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions ||
                                response == null ||
                                response.touchedSection == null) {
                              setState(() => _touchedIndex = -1);
                              return;
                            }
                            setState(() => _touchedIndex =
                                response.touchedSection!.touchedSectionIndex);
                          },
                        ),
                        sections: List.generate(slices.length, (i) {
                          final s = slices[i];
                          final isTouched = i == _touchedIndex;
                          final pct =
                              total > 0 ? s.totalExpense / total * 100 : 0.0;
                          return PieChartSectionData(
                            value: s.totalExpense.toDouble(),
                            color: _hexToColor(s.colorHex)
                                .withOpacity(isTouched ? 1.0 : 0.88),
                            radius: isTouched ? 60 : 50,
                            title: pct >= 9 ? '${pct.toStringAsFixed(0)}%' : '',
                            titleStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                    color: Colors.black26,
                                    blurRadius: 2,
                                    offset: Offset(0, 1))
                              ],
                            ),
                          );
                        }),
                      ),
                      swapAnimationDuration: const Duration(milliseconds: 300),
                    ),
                    // ── 중앙 총합 표시 ───────────────────
                    if (touched == null)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.isExpense ? '총 지출' : '총 수입',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.outline,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _fmtCompact(total),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: widget.isExpense
                                  ? (isDark
                                      ? AppTheme.expenseDark
                                      : AppTheme.expenseLight)
                                  : (isDark
                                      ? AppTheme.incomeDark
                                      : AppTheme.incomeLight),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // ── 범례 or 상세 ──────────────────────────
              Expanded(
                flex: 5,
                child: touched != null
                    ? _DonutDetail(
                        item: touched,
                        total: total,
                        hexToColor: _hexToColor,
                        fmt: _fmt,
                      )
                    : _DonutLegend(
                        slices: slices,
                        total: total,
                        hexToColor: _hexToColor,
                        fmt: _fmt,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtCompact(int amount) {
    if (amount >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(1)}천만원';
    }
    if (amount >= 10000) {
      return '${(amount / 10000).toStringAsFixed(0)}만원';
    }
    return '${NumberFormat('#,###', 'ko_KR').format(amount)}원';
  }
}

class _DonutLegend extends StatelessWidget {
  const _DonutLegend({
    required this.slices,
    required this.total,
    required this.hexToColor,
    required this.fmt,
  });

  final List<CategoryExpense> slices;
  final int total;
  final Color Function(String) hexToColor;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: slices.map((s) {
        final pct = total > 0 ? s.totalExpense / total * 100 : 0.0;
        final color = hexToColor(s.colorHex);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  s.categoryName,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DonutDetail extends StatelessWidget {
  const _DonutDetail({
    required this.item,
    required this.total,
    required this.hexToColor,
    required this.fmt,
  });

  final CategoryExpense item;
  final int total;
  final Color Function(String) hexToColor;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? item.totalExpense / total * 100 : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final colorScheme = Theme.of(context).colorScheme;
    final color = hexToColor(item.colorHex);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          item.categoryName,
          style: GoogleFonts.newsreader(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          '${fmt(item.totalExpense)}원',
          style: TextStyle(
            color: expenseColor,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${pct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// BarChart — 월별 수입/지출 추이
// ════════════════════════════════════════════════════════════

class DashboardBarChart extends StatelessWidget {
  const DashboardBarChart({super.key, required this.data});
  final List<MonthlyTrend> data;

  String _fmtY(int amount) {
    if (amount >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(0)}천만';
    }
    if (amount >= 10000) return '${(amount / 10000).toStringAsFixed(0)}만';
    return NumberFormat('#,###', 'ko_KR').format(amount);
  }

  String _fmtTooltip(int amount) =>
      NumberFormat('#,###', 'ko_KR').format(amount);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _ChartEmpty(message: '거래 내역이 없습니다');

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;

    final maxVal = data
        .expand((d) => [d.income, d.expense])
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ChartTitle(icon: Icons.bar_chart_outlined, title: '월별 수입/지출'),
            Row(
              children: [
                _LegendDot(color: incomeColor, label: '수입'),
                const SizedBox(width: 14),
                _LegendDot(color: expenseColor, label: '지출'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxVal > 0 ? maxVal * 1.3 : 100000,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVal > 0 ? (maxVal * 1.3 / 4) : 25000,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colorScheme.outlineVariant.withOpacity(0.35),
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (val, _) => Text(
                      _fmtY(val.toInt()),
                      style:
                          TextStyle(fontSize: 10, color: colorScheme.outline),
                    ),
                  ),
                ),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (val, _) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= data.length) {
                        return const SizedBox.shrink();
                      }
                      final isLast = idx == data.length - 1;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${data[idx].month}월',
                          style: TextStyle(
                            fontSize: 11,
                            color: isLast
                                ? colorScheme.primary
                                : colorScheme.outline,
                            fontWeight:
                                isLast ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => isDark
                      ? colorScheme.surfaceContainerHighest
                      : const Color(0xFFF5F2E8),
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  getTooltipItem: (group, groupIdx, rod, rodIdx) {
                    final d = data[group.x];
                    final isIncome = rodIdx == 0;
                    return BarTooltipItem(
                      '${isIncome ? '수입' : '지출'}\n'
                      '${_fmtTooltip(rod.toY.toInt())}원',
                      TextStyle(
                        color: isIncome ? incomeColor : expenseColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: List.generate(data.length, (i) {
                final d = data[i];
                final isLast = i == data.length - 1;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: d.income.toDouble(),
                      color: incomeColor.withOpacity(isLast ? 1.0 : 0.55),
                      width: 11,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                    BarChartRodData(
                      toY: d.expense.toDouble(),
                      color: expenseColor.withOpacity(isLast ? 1.0 : 0.55),
                      width: 11,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ],
                  barsSpace: 4,
                );
              }),
            ),
            swapAnimationDuration: const Duration(milliseconds: 300),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 공용 소형 위젯
// ════════════════════════════════════════════════════════════

class _ChartTitle extends StatelessWidget {
  const _ChartTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.newsreader(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 120,
        child: Center(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}
