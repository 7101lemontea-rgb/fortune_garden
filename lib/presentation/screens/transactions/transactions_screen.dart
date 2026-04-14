// lib/presentation/screens/transactions/transactions_screen.dart
// SCR-003 /transactions — 거래 내역
//
// Desktop (≥720px): 2컬럼 — 좌: SliverAppBar 헤더 + 거래 목록 / 우: 월 요약 + Spending Pulse
// Mobile  (<720px):  싱글 컬럼 — SliverAppBar 헤더 + 월 이동 + 필터 + 목록

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/repositories/transaction_filter.dart';
import '../../../application/category/category_classify_use_case.dart';
import '../../../application/transaction/transaction_use_case.dart';
import '../../../application/report/report_use_case.dart';
import '../../providers/app_providers.dart';
import '../dashboard/dashboard_charts.dart';
import 'monthly_analysis.dart';

// ── 카테고리 맵 Provider ──────────────────────────────────────────────────────
final _categoryMapProvider = FutureProvider<Map<int, Category>>((ref) async {
  final cats =
      await ref.read(categoryClassifyUseCaseProvider).getAllCategories();
  return {for (final c in cats) c.id: c};
});

// ── 수입/지출 필터 ────────────────────────────────────────────────────────────
enum _TypeFilter { all, expense, income }

class _FilterState {
  const _FilterState({
    this.typeFilter = _TypeFilter.all,
    this.searchQuery = '',
  });
  final _TypeFilter typeFilter;
  final String searchQuery;

  _FilterState copyWith({_TypeFilter? typeFilter, String? searchQuery}) =>
      _FilterState(
        typeFilter: typeFilter ?? this.typeFilter,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

final _filterStateProvider =
    StateProvider.autoDispose<_FilterState>((ref) => const _FilterState());

// ── 월별 거래 목록 Provider ───────────────────────────────────────────────────
final _monthlyTransactionListProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) {
  final selected = ref.watch(selectedMonthProvider);
  final filter = TransactionFilter(
    fromDate: selected.monthStartMs,
    toDate: selected.monthEndMs,
    limit: 500,
  );
  return ref.read(transactionUseCaseProvider).getList(filter);
});

