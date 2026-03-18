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
  Future<void> updateBalance(int id, int balance);

  /// 계좌 삭제. CASCADE로 transactions·import_history도 삭제됨.
  Future<void> delete(int id);
}
