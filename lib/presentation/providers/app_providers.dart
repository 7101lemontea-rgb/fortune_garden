// lib/presentation/providers/app_providers.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/view_mode.dart';
import '../../domain/entities/parsed_transaction.dart';   // ← ImportResult
import '../../domain/repositories/transaction_filter.dart';
import '../../application/profile/profile_use_case.dart';
import '../../application/profile/view_mode_use_case.dart';
import '../../application/transaction/transaction_use_case.dart';
import '../../application/report/report_use_case.dart';   // ← MonthlySummary
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

  final ImportStatus  status;
  final ImportResult? result;
  final String?       errorMessage;

  bool get isImporting => status == ImportStatus.importing;

  ImportState copyWith({
    ImportStatus? status,
    ImportResult? result,
    String?       errorMessage,
  }) =>
      ImportState(
        status:       status       ?? this.status,
        result:       result       ?? this.result,
        errorMessage: errorMessage ?? this.errorMessage,
      );
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
  Future<ViewMode> build() =>
      ref.read(viewModeUseCaseProvider).getMode();

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
// dashboardSummaryProvider
// ─────────────────────────────────────────────────────────

final dashboardSummaryProvider =
    FutureProvider.autoDispose<List<MonthlySummary>>((ref) async {
  final viewMode      = await ref.watch(viewModeProvider.future);
  final activeProfile = await ref.watch(activeProfileProvider.future);
  final now = DateTime.now();

  return ref.read(reportUseCaseProvider).getMonthlySummary(
    year:            now.year,
    month:           now.month,
    viewMode:        viewMode,
    activeProfileId: activeProfile?.id,
  );
});

// ─────────────────────────────────────────────────────────
// csvImportStateProvider
// ─────────────────────────────────────────────────────────

final csvImportStateProvider =
    NotifierProvider<CsvImportNotifier, ImportState>(CsvImportNotifier.new);

class CsvImportNotifier extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportState();

  Future<void> execute({
    required File   file,
    required int    profileId,
    required int    accountId,
    required String institutionCode,
  }) async {
    state = state.copyWith(status: ImportStatus.importing);
    try {
      final result = await ref.read(csvImportUseCaseProvider).execute(
        file:            file,
        profileId:       profileId,
        accountId:       accountId,
        institutionCode: institutionCode,
      );
      state = ImportState(status: ImportStatus.done, result: result);
      ref.invalidate(transactionListProvider);
      ref.invalidate(dashboardSummaryProvider);
    } catch (e) {
      state = ImportState(
        status:       ImportStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const ImportState();
}
