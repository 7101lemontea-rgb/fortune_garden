// lib/presentation/providers/app_providers.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/view_mode.dart';
import '../../domain/entities/parsed_transaction.dart';
import '../../domain/repositories/transaction_filter.dart';
import '../../application/profile/profile_use_case.dart';
import '../../application/profile/view_mode_use_case.dart';
import '../../application/transaction/transaction_use_case.dart';
import '../../application/report/report_use_case.dart';
import '../../application/csv_import/csv_import_use_case.dart';

// ─────────────────────────────────────────────────────────
// CSV 가져오기 상태
// ─────────────────────────────────────────────────────────

enum ImportStatus { idle, importing, done, error }

class ImportState {
  const ImportState({
    this.status = ImportStatus.idle,
    this.result,
    this.errorMessage,
  });

  final ImportStatus status;
  final ImportResult? result;
  final String? errorMessage;

  bool get isImporting => status == ImportStatus.importing;

  ImportState copyWith({
    ImportStatus? status,
    ImportResult? result,
    String? errorMessage,
  }) =>
      ImportState(
        status: status ?? this.status,
        result: result ?? this.result,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ─────────────────────────────────────────────────────────
// selectedMonthProvider  ★ 신규 — 대시보드 월 이동용
// ─────────────────────────────────────────────────────────

class SelectedMonth {
  const SelectedMonth({required this.year, required this.month});

  final int year;
  final int month;

  SelectedMonth get prev {
    if (month == 1) return SelectedMonth(year: year - 1, month: 12);
    return SelectedMonth(year: year, month: month - 1);
  }

  SelectedMonth get next {
    if (month == 12) return SelectedMonth(year: year + 1, month: 1);
    return SelectedMonth(year: year, month: month + 1);
  }

  /// 현재 달(오늘)인지 여부 — 미래 이동 차단에 사용
  bool get isCurrentMonth {
    final now = DateTime.now();
    return year == now.year && month == now.month;
  }

  int get monthStartMs => DateTime(year, month, 1).millisecondsSinceEpoch;

  int get monthEndMs => DateTime(year, month + 1, 1).millisecondsSinceEpoch;

  @override
  bool operator ==(Object other) =>
      other is SelectedMonth && year == other.year && month == other.month;

  @override
  int get hashCode => Object.hash(year, month);
}

final selectedMonthProvider =
    StateNotifierProvider<SelectedMonthNotifier, SelectedMonth>((ref) {
  final now = DateTime.now();
  return SelectedMonthNotifier(SelectedMonth(year: now.year, month: now.month));
});

class SelectedMonthNotifier extends StateNotifier<SelectedMonth> {
  SelectedMonthNotifier(super.state);

  void prev() => state = state.prev;

  void next() {
    if (!state.isCurrentMonth) state = state.next;
  }

  void reset() {
    final now = DateTime.now();
    state = SelectedMonth(year: now.year, month: now.month);
  }
}

// ─────────────────────────────────────────────────────────
// activeProfileProvider
// ─────────────────────────────────────────────────────────

final activeProfileProvider = FutureProvider<Profile?>((ref) {
  return ref.read(profileUseCaseProvider).getActiveProfile();
});

// ─────────────────────────────────────────────────────────
// viewModeProvider
// ─────────────────────────────────────────────────────────

final viewModeProvider =
    AsyncNotifierProvider<ViewModeNotifier, ViewMode>(ViewModeNotifier.new);

class ViewModeNotifier extends AsyncNotifier<ViewMode> {
  @override
  Future<ViewMode> build() => ref.read(viewModeUseCaseProvider).getMode();

  Future<void> setMode(ViewMode mode) async {
    await ref.read(viewModeUseCaseProvider).setMode(mode);
    state = AsyncData(mode);
  }
}

// ─────────────────────────────────────────────────────────
// transactionListProvider
// ─────────────────────────────────────────────────────────

final transactionFilterProvider =
    StateProvider<TransactionFilter>((ref) => const TransactionFilter());

final transactionListProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  return ref.read(transactionUseCaseProvider).getList(filter);
});

// ─────────────────────────────────────────────────────────
// dashboardSummaryProvider  — selectedMonth 참조
// ─────────────────────────────────────────────────────────

