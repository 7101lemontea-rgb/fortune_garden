// lib/presentation/screens/transactions/transaction_detail_screen.dart
// SCR-004 /transactions/:id — 거래 상세/수정

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../application/transaction/transaction_use_case.dart';
import '../../../application/category/category_classify_use_case.dart';
import '../../../application/profile/profile_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

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
  List<Account> _accounts = [];

  // 편집 상태
  int? _selectedCategoryId;
  late final _memoCtrl = TextEditingController();
  late final _merchantCtrl = TextEditingController();
  late final _amountCtrl = TextEditingController();
  DateTime _txnDate = DateTime.now();
  bool _isExpense = true;
  int? _accountId;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final txn = await ref.read(transactionUseCaseProvider).getById(widget.id);
    final cats =
        await ref.read(categoryClassifyUseCaseProvider).getAllCategories();

    // 계좌 목록: 활성 프로필 기준
    final profile = await ref.read(profileUseCaseProvider).getActiveProfile();
    final accounts = profile != null
        ? await ref.read(accountRepositoryProvider).getByProfile(profile.id)
        : <Account>[];

    if (mounted) {
      setState(() {
        _txn = txn;
        _categories = cats;
        _accounts = accounts;

        if (txn != null) {
          _selectedCategoryId = txn.categoryId;
          _memoCtrl.text = txn.memo ?? '';
          _merchantCtrl.text = txn.merchant;
          _isExpense = txn.amount < 0;
          _amountCtrl.text = txn.amount.abs().toString();
          _txnDate = DateTime.fromMillisecondsSinceEpoch(txn.txnDate);
          _accountId = txn.accountId;
        }
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_txn == null) return;
    final amountRaw =
        int.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final amount = _isExpense ? -amountRaw : amountRaw;
    final merchant = _merchantCtrl.text.trim();
    if (merchant.isEmpty || amountRaw == 0) return;

    setState(() => _saving = true);

    final profile = await ref.read(profileUseCaseProvider).getActiveProfile();

    if (_txn!.isManual == 1 && profile != null) {
      // 수동 거래: 전체 필드 수정
      await ref.read(transactionUseCaseProvider).upsert(
            id: _txn!.id,
            profileId: profile.id,
            accountId: _accountId ?? _txn!.accountId,
            txnDate: _txnDate.millisecondsSinceEpoch,
            amount: amount,
            merchant: merchant,
            categoryId: _selectedCategoryId,
            memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
            isManual: true,
          );
    } else {
      // CSV 거래: 거래처명·카테고리·메모 수정 (금액·날짜·계좌는 원본 유지)
      await ref.read(transactionUseCaseProvider).updateMeta(
            id: _txn!.id,
            merchant: merchant,
            categoryId: _selectedCategoryId,
            memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
          );
    }

    ref.invalidate(transactionListProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(categoryExpensesProvider);
    if (mounted) {
      setState(() => _saving = false);
      context.pop();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거래 삭제'),
        content: const Text('이 거래를 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).brightness == Brightness.dark
                  ? AppTheme.expenseDark
                  : AppTheme.expenseLight,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(transactionUseCaseProvider).delete(_txn!.id);
    ref.invalidate(transactionListProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(categoryExpensesProvider);
    if (mounted) context.pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _txnDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) setState(() => _txnDate = picked);
  }

  // 카테고리 계층 구조 빌드: {parentId → children}
  // parentId가 null인 것이 최상위
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
    // Light: #2d4a22 / Dark: #051a0f (디자인 시스템 헤더 배경색)
    final headerBg = isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22);
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final primaryColor = theme.colorScheme.primary;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_txn == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('거래를 찾을 수 없습니다')),
      );
    }

    final isManual = _txn!.isManual == 1;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // ── 헤더 AppBar ──────────────────────────────────────
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
                        '거래 상세',
                        style: GoogleFonts.gowunBatang(
                          fontSize: 20,
                          // fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // 삭제 버튼
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.75),
                      ),
                      child: const Text('삭제'),
                    ),
                    // 저장 버튼
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
                // ① 수입/지출 토글 (수동만 활성화)
                _SectionCard(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('지출')),
                      ButtonSegment(value: false, label: Text('수입')),
                    ],
                    selected: {_isExpense},
                    onSelectionChanged: isManual
                        ? (s) => setState(() => _isExpense = s.first)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // ② 금액 + 날짜 카드 내의 금액 섹션 수정 코드
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 금액 라벨
                      _FieldLabel('금액 (원)'),
                      const SizedBox(height: 6),

                      // 금액 입력부: Row를 사용하여 요소들을 가로로 배치
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic, // 텍스트 하단 라인을 맞춤
                        children: [
                          // 1. 부호 (+/-)
                          Text(
                            _isExpense ? '- ' : '+ ',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _isExpense ? expenseColor : incomeColor,
                            ),
                          ),

                          // 2. 가변 너비 입력창 (숫자 길이에 맞춰 너비 조절)
                          IntrinsicWidth(
                            child: TextField(
                              controller: _amountCtrl,
                              enabled: isManual,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: GoogleFonts.newsreader(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: _isExpense ? expenseColor : incomeColor,
                              ),
                              // 핵심 설정: TextField의 기본 여백과 데코레이션을 제거하여 텍스트만 보이게 함
                              decoration: InputDecoration(
                                filled: false,
                                fillColor: Colors.transparent,
                                hintText: '0',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                disabledBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // 3. 단위 (원)
                          Text(
                            '원',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _isExpense ? expenseColor : incomeColor,
                            ),
                          ),
                        ],
                      ),

                      // 4. 하단 밑줄
                      Container(
                        height: 2,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: isManual
                              ? (FocusScope.of(context).hasFocus
                                  ? primaryColor
                                  : theme.colorScheme.outlineVariant)
                              : Colors.transparent,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 날짜
                      _FieldLabel('날짜'),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: isManual ? _pickDate : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: isManual
                                    ? primaryColor
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.38),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('yyyy년 M월 d일 (E)', 'ko_KR')
                                    .format(_txnDate),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: isManual
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                ),
                              ),
                              if (isManual) ...[
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: theme.colorScheme.outline,
                                ),
                              ],
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
                      _FieldLabel('거래처명'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _merchantCtrl,
                        decoration: _inputDecoration(context, '거래처명'),
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('계좌'),
                      const SizedBox(height: 6),
                      if (_accounts.isNotEmpty && isManual)
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
                        )
                      else
                        Text(
                          _accounts
                                  .where((a) => a.id == _accountId)
                                  .firstOrNull
                                  ?.alias ??
                              '계좌 ${_accountId ?? '-'}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      // 수동 입력 여부 뱃지
                      if (isManual) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '수동 입력',
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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
                        categories: _categories,
                        tree: _buildCategoryTree(),
                        selectedId: _selectedCategoryId,
                        onSelect: (id) =>
                            setState(() => _selectedCategoryId = id),
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

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    final theme = Theme.of(context);
    return InputDecoration(
      hintText: hint,
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
          color: Theme.of(context).colorScheme.primary,
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
// 카테고리 계층 선택 위젯
// ─────────────────────────────────────────────────────────────

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.tree,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Category> categories;
  final Map<int?, List<Category>> tree;
  final int? selectedId;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[];

    // 미분류 칩
    chips.add(_buildChip(
      context: context,
      label: '미분류',
      colorHex: null,
      isSelected: selectedId == null,
      onTap: () => onSelect(null),
    ));

    // 최상위 카테고리
    final roots = tree[null] ?? [];
    for (final root in roots) {
      chips.add(_buildChip(
        context: context,
        label: root.name,
        colorHex: root.colorHex,
        isSelected: selectedId == root.id,
        onTap: () => onSelect(root.id),
      ));

      // 하위 카테고리 (들여쓰기 표시)
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
            int.parse(colorHex.replaceFirst('#', ''), radix: 16) | 0xFF000000);
      } catch (_) {
        catColor = null;
      }
    }

    final primary = Theme.of(context).colorScheme.primary;
    final selectedBg = catColor?.withOpacity(0.18) ?? primary.withOpacity(0.12);
    final selectedBorder = catColor ?? primary;
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
              : theme.colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? selectedBorder : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isChild) ...[
              Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? selectedText : theme.colorScheme.outline,
                ),
              ),
            ] else if (catColor != null) ...[
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: catColor,
                ),
              ),
            ],
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
