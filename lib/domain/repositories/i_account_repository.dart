// lib/domain/repositories/i_account_repository.dart

import '../../data/database/app_database.dart';

/// 계좌 데이터 접근 추상 인터페이스.
abstract interface class IAccountRepository {
  /// 특정 프로필의 계좌 목록 반환.
  Future<List<Account>> getByProfile(int profileId);

  /// id로 특정 계좌 반환. 없으면 null.
  Future<Account?> getById(int id);

  /// 계좌 삽입 또는 업데이트 (upsert).
  Future<int> upsert(AccountsCompanion companion);

  /// 계좌 잔액 업데이트.
  ///
  /// [balance]가 null이면 잔액은 그대로 두고 [lastSyncedAt]만 갱신한다.
  /// (잔액 컬럼이 없는 CSV 형식에서 가져오기 시각만 기록하는 경우)
  /// [lastSyncedAt]이 null이면 가져오기 시각은 건드리지 않는다.
  Future<void> updateBalance(
    int id,
    int? balance, {
    int? lastSyncedAt,
  });

  /// 계좌 삭제. CASCADE로 transactions·import_history도 삭제됨.
  Future<void> delete(int id);
}