// ─────────────────────────────────────────────────────────────────────────────

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchCtrl.clear();
        ref
            .read(_filterStateProvider.notifier)
            .update((s) => s.copyWith(searchQuery: ''));
      }
    });
  }

  Future<void> _deleteTransaction(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('거래 삭제'),
        content: const Text('이 거래를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '삭제',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(transactionUseCaseProvider).delete(id);
      ref.invalidate(_monthlyTransactionListProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(categoryExpensesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      body: GrainOverlay(
        child: isDesktop
            ? _DesktopLayout(
                showSearch: _showSearch,
                searchCtrl: _searchCtrl,
                onToggleSearch: _toggleSearch,
                onDelete: _deleteTransaction,
              )
            : _MobileLayout(
                showSearch: _showSearch,
                searchCtrl: _searchCtrl,
                onToggleSearch: _toggleSearch,
                onDelete: _deleteTransaction,
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/transactions/new'),
        tooltip: '거래 추가',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Desktop — 2컬럼
// ════════════════════════════════════════════════════════════

class _DesktopLayout extends ConsumerStatefulWidget {
  const _DesktopLayout({
    required this.showSearch,
    required this.searchCtrl,
    required this.onToggleSearch,
    required this.onDelete,
  });

  final bool showSearch;
  final TextEditingController searchCtrl;
  final VoidCallback onToggleSearch;
  final Future<void> Function(int) onDelete;

  @override
  ConsumerState<_DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends ConsumerState<_DesktopLayout> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedMonthProvider);
    final headerBg = isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22);

    return Column(
      children: [
        // ── 통합 AppBar ──────────────────────────────────
        Container(
          color: headerBg,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  // 좌: 앱 타이틀 or 검색바
                  Expanded(
                    child: widget.showSearch
                        ? TextField(
                            controller: widget.searchCtrl,
                            autofocus: true,
                            onChanged: (v) => ref
                                .read(_filterStateProvider.notifier)
                                .update((s) => s.copyWith(searchQuery: v)),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: '거래처명 검색...',
                              hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 14),
                              prefixIcon: Icon(Icons.search,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 20),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.12),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // 우: 검색 + 프로필 아이콘
                  IconButton(
                    icon: Icon(
                      widget.showSearch ? Icons.close : Icons.search_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: widget.onToggleSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_outline,
                        color: Colors.white, size: 22),
                    onPressed: () => context.push('/profiles'),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),

        // ── 좌/우 컬럼 ───────────────────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 좌: 제목 + 목록
              Expanded(
                child: _TxnListColumn(
                  selected: selected,
                  onDelete: widget.onDelete,
                  hPad: 20.0,
                ),
              ),
              // 우: 요약 패널
              SizedBox(
                width: 400,
                child: _SummaryPanel(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// Mobile — 싱글 컬럼
// ════════════════════════════════════════════════════════════

class _MobileLayout extends ConsumerWidget {
  const _MobileLayout({
    required this.showSearch,
    required this.searchCtrl,
    required this.onToggleSearch,
    required this.onDelete,
  });

  final bool showSearch;
  final TextEditingController searchCtrl;
  final VoidCallback onToggleSearch;
  final Future<void> Function(int) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TxnScrollView(
      showSearch: showSearch,
      searchCtrl: searchCtrl,
      onToggleSearch: onToggleSearch,
      onDelete: onDelete,
    );
  }
}

// ════════════════════════════════════════════════════════════
// Desktop 좌측 컬럼 — 제목 + 목록 (AppBar 없음)
// ════════════════════════════════════════════════════════════

class _TxnListColumn extends ConsumerWidget {
  const _TxnListColumn({
    required this.selected,
    required this.onDelete,
    required this.hPad,
  });

  final SelectedMonth selected;
  final Future<void> Function(int) onDelete;
  final double hPad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final filterState = ref.watch(_filterStateProvider);
    final txnsAsync = ref.watch(_monthlyTransactionListProvider);
    final catMapAsync = ref.watch(_categoryMapProvider);

    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;

    return CustomScrollView(
      slivers: [
        // ── 제목 영역 ─────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${selected.year}년 ${selected.month}월'.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '거래 내역',
                  style: GoogleFonts.gowunBatang(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 월 이동 + 필터 칩 ─────────────────────────────
        SliverToBoxAdapter(
          child: _ControlRow(hPad: 16),
        ),

        // ── 거래 목록 ─────────────────────────────────────
        txnsAsync.when(
          data: (allTxns) {
            final txns = _applyFilter(allTxns, filterState);
            if (txns.isEmpty) {
              return SliverFillRemaining(
                child: _EmptyView(
                  hasFilter: filterState.typeFilter != _TypeFilter.all ||
                      filterState.searchQuery.isNotEmpty,
                ),
              );
            }
            final grouped = _groupByDate(txns);
            final catMap = catMapAsync.valueOrNull ?? {};

            return SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final entry = grouped[i];
                    if (entry is _DateHeader) {
                      return _DateHeaderTile(
                        dateLabel: entry.label,
                        dayTotal: entry.dayTotal,
                        expenseColor: expenseColor,
                        incomeColor: incomeColor,
                        isFirst: i == 0,
                      );
                    }
                    final txn = (entry as _TxnItem).txn;
                    final cat =
                        txn.categoryId != null ? catMap[txn.categoryId] : null;
                    final isLast = i == grouped.length - 1;
                    final nextIsHeader =
                        !isLast && grouped[i + 1] is _DateHeader;
                    return _TxnCard(
                      txn: txn,
                      category: cat,
                      expenseColor: expenseColor,
                      incomeColor: incomeColor,
                      showDivider: !isLast && !nextIsHeader,
                      onTap: () => context.push('/transactions/${txn.id}'),
                      onDelete: () => onDelete(txn.id),
                    );
                  },
                  childCount: grouped.length,
                ),
              ),
            );
          },
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: Center(child: Text('오류: $e')),
          ),
        ),
      ],
    );
  }

  List<Transaction> _applyFilter(List<Transaction> txns, _FilterState filter) {
    var result = txns;
    if (filter.typeFilter == _TypeFilter.expense) {
      result = result.where((t) => t.amount < 0).toList();
    } else if (filter.typeFilter == _TypeFilter.income) {
      result = result.where((t) => t.amount > 0).toList();
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = filter.searchQuery.toLowerCase();
      result =
          result.where((t) => t.merchant.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  List<Object> _groupByDate(List<Transaction> txns) {
    final sorted = [...txns]..sort((a, b) => b.txnDate.compareTo(a.txnDate));
    final result = <Object>[];
    String? lastKey;

    for (final txn in sorted) {
      final dt = DateTime.fromMillisecondsSinceEpoch(txn.txnDate);
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';

      if (key != lastKey) {
        final dayTxns = sorted.where((t) {
          final d = DateTime.fromMillisecondsSinceEpoch(t.txnDate);
          return d.year == dt.year && d.month == dt.month && d.day == dt.day;
        });
        final dayIncome = dayTxns
            .where((t) => t.amount > 0)
            .fold<int>(0, (s, t) => s + t.amount);
        final dayExpense = dayTxns
            .where((t) => t.amount < 0)
            .fold<int>(0, (s, t) => s + t.amount.abs());

        result.add(_DateHeader(
          label: _fmtDateLabel(dt),
          dayTotal: (income: dayIncome, expense: dayExpense),
        ));
        lastKey = key;
      }
      result.add(_TxnItem(txn));
    }
    return result;
  }

  String _fmtDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    final wd = ['월', '화', '수', '목', '금', '토', '일'][dt.weekday - 1];
    if (diff == 0) return '오늘 ($wd)';
    if (diff == 1) return '어제 ($wd)';
    return '${DateFormat('M월 d일', 'ko_KR').format(dt)} ($wd)';
  }
}

// ════════════════════════════════════════════════════════════
// 공통 스크롤 뷰 — SliverAppBar + 목록
// ════════════════════════════════════════════════════════════

class _TxnScrollView extends ConsumerWidget {
  const _TxnScrollView({
    required this.showSearch,
    required this.searchCtrl,
    required this.onToggleSearch,
    required this.onDelete,
  });

  final bool showSearch;
  final TextEditingController searchCtrl;
  final VoidCallback onToggleSearch;
  final Future<void> Function(int) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedMonthProvider);
    final filterState = ref.watch(_filterStateProvider);
    final txnsAsync = ref.watch(_monthlyTransactionListProvider);
    final catMapAsync = ref.watch(_categoryMapProvider);

    final headerBg = isDark ? const Color(0xFF051a0f) : const Color(0xFF2d4a22);
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;

    return CustomScrollView(
      slivers: [
        // ── AppBar — 프로필 + 검색만 ──────────────────────
        SliverAppBar(
          pinned: true,
          floating: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: headerBg,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: Icon(
                showSearch ? Icons.close : Icons.search_outlined,
                color: Colors.white,
                size: 22,
              ),
              onPressed: onToggleSearch,
            ),
            IconButton(
              icon: const Icon(
                Icons.person_outline,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => context.push('/profiles'),
            ),
          ],
        ),

        // ── 제목 영역 (일반 배경) ──────────────────────────
        SliverToBoxAdapter(
          child: showSearch
              ? Container(
                  color: headerBg,
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: (v) => ref
                        .read(_filterStateProvider.notifier)
                        .update((s) => s.copyWith(searchQuery: v)),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: '거래처명 검색...',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 14),
                      prefixIcon: Icon(Icons.search,
                          color: Colors.white.withOpacity(0.7), size: 20),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.3), width: 1),
                      ),
                    ),
                  ),
                )
              : Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selected.year}년 ${selected.month}월'.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '거래 내역',
                        style: GoogleFonts.gowunBatang(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
        ),

        // ── 월 이동 + 필터 칩 ─────────────────────────────
        SliverToBoxAdapter(
          child: _ControlRow(hPad: 16),
        ),

        // ── 거래 목록 ─────────────────────────────────────
        txnsAsync.when(
          data: (allTxns) {
            final txns = _applyFilter(allTxns, filterState);
            if (txns.isEmpty) {
              return SliverFillRemaining(
                child: _EmptyView(
                  hasFilter: filterState.typeFilter != _TypeFilter.all ||
                      filterState.searchQuery.isNotEmpty,
                ),
              );
            }
            final grouped = _groupByDate(txns);
            final catMap = catMapAsync.valueOrNull ?? {};

            return SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final entry = grouped[i];
                    if (entry is _DateHeader) {
                      return _DateHeaderTile(
                        dateLabel: entry.label,
                        dayTotal: entry.dayTotal,
                        expenseColor: expenseColor,
                        incomeColor: incomeColor,
                        isFirst: i == 0,
                      );
                    }
                    final txn = (entry as _TxnItem).txn;
                    final cat =
                        txn.categoryId != null ? catMap[txn.categoryId] : null;
                    final isLast = i == grouped.length - 1;
                    final nextIsHeader =
                        !isLast && grouped[i + 1] is _DateHeader;
                    return _TxnCard(
                      txn: txn,
                      category: cat,
                      expenseColor: expenseColor,
                      incomeColor: incomeColor,
                      showDivider: !isLast && !nextIsHeader,
                      onTap: () => context.push('/transactions/${txn.id}'),
                      onDelete: () => onDelete(txn.id),
                    );
                  },
                  childCount: grouped.length,
                ),
              ),
            );
          },
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: Center(child: Text('오류: $e')),
          ),
        ),
      ],
    );
  }

  List<Transaction> _applyFilter(List<Transaction> txns, _FilterState filter) {
    var result = txns;
    if (filter.typeFilter == _TypeFilter.expense) {
      result = result.where((t) => t.amount < 0).toList();
    } else if (filter.typeFilter == _TypeFilter.income) {
      result = result.where((t) => t.amount > 0).toList();
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = filter.searchQuery.toLowerCase();
      result =
          result.where((t) => t.merchant.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  List<Object> _groupByDate(List<Transaction> txns) {
    final sorted = [...txns]..sort((a, b) => b.txnDate.compareTo(a.txnDate));
    final result = <Object>[];
    String? lastKey;

    for (final txn in sorted) {
      final dt = DateTime.fromMillisecondsSinceEpoch(txn.txnDate);
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';

      if (key != lastKey) {
        final dayTxns = sorted.where((t) {
          final d = DateTime.fromMillisecondsSinceEpoch(t.txnDate);
          return d.year == dt.year && d.month == dt.month && d.day == dt.day;
        });
        final dayIncome = dayTxns
            .where((t) => t.amount > 0)
            .fold<int>(0, (s, t) => s + t.amount);
        final dayExpense = dayTxns
            .where((t) => t.amount < 0)
            .fold<int>(0, (s, t) => s + t.amount.abs());

        result.add(_DateHeader(
          label: _fmtDateLabel(dt),
          dayTotal: (income: dayIncome, expense: dayExpense),
        ));
        lastKey = key;
      }
      result.add(_TxnItem(txn));
    }
    return result;
  }

  String _fmtDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    final wd = ['월', '화', '수', '목', '금', '토', '일'][dt.weekday - 1];
    if (diff == 0) return '오늘 ($wd)';
    if (diff == 1) return '어제 ($wd)';
    return '${DateFormat('M월 d일', 'ko_KR').format(dt)} ($wd)';
  }
}

// ════════════════════════════════════════════════════════════
// 헤더 배경 (FlexibleSpaceBar background)
// ════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════
// 컨트롤 행 — 월 이동 + 필터 칩
// ════════════════════════════════════════════════════════════

class _ControlRow extends ConsumerWidget {
  const _ControlRow({required this.hPad});
  final double hPad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = ref.watch(selectedMonthProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    final filterState = ref.watch(_filterStateProvider);

    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: notifier.prev,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.chevron_left,
                  size: 20, color: cs.onSurfaceVariant),
            ),
          ),
          GestureDetector(
            onTap: notifier.reset,
            child: Text(
              '${selected.month}월',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          GestureDetector(
            onTap: selected.isCurrentMonth ? null : notifier.next,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: selected.isCurrentMonth
                    ? cs.onSurfaceVariant.withOpacity(0.3)
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _TypeChip(
            label: '전체',
            selected: filterState.typeFilter == _TypeFilter.all,
            color: cs.primary,
            onTap: () => ref
                .read(_filterStateProvider.notifier)
                .update((s) => s.copyWith(typeFilter: _TypeFilter.all)),
          ),
          const SizedBox(width: 6),
          _TypeChip(
            label: '지출',
            selected: filterState.typeFilter == _TypeFilter.expense,
            color: expenseColor,
            onTap: () => ref
                .read(_filterStateProvider.notifier)
                .update((s) => s.copyWith(typeFilter: _TypeFilter.expense)),
          ),
          const SizedBox(width: 6),
          _TypeChip(
            label: '수입',
            selected: filterState.typeFilter == _TypeFilter.income,
            color: incomeColor,
            onTap: () => ref
                .read(_filterStateProvider.notifier)
                .update((s) => s.copyWith(typeFilter: _TypeFilter.income)),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.13) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? color
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 우측 요약 패널 (Desktop 전용)
// ════════════════════════════════════════════════════════════

class _SummaryPanel extends ConsumerWidget {
  const _SummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = ref.watch(selectedMonthProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final categoryExpAsync = ref.watch(categoryExpensesProvider);

    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: cs.outlineVariant.withOpacity(0.4), width: 1),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${selected.month}월 요약'.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Summary',
                    style: GoogleFonts.newsreader(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summaryAsync.when(
                    data: (summaries) => _MonthlySummaryNumbers(
                      summaries: summaries,
                      incomeColor: incomeColor,
                      expenseColor: expenseColor,
                    ),
                    loading: () => const _PanelSkeleton(height: 140),
                    error: (e, _) => Text('오류: $e',
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'SPENDING PULSE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  categoryExpAsync.when(
                    data: (data) => data.isEmpty
                        ? const _PanelEmpty(message: '이번 달 지출 없음')
                        : DashboardDonutChart(data: data),
                    loading: () => const _PanelSkeleton(height: 220),
                    error: (e, _) => Text('오류: $e',
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ),
                  const SizedBox(height: 28),
                  const AnalysisCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 월 요약 수치 ──────────────────────────────────────────────────────────────

class _MonthlySummaryNumbers extends StatelessWidget {
  const _MonthlySummaryNumbers({
    required this.summaries,
    required this.incomeColor,
    required this.expenseColor,
  });

  final List<MonthlySummary> summaries;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,###', 'ko_KR');

    final totalIncome = summaries.fold<int>(0, (s, m) => s + m.income);
    final totalExpense = summaries.fold<int>(0, (s, m) => s + m.expense).abs();
    final net = totalIncome - totalExpense;

    return Column(
      children: [
        _SummaryRow(
          label: 'Total Inflow',
          value: '+${fmt.format(totalIncome)}',
          valueColor: incomeColor,
        ),
        const SizedBox(height: 14),
        _SummaryRow(
          label: 'Total Outflow',
          value: '-${fmt.format(totalExpense)}',
          valueColor: expenseColor,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Divider(
            color:
                Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
            height: 1,
          ),
        ),
        Row(
          children: [
            Text(
              'NET CHANGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${net >= 0 ? '+' : ''}${fmt.format(net)}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: net >= 0 ? incomeColor : expenseColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 데이터 모델
// ════════════════════════════════════════════════════════════

class _DateHeader {
  const _DateHeader({required this.label, required this.dayTotal});
  final String label;
  final ({int income, int expense}) dayTotal;
}

class _TxnItem {
  const _TxnItem(this.txn);
  final Transaction txn;
}

// ════════════════════════════════════════════════════════════
// 날짜 헤더 타일
// ════════════════════════════════════════════════════════════

class _DateHeaderTile extends StatelessWidget {
  const _DateHeaderTile({
    required this.dateLabel,
    required this.dayTotal,
    required this.expenseColor,
    required this.incomeColor,
    this.isFirst = false,
  });

  final String dateLabel;
  final ({int income, int expense}) dayTotal;
  final Color expenseColor;
  final Color incomeColor;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,###', 'ko_KR');

    return Column(
      children: [
        // 날짜 그룹 구분선 — 첫 번째 그룹은 선 없음
        if (!isFirst)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outline.withOpacity(0.5),
          ),
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 16 : 20, bottom: 8),
          child: Row(
            children: [
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (dayTotal.income > 0)
                Text(
                  '+${fmt.format(dayTotal.income)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: incomeColor,
                      fontWeight: FontWeight.w600),
                ),
              if (dayTotal.income > 0 && dayTotal.expense > 0)
                const SizedBox(width: 8),
              if (dayTotal.expense > 0)
                Text(
                  '-${fmt.format(dayTotal.expense)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: expenseColor,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 거래 카드
// ════════════════════════════════════════════════════════════

class _TxnCard extends StatelessWidget {
  const _TxnCard({
    required this.txn,
    required this.category,
    required this.expenseColor,
    required this.incomeColor,
    required this.onTap,
    required this.onDelete,
    this.showDivider = false,
  });

  final Transaction txn;
  final Category? category;
  final Color expenseColor;
  final Color incomeColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool showDivider;

  Color _hexToColor(String hex) =>
      Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

  IconData _iconFromName(String? name) => switch (name) {
        'restaurant' => Icons.restaurant_outlined,
        'directions_car' => Icons.directions_car_outlined,
        'shopping_bag' => Icons.shopping_bag_outlined,
        'local_hospital' => Icons.local_hospital_outlined,
        'movie' => Icons.movie_outlined,
        'school' => Icons.school_outlined,
        'receipt' => Icons.receipt_outlined,
        'smartphone' => Icons.smartphone_outlined,
        'account_balance' => Icons.account_balance_outlined,
        'swap_horiz' => Icons.swap_horiz_outlined,
        'more_horiz' => Icons.more_horiz,
        _ => Icons.payments_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isExpense = txn.amount < 0;
    final amountColor = isExpense ? expenseColor : incomeColor;
    final fmt = NumberFormat('#,###', 'ko_KR');

    final catColor = category?.colorHex != null
        ? _hexToColor(category!.colorHex!)
        : cs.outlineVariant;

    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: expenseColor.withOpacity(0.08),
        child: Icon(Icons.delete_outline, color: expenseColor, size: 22),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            // 거래 행
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  // 카테고리 아이콘
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFromName(category?.icon),
                      size: 19,
                      color: catColor,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 거래처명 + 카테고리 · 날짜
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          txn.merchant,
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (category != null) ...[
                              Text(
                                category!.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: catColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                ' · ',
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        cs.onSurfaceVariant.withOpacity(0.5)),
                              ),
                            ],
                            if (category == null && txn.memo == null)
                              Text(
                                '미분류 · ',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant.withOpacity(0.4),
                                ),
                              ),
                            if (txn.memo != null)
                              Flexible(
                                child: Text(
                                  '${txn.memo!} · ',
                                  style: TextStyle(
                                      fontSize: 11, color: cs.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            Text(
                              DateFormat('d MMM', 'ko_KR').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                      txn.txnDate)),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant.withOpacity(0.6)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // 금액 + 수동 뱃지
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isExpense ? '-' : '+'}${fmt.format(txn.amount.abs())}',
                        style: tt.bodyMedium?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (txn.isManual == 1) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '수동',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // 구분선
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color: cs.outline.withOpacity(0.3),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 빈 화면
// ════════════════════════════════════════════════════════════

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.hasFilter});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilter ? Icons.search_off_outlined : Icons.receipt_long_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withOpacity(0.35),
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? '검색 결과가 없습니다' : '이 달의 거래 내역이 없습니다',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
          if (!hasFilter) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/import'),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('CSV 가져오기'),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 패널 공용 위젯
// ════════════════════════════════════════════════════════════

class _PanelSkeleton extends StatelessWidget {
  const _PanelSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: Center(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
}
