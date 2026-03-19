// lib/application/report/report_use_case.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';      // ← appDatabaseProvider
import '../../domain/entities/view_mode.dart';

// ── 결과 모델 ──────────────────────────────────────────────

class MonthlySummary {
  const MonthlySummary({
    required this.profileId,
    required this.profileName,
    required this.colorHex,
    required this.income,
    required this.expense,
  });

  final int    profileId;
  final String profileName;
  final String colorHex;
  final int    income;
  final int    expense;

  int get net => income + expense;
}

// ── Provider ──────────────────────────────────────────────

final reportUseCaseProvider = Provider<ReportUseCase>((ref) {
  return ReportUseCase(ref.read(appDatabaseProvider));
});

// ── UseCase ───────────────────────────────────────────────

class ReportUseCase {
  const ReportUseCase(this._db);
  final AppDatabase _db;

  Future<List<MonthlySummary>> getMonthlySummary({
    required int      year,
    required int      month,
    required ViewMode viewMode,
    int?              activeProfileId,
  }) async {
    final range = _monthRange(year, month);

    if (viewMode == ViewMode.personal) {
      if (activeProfileId == null) return [];

      final row = await _db.getMonthlySummary(
        profileId:  activeProfileId,
        monthStart: range.$1,
        monthEnd:   range.$2,
      );

      final profile = await (_db.select(_db.profiles)
            ..where((t) => t.id.equals(activeProfileId)))
          .getSingleOrNull();
      if (profile == null) return [];

      return [
        MonthlySummary(
          profileId:   profile.id,
          profileName: profile.name,
          colorHex:    profile.colorHex,
          income:      row.income,
          expense:     row.expense,
        ),
      ];
    } else {
      final rows = await _db.getCombinedDashboard(
        monthStart: range.$1,
        monthEnd:   range.$2,
      );

      return rows.map((row) => MonthlySummary(
        profileId:   0,
        profileName: row.read<String>('name'),
        colorHex:    row.read<String>('color_hex'),
        income:      row.read<int>('income'),
        expense:     row.read<int>('expense'),
      )).toList();
    }
  }

  (int, int) _monthRange(int year, int month) {
    final start = DateTime(year, month, 1);
    final end   = DateTime(year, month + 1, 1);
    return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
  }
}
