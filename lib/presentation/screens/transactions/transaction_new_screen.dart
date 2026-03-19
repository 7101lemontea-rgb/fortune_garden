// lib/presentation/screens/transactions/transaction_new_screen.dart
// SCR-005 /transactions/new — 수동 거래 입력

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/transaction/transaction_use_case.dart';
import '../../../application/profile/profile_use_case.dart';
import '../../../application/category/category_classify_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/app_providers.dart';

class TransactionNewScreen extends ConsumerStatefulWidget {
  const TransactionNewScreen({super.key});

  @override
  ConsumerState<TransactionNewScreen> createState() =>
      _TransactionNewScreenState();
}

class _TransactionNewScreenState extends ConsumerState<TransactionNewScreen> {
  final _merchantCtrl = TextEditingController();
  final _amountCtrl   = TextEditingController();
  final _memoCtrl     = TextEditingController();

  DateTime      _date         = DateTime.now();
  bool          _isExpense    = true;
  int?          _categoryId;
  int?          _accountId;
  List<Account> _accounts     = [];
  List<Category>_categories   = [];
  bool          _saving       = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final profile = await ref.read(profileUseCaseProvider).getActiveProfile();
    if (profile == null) return;

    final accounts = await ref
        .read(accountRepositoryProvider)
        .getByProfile(profile.id);
    final cats = await ref
        .read(categoryClassifyUseCaseProvider)
        .getAllCategories();

    if (mounted) {
      setState(() {
        _accounts   = accounts;
        _categories = cats;
        _accountId  = accounts.isNotEmpty ? accounts.first.id : null;
      });
    }
  }

  Future<void> _save() async {
    if (_merchantCtrl.text.trim().isEmpty) return;
    if (_amountCtrl.text.trim().isEmpty) return;
    if (_accountId == null) return;

    final profile = await ref.read(profileUseCaseProvider).getActiveProfile();
    if (profile == null) return;

    setState(() => _saving = true);

    final rawAmount = int.tryParse(
          _amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final amount = _isExpense ? -rawAmount : rawAmount;

    await ref.read(transactionUseCaseProvider).upsert(
      profileId:  profile.id,
      accountId:  _accountId!,
      txnDate:    _date.millisecondsSinceEpoch,
      amount:     amount,
      merchant:   _merchantCtrl.text.trim(),
      categoryId: _categoryId,
      memo:       _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      isManual:   true,
    );

    ref.invalidate(transactionListProvider);
    ref.invalidate(dashboardSummaryProvider);
    if (mounted) context.pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('수동 거래 입력')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 수입/지출 토글
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true,  label: Text('지출')),
              ButtonSegment(value: false, label: Text('수입')),
            ],
            selected: {_isExpense},
            onSelectionChanged: (s) =>
                setState(() => _isExpense = s.first),
          ),
          const SizedBox(height: 16),

          // 날짜
          ListTile(
            title: Text('${_date.year}년 ${_date.month}월 ${_date.day}일'),
            leading: const Icon(Icons.calendar_today_outlined),
            onTap: _pickDate,
            tileColor: Theme.of(context).colorScheme.surfaceVariant,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(height: 12),

          // 계좌 선택
          if (_accounts.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _accountId,
              decoration: const InputDecoration(
                labelText: '계좌',
                border: OutlineInputBorder(),
              ),
              items: _accounts.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.alias ?? '계좌 ${a.id}'),
              )).toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
          const SizedBox(height: 12),

          // 거래처명
          TextField(
            controller: _merchantCtrl,
            decoration: const InputDecoration(
              labelText: '거래처명 *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // 금액
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '금액 (원) *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // 카테고리
          DropdownButtonFormField<int?>(
            value: _categoryId,
            decoration: const InputDecoration(
              labelText: '카테고리',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('미분류')),
              ..._categories.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              )),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),

          // 메모
          TextField(
            controller: _memoCtrl,
            decoration: const InputDecoration(
              labelText: '메모',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ),
        ],
      ),
    );
  }
}
