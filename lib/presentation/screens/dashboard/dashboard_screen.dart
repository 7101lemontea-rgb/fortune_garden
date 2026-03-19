// lib/presentation/screens/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../domain/entities/view_mode.dart';
import '../../../application/report/report_use_case.dart';  // MonthlySummary
import '../../providers/app_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync  = ref.watch(dashboardSummaryProvider);
    final viewModeAsync = ref.watch(viewModeProvider);
    final txListAsync   = ref.watch(transactionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fortune Garden'),
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
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profiles'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(transactionListProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 요약 카드
            summaryAsync.when(
              data: (summaries) => _SummaryCard(summaries: summaries),
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('오류: $e'),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 최근 거래
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('최근 거래',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                  onPressed: () => context.go('/transactions'),
                  child: const Text('전체 보기'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            txListAsync.when(
              data: (txns) => txns.isEmpty
                  ? _EmptyTxn(onImport: () => context.go('/import'))
                  : Column(
                      children: txns
                          .take(10)
                          .map((t) => _TxnTile(txn: t))
                          .toList(),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/transactions/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── 요약 카드 ──────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summaries});
  final List<MonthlySummary> summaries;

  String _fmt(int amount) =>
      NumberFormat('#,###원', 'ko_KR').format(amount.abs());

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) return const SizedBox.shrink();

    final totalIncome  = summaries.fold<int>(0, (s, e) => s + e.income);
    final totalExpense = summaries.fold<int>(0, (s, e) => s + e.expense);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy년 M월', 'ko_KR').format(DateTime.now()),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatItem(
                    label: '수입', value: _fmt(totalIncome), color: Colors.green)),
                Expanded(child: _StatItem(
                    label: '지출', value: _fmt(totalExpense), color: Colors.red)),
                Expanded(child: _StatItem(
                    label: '순수지',
                    value: _fmt(totalIncome + totalExpense),
                    color: (totalIncome + totalExpense) >= 0
                        ? Colors.green
                        : Colors.red)),
              ],
            ),
            if (summaries.length > 1) ...[
              const Divider(height: 24),
              ...summaries.map((s) {
                final color = Color(int.parse(
                    'FF${s.colorHex.replaceAll('#', '')}', radix: 16));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      CircleAvatar(backgroundColor: color, radius: 6),
                      const SizedBox(width: 8),
                      Text(s.profileName,
                          style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      Text(_fmt(s.expense),
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 13)),
        ],
      );
}

// ── 거래 타일 ──────────────────────────────────────────────
class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final Transaction txn;

  @override
  Widget build(BuildContext context) {
    final dt        = DateTime.fromMillisecondsSinceEpoch(txn.txnDate);
    final isExpense = txn.amount < 0;
    return ListTile(
      title: Text(txn.merchant,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(DateFormat('M/d', 'ko_KR').format(dt)),
      trailing: Text(
        '${isExpense ? '-' : '+'}${NumberFormat('#,###', 'ko_KR').format(txn.amount.abs())}원',
        style: TextStyle(
            color: isExpense ? Colors.red : Colors.green,
            fontWeight: FontWeight.w500),
      ),
      onTap: () => context.go('/transactions/${txn.id}'),
    );
  }
}

// ── 빈 상태 ────────────────────────────────────────────────
class _EmptyTxn extends StatelessWidget {
  const _EmptyTxn({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('거래 내역이 없습니다',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('CSV 가져오기'),
          ),
        ],
      );
}
