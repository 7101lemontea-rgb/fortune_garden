// lib/presentation/screens/transactions/transaction_detail_screen.dart
// SCR-004 /transactions/:id — 거래 상세/수정

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../application/transaction/transaction_use_case.dart';
import '../../../application/category/category_classify_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../providers/app_providers.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  Transaction? _txn;
  List<Category> _categories = [];
  int?    _selectedCategoryId;
  late final _memoCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final txn = await ref.read(transactionUseCaseProvider).getById(widget.id);
    final cats = await ref.read(categoryClassifyUseCaseProvider)
        .getAllCategories();
    if (mounted) {
      setState(() {
        _txn = txn;
        _categories = cats;
        _selectedCategoryId = txn?.categoryId;
        _memoCtrl.text = txn?.memo ?? '';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_txn == null) return;
    await ref.read(transactionUseCaseProvider).updateMeta(
      id:         _txn!.id,
      categoryId: _selectedCategoryId,
      memo:       _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
    );
    ref.invalidate(transactionListProvider);
    ref.invalidate(dashboardSummaryProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_txn == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('거래를 찾을 수 없습니다')),
      );
    }

    final txn  = _txn!;
    final dt   = DateTime.fromMillisecondsSinceEpoch(txn.txnDate);
    final fmt  = NumberFormat('#,###', 'ko_KR');
    final isEx = txn.amount < 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('거래 상세'),
        actions: [
          TextButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 거래 정보 카드
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn.merchant,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('yyyy년 M월 d일', 'ko_KR').format(dt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${isEx ? '-' : '+'}${fmt.format(txn.amount.abs())}원',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isEx ? Colors.red : Colors.green,
                    ),
                  ),
                  if (txn.isManual == 1) ...[
                    const SizedBox(height: 8),
                    const Chip(label: Text('수동 입력')),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 카테고리 선택
          Text('카테고리',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('미분류'),
                selected: _selectedCategoryId == null,
                onSelected: (_) =>
                    setState(() => _selectedCategoryId = null),
              ),
              ..._categories.map((c) => FilterChip(
                label: Text(c.name),
                selected: _selectedCategoryId == c.id,
                onSelected: (_) =>
                    setState(() => _selectedCategoryId = c.id),
              )),
            ],
          ),
          const SizedBox(height: 16),

          // 메모
          TextField(
            controller: _memoCtrl,
            decoration: const InputDecoration(
              labelText: '메모',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
