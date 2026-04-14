// lib/domain/repositories/i_transaction_repository.dart

import '../../data/database/app_database.dart';
import 'transaction_filter.dart';

/// 거래 내역 데이터 접근 추상 인터페이스.
abstract interface class ITransactionRepository {
  /// 필터 조건으로 거래 목록 반환.
  /// offset·limit으로 페이지네이션 지원.
  Future<List<Transaction>> getList(TransactionFilter filter);

  /// id로 특정 거래 반환. 없으면 null.
  Future<Transaction?> getById(int id);

  /// 거래 삽입 또는 업데이트 (upsert).
  /// txnHash UNIQUE 제약으로 중복 자동 무시.
  Future<void> upsert(TransactionsCompanion companion);

  /// 거래 카테고리·메모·거래처명만 부분 업데이트.
  /// CSV 거래에서 금액·날짜·계좌 원본을 유지할 때 사용.
  Future<void> updateMeta({
    required int id,
    String? merchant,
    int? categoryId,
    String? memo,
  });

  /// 거래 삭제.
  Future<void> delete(int id);

  /// txnHash 존재 여부 확인. CSV 가져오기 전 중복 체크에 사용.
  Future<bool> existsByHash(String txnHash);
}
