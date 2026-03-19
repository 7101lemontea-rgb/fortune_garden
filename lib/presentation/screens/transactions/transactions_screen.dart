// lib/presentation/screens/transactions/transactions_screen.dart
// SCR-003 /transactions — 거래 내역

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../domain/repositories/transaction_filter.dart';
import '../../providers/app_providers.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(transactionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('거래 내역'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.go('/transactions/new'),
          ),
        ],
      ),
      body: txnsAsync.when(
        data: (txns) => txns.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('거래 내역이 없습니다'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.go('/import'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('CSV 가져오기'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: txns.length,
                itemBuilder: (ctx, i) => _TxnTile(txn: txns[i]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('오류: $e')),
      ),
    );
  }
}

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
      subtitle: Text(
        DateFormat('yyyy.MM.dd', 'ko_KR').format(dt),
      ),
      trailing: Text(
        '${isExpense ? '-' : '+'}${NumberFormat('#,###', 'ko_KR').format(txn.amount.abs())}원',
        style: TextStyle(
          color: isExpense ? Colors.red : Colors.green,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () => context.go('/transactions/${txn.id}'),
    );
  }
}
