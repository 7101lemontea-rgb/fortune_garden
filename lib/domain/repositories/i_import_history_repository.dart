// lib/domain/repositories/i_import_history_repository.dart

import '../../data/database/app_database.dart';

/// CSV 가져오기 이력 데이터 접근 추상 인터페이스.
abstract interface class IImportHistoryRepository {
  /// 가져오기 이력 삽입.
  Future<int> insert(ImportHistoryCompanion companion);

  /// 특정 계좌의 가져오기 이력 반환 (최신순).
  /// SCR-007 계좌 관리 화면 ImportHistoryList에서 사용.
  Future<List<ImportHistoryEntry>> getByAccount(
    int accountId, {
    int limit = 20,
  });
}
