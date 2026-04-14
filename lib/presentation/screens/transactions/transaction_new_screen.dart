// lib/presentation/screens/transactions/transaction_new_screen.dart
// SCR-005 /transactions/new — 수동 거래 입력

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../application/transaction/transaction_use_case.dart';
import '../../../application/profile/profile_use_case.dart';
import '../../../application/category/category_classify_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class TransactionNewScreen extends ConsumerStatefulWidget {
  const TransactionNewScreen({super.key});

  @override
  ConsumerState<TransactionNewScreen> createState() =>
      _TransactionNewScreenState();
}

class _TransactionNewScreenState extends ConsumerState<TransactionNewScreen> {
  final _merchantCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  bool _isExpense = true;
  int? _categoryId;
  int? _accountId;
  List<Account> _accounts = [];
  List<Category> _categories = [];
  bool _saving = false;

  // 유효성 오류 메시지
  String? _merchantError;
  String? _amountError;

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

    final accounts =
        await ref.read(accountRepositoryProvider).getByProfile(profile.id);
    final cats =
        await ref.read(categoryClassifyUseCaseProvider).getAllCategories();

    if (mounted) {
      setState(() {
        _accounts = accounts;
        _categories = cats;
        _accountId = accounts.isNotEmpty ? accounts.first.id : null;
      });
    }
  }

  bool _validate() {
    String? merchantErr;
    String? amountErr;

    if (_merchantCtrl.text.trim().isEmpty) {
      merchantErr = '거래처명을 입력하세요';
    }
    final raw = int.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    if (_amountCtrl.text.trim().isEmpty) {
      amountErr = '금액을 입력하세요';
    } else if (raw <= 0) {
      amountErr = '0보다 큰 금액을 입력하세요';
    }

    setState(() {
      _merchantError = merchantErr;
      _amountError = amountErr;
    });

    return merchantErr == null && amountErr == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    if (_accountId == null) return;

    final profile = await ref.read(profileUseCaseProvider).getActiveProfile();
    if (profile == null) return;

    setState(() => _saving = true);

    final rawAmount =
        int.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final amount = _isExpense ? -rawAmount : rawAmount;

    await ref.read(transactionUseCaseProvider).upsert(
          profileId: profile.id,
          accountId: _accountId!,
          txnDate: _date.millisecondsSinceEpoch,
          amount: amount,
          merchant: _merchantCtrl.text.trim(),
          categoryId: _categoryId,
          memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
          isManual: true,
        );

    ref.invalidate(transactionListProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(categoryExpensesProvider);
    if (mounted) context.pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Map<int?, List<Category>> _buildCategoryTree() {
    final map = <int?, List<Category>>{};
    for (final c in _categories) {
      map.putIfAbsent(c.parentId, () => []).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22);
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final primaryColor = theme.colorScheme.primary;
    final amountColor = _isExpense ? expenseColor : incomeColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // ── 헤더 ────────────────────────────────────────────
          Container(
            color: headerBg,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: Colors.white,
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        '거래 입력',
                        style: GoogleFonts.newsreader(
                          fontSize: 20,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : TextButton(
                              onPressed: _save,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text(
                                '저장',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 본문 ────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ① 수입/지출 토글
                _SectionCard(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('지출')),
                      ButtonSegment(value: false, label: Text('수입')),
                    ],
                    selected: {_isExpense},
                    onSelectionChanged: (s) =>
                        setState(() => _isExpense = s.first),
                  ),
                ),
                const SizedBox(height: 12),

                // ② 금액 + 날짜
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('금액 (원) *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) {
                          if (_amountError != null) {
                            setState(() => _amountError = null);
                          }
                        },
                        style: GoogleFonts.newsreader(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: amountColor,
                        ),
                        decoration: InputDecoration(
                          prefixText: _isExpense ? '- ' : '+ ',
                          prefixStyle: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: amountColor,
                          ),
                          suffixText: '원',
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 28,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.25),
                          ),
                          errorText: _amountError,
                          border: InputBorder.none,
                          filled: false,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: _amountError != null
                                  ? expenseColor
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('날짜'),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('yyyy년 M월 d일 (E)', 'ko_KR')
                                    .format(_date),
                                style: theme.textTheme.bodyLarge,
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: theme.colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ③ 거래처명 + 계좌
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('거래처명 *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _merchantCtrl,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_merchantError != null) {
                            setState(() => _merchantError = null);
                          }
                        },
                        decoration: _inputDecoration(
                          context,
                          '예) 스타벅스, 쿠팡',
                          errorText: _merchantError,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('계좌'),
                      const SizedBox(height: 6),
                      if (_accounts.isEmpty)
                        Text(
                          '등록된 계좌가 없습니다. 계좌 관리에서 먼저 추가해 주세요.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: expenseColor,
                          ),
                        )
                      else
                        DropdownButtonFormField<int>(
                          value: _accountId,
                          decoration: _inputDecoration(context, '계좌 선택'),
                          items: _accounts
                              .map((a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text(a.alias ?? '계좌 ${a.id}'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _accountId = v),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ④ 카테고리 (계층 구조)
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('카테고리'),
                      const SizedBox(height: 10),
                      _CategorySelector(
                        tree: _buildCategoryTree(),
                        selectedId: _categoryId,
                        onSelect: (id) => setState(() => _categoryId = id),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ⑤ 메모
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('메모'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _memoCtrl,
                        maxLines: 3,
                        decoration: _inputDecoration(context, '메모를 입력하세요'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context,
    String hint, {
    String? errorText,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      hintStyle: TextStyle(
        color: theme.colorScheme.onSurface.withOpacity(0.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: theme.colorScheme.primary,
          width: 1.5,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      filled: true,
      fillColor: theme.colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 카테고리 계층 선택 위젯 (SCR-004와 동일 패턴)
// ─────────────────────────────────────────────────────────────

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.tree,
    required this.selectedId,
    required this.onSelect,
  });

  final Map<int?, List<Category>> tree;
  final int? selectedId;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    chips.add(_buildChip(
      context: context,
      label: '미분류',
      colorHex: null,
      isSelected: selectedId == null,
      onTap: () => onSelect(null),
    ));

    final roots = tree[null] ?? [];
    for (final root in roots) {
      chips.add(_buildChip(
        context: context,
        label: root.name,
        colorHex: root.colorHex,
        isSelected: selectedId == root.id,
        onTap: () => onSelect(root.id),
      ));

      final children = tree[root.id] ?? [];
      for (final child in children) {
        chips.add(_buildChip(
          context: context,
          label: child.name,
          colorHex: child.colorHex,
          isSelected: selectedId == child.id,
          onTap: () => onSelect(child.id),
          isChild: true,
        ));
      }
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required String? colorHex,
    required bool isSelected,
    required VoidCallback onTap,
    bool isChild = false,
  }) {
    final theme = Theme.of(context);
    Color? catColor;
    if (colorHex != null) {
      try {
        catColor = Color(
          int.parse(colorHex.replaceFirst('#', ''), radix: 16) | 0xFF000000,
        );
      } catch (_) {}
    }

    final primary = theme.colorScheme.primary;
    final selectedBg = catColor?.withOpacity(0.18) ?? primary.withOpacity(0.12);
    final selectedEdge = catColor ?? primary;
    final selectedText = catColor ?? primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: isChild ? 10 : 12,
          vertical: isChild ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedBg
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? selectedEdge : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isChild)
              Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? selectedText : theme.colorScheme.outline,
                ),
              )
            else if (catColor != null)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: catColor,
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: isChild ? 12 : 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? selectedText
                    : theme.colorScheme.onSurface.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 공통 보조 위젯
// ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
            letterSpacing: 0.3,
          ),
    );
  }
}
