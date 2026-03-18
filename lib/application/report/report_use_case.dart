// lib/application/report/report_use_case.dart
//
// SAD v1.1 §4.2 — ReportUseCase
// 뷰 모드에 따라 단일 또는 합산 리포트 데이터 반환.
// DB ERD v1.1 §6.1~6.2 쿼리 패턴 기준.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/view_mode.dart';

// ── 결과 모델 ──────────────────────────────────────────

/// 단일 프로필 월별 수입/지출 요약.
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

  /// 수입 합계 (양수)
  final int income;

  /// 지출 합계 (음수 → 절댓값으로 반환)
  final int expense;

  /// 순수지 = income + expense (expense가 음수이므로)
  int get net => income + expense;
}

// ── Provider ──────────────────────────────────────────
final reportUseCaseProvider = Provider<ReportUseCase>((ref) {
  return ReportUseCase(ref.read(appDatabaseProvider));
});

// ── UseCase ───────────────────────────────────────────
class ReportUseCase {
  const ReportUseCase(this._db);
  final AppDatabase _db;

  /// 월별 수입/지출 요약 반환.
  /// [viewMode]에 따라 개인 또는 통합 뷰 결과 반환.
  Future<List<MonthlySummary>> getMonthlySummary({
    required int year,
    required int month,
    required ViewMode viewMode,
    int? activeProfileId, // 개인 뷰일 때 사용
  }) async {
    final range = _monthRange(year, month);

    if (viewMode == ViewMode.personal) {
      // ── 개인 뷰: 단일 프로필 ──
      if (activeProfileId == null) return [];

      final row = await _db.getMonthlySummary(
        profileId:  activeProfileId,
        monthStart: range.$1,
        monthEnd:   range.$2,
      );

      // 프로필 정보 조회
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
      // ── 통합 뷰: 두 프로필 합산 ──
      final rows = await _db.getCombinedDashboard(
        monthStart: range.$1,
        monthEnd:   range.$2,
      );

      return rows.map((row) {
        return MonthlySummary(
          profileId:   0, // getCombinedDashboard는 profileId를 반환하지 않음
          profileName: row.read<String>('name'),
          colorHex:    row.read<String>('color_hex'),
          income:      row.read<int>('income'),
          expense:     row.read<int>('expense'),
        );
      }).toList();
    }
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  /// [year]년 [month]월의 시작·종료 Unix timestamp (ms) 반환.
  (int, int) _monthRange(int year, int month) {
    final start = DateTime(year, month, 1);
    final end   = DateTime(year, month + 1, 1);
    return (
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    );
  }
}