final dashboardSummaryProvider =
    FutureProvider.autoDispose<List<MonthlySummary>>((ref) async {
  final viewMode = await ref.watch(viewModeProvider.future);
  final activeProfile = await ref.watch(activeProfileProvider.future);
  final selected = ref.watch(selectedMonthProvider); // ★ 변경

  return ref.read(reportUseCaseProvider).getMonthlySummary(
        year: selected.year, // ★ now.year → selected.year
        month: selected.month, // ★ now.month → selected.month
        viewMode: viewMode,
        activeProfileId: activeProfile?.id,
      );
});

// ─────────────────────────────────────────────────────────
// categoryExpensesProvider  — selectedMonth 참조
// ─────────────────────────────────────────────────────────

final categoryExpensesProvider =
    FutureProvider.autoDispose<List<CategoryExpense>>((ref) async {
  final viewMode = await ref.watch(viewModeProvider.future);
  final activeProfile = await ref.watch(activeProfileProvider.future);
  final db = ref.read(appDatabaseProvider);
  final selected = ref.watch(selectedMonthProvider); // ★ 변경

  return db.getCategoryExpenses(
    monthStart: selected.monthStartMs, // ★ 변경
    monthEnd: selected.monthEndMs, // ★ 변경
    profileId: viewMode == ViewMode.personal ? activeProfile?.id : null,
  );
});

// ─────────────────────────────────────────────────────────
// monthlyTrendProvider  — selectedMonth 기준 6개월
// ─────────────────────────────────────────────────────────

final monthlyTrendProvider =
    FutureProvider.autoDispose<List<MonthlyTrend>>((ref) async {
  final viewMode = await ref.watch(viewModeProvider.future);
  final activeProfile = await ref.watch(activeProfileProvider.future);
  final db = ref.read(appDatabaseProvider);
  final selected = ref.watch(selectedMonthProvider); // ★ 변경

  return db.getMonthlyTrend(
    months: 6,
    profileId: viewMode == ViewMode.personal ? activeProfile?.id : null,
    baseYear: selected.year, // ★ 추가
    baseMonth: selected.month, // ★ 추가
  );
});

// ─────────────────────────────────────────────────────────
// reportCategoryExpensesProvider  — 리포트 전용 (수입/지출 분리)
// ─────────────────────────────────────────────────────────

final reportCategoryExpenseParamProvider =
    StateProvider<bool>((ref) => true); // true = 지출, false = 수입

final reportCategoryExpensesProvider =
    FutureProvider.autoDispose<List<CategoryExpense>>((ref) async {
  final viewMode = await ref.watch(viewModeProvider.future);
  final activeProfile = await ref.watch(activeProfileProvider.future);
  final db = ref.read(appDatabaseProvider);
  final selected = ref.watch(selectedMonthProvider);
  final isExpense = ref.watch(reportCategoryExpenseParamProvider);

  return db.getCategoryExpenses(
    monthStart: selected.monthStartMs,
    monthEnd: selected.monthEndMs,
    profileId: viewMode == ViewMode.personal ? activeProfile?.id : null,
    isExpense: isExpense,
  );
});

// ─────────────────────────────────────────────────────────
// reportSummaryProvider  — 리포트 전용 월별 요약
// ─────────────────────────────────────────────────────────

final reportSummaryProvider =
    FutureProvider.autoDispose<List<MonthlySummary>>((ref) async {
  final viewMode = await ref.watch(viewModeProvider.future);
  final activeProfile = await ref.watch(activeProfileProvider.future);
  final selected = ref.watch(selectedMonthProvider);

  return ref.read(reportUseCaseProvider).getMonthlySummary(
        year: selected.year,
        month: selected.month,
        viewMode: viewMode,
        activeProfileId: activeProfile?.id,
      );
});

final csvImportStateProvider =
    NotifierProvider<CsvImportNotifier, ImportState>(CsvImportNotifier.new);

class CsvImportNotifier extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportState();

  Future<void> execute({
    required File file,
    required int profileId,
    required int accountId,
    required String institutionCode,
  }) async {
    state = state.copyWith(status: ImportStatus.importing);
    try {
      final result = await ref.read(csvImportUseCaseProvider).execute(
            file: file,
            profileId: profileId,
            accountId: accountId,
            institutionCode: institutionCode,
          );
      state = ImportState(status: ImportStatus.done, result: result);
      ref.invalidate(transactionListProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(categoryExpensesProvider);
      ref.invalidate(monthlyTrendProvider);
    } catch (e) {
      state = ImportState(
        status: ImportStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const ImportState();
}
