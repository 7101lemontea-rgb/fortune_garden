// lib/presentation/screens/report/report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/view_mode.dart';
import '../../../application/report/report_use_case.dart';  // MonthlySummary, reportUseCaseProvider
import '../../providers/app_providers.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime _month =
      DateTime(DateTime.now().year, DateTime.now().month);

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() {
    final next = DateTime(_month.year, _month.month + 1);
    if (!next.isAfter(DateTime.now())) setState(() => _month = next);
  }

  // ConsumerStatefulWidget에서 ref.watch 사용 → build() 안에서만
  @override
  Widget build(BuildContext context) {
    final viewModeAsync = ref.watch(viewModeProvider);
    final activeAsync   = ref.watch(activeProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('리포트'),
        actions: [
          viewModeAsync.when(
            data: (mode) => TextButton.icon(
              icon: Icon(mode == ViewMode.combined
                  ? Icons.people_outline
                  : Icons.person_outline),
              label: Text(mode == ViewMode.combined ? '통합' : '개인'),
              onPressed: () => ref.read(viewModeProvider.notifier).setMode(
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
      body: Column(
        children: [
          // 월 선택
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: _prevMonth,
                    icon: const Icon(Icons.chevron_left)),
                Text(
                  DateFormat('yyyy년 M월', 'ko_KR').format(_month),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                    onPressed: _nextMonth,
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Expanded(
            child: viewModeAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('오류: $e')),
              data: (mode) => activeAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('오류: $e')),
                data: (profile) {
                  // month 변경 시 재계산되는 로컬 FutureProvider
                  final summaryProvider = FutureProvider
                      .autoDispose<List<MonthlySummary>>((r) =>
                          r.read(reportUseCaseProvider).getMonthlySummary(
                            year:            _month.year,
                            month:           _month.month,
                            viewMode:        mode,
                            activeProfileId: profile?.id,
                          ));
                  return Consumer(builder: (ctx, r, _) {
                    final async = r.watch(summaryProvider);
                    return async.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('오류: $e')),
                      data: (s) => _ReportBody(summaries: s),
                    );
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 리포트 본문 ────────────────────────────────────────────
class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.summaries});
  final List<MonthlySummary> summaries;

  String _fmt(int v) =>
      NumberFormat('#,###원', 'ko_KR').format(v.abs());

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const Center(child: Text('해당 월의 거래 내역이 없습니다'));
    }

    final totalIncome  = summaries.fold<int>(0, (s, e) => s + e.income);
    final totalExpense = summaries.fold<int>(0, (s, e) => s + e.expense);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SummaryRow('총 수입',  _fmt(totalIncome),  Colors.green),
                const Divider(),
                _SummaryRow('총 지출',  _fmt(totalExpense), Colors.red),
                const Divider(),
                _SummaryRow(
                  '순수지',
                  _fmt(totalIncome + totalExpense),
                  (totalIncome + totalExpense) >= 0
                      ? Colors.green
                      : Colors.red,
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        if (summaries.length > 1) ...[
          const SizedBox(height: 16),
          Text('프로필별',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...summaries.map((s) {
            final color = Color(int.parse(
                'FF${s.colorHex.replaceAll('#', '')}', radix: 16));
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: color, radius: 10),
                    const SizedBox(width: 12),
                    Text(s.profileName),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_fmt(s.income),
                            style: const TextStyle(
                                color: Colors.green, fontSize: 12)),
                        Text(_fmt(s.expense),
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, this.color,
      {this.bold = false});
  final String label;
  final String value;
  final Color  color;
  final bool   bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(label),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.w500)),
          ],
        ),
      );
}
