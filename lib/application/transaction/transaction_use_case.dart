// lib/application/transaction/transaction_use_case.dart
//
// SAD v1.1 §4.2 — TransactionUseCase
// 거래 내역 CRUD 및 필터 쿼리.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/repositories/i_transaction_repository.dart';
import '../../domain/repositories/transaction_filter.dart';

// ── Provider ──────────────────────────────────────────
final transactionUseCaseProvider = Provider<TransactionUseCase>((ref) {
  return TransactionUseCase(ref.read(transactionRepositoryProvider));
});

// ── UseCase ───────────────────────────────────────────
class TransactionUseCase {
  const TransactionUseCase(this._transactionRepo);
  final ITransactionRepository _transactionRepo;

  /// 필터 조건으로 거래 목록 반환.
  Future<List<Transaction>> getList(TransactionFilter filter) =>
      _transactionRepo.getList(filter);

  /// id로 특정 거래 반환.
  Future<Transaction?> getById(int id) => _transactionRepo.getById(id);

  /// 거래 수동 입력 또는 수정.
  /// SAD v1.1 §5.3 수동 거래 입력 흐름.
  Future<void> upsert({
    int? id,
    required int profileId,
    required int accountId,
    required int txnDate,
    required int amount,
    required String merchant,
    int? categoryId,
    String? memo,
    int? balanceAfter,
    bool isManual = true,
  }) {
    // 수동 입력 거래의 hash: profileId + date + amount + merchant
    final hash = 'manual_${profileId}_${txnDate}_${amount}_$merchant';

    return _transactionRepo.upsert(TransactionsCompanion(
      id: id != null ? Value(id) : const Value.absent(),
      profileId: Value(profileId),
      accountId: Value(accountId),
      txnHash: Value(hash),
      txnDate: Value(txnDate),
      amount: Value(amount),
      merchant: Value(merchant),
      categoryId: Value(categoryId),
      memo: Value(memo),
      balanceAfter: Value(balanceAfter),
      isManual: Value(isManual ? 1 : 0),
      createdAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// 거래 삭제.
  Future<void> delete(int id) => _transactionRepo.delete(id);

  /// 거래 카테고리·메모·거래처명 수정.
  /// CSV 거래에서 금액·날짜·계좌는 유지하고 나머지 메타만 변경할 때 사용.
  Future<void> updateMeta({
    required int id,
    String? merchant,
    int? categoryId,
    String? memo,
  }) =>
      _transactionRepo.updateMeta(
        id: id,
        merchant: merchant,
        categoryId: categoryId,
        memo: memo,
      );
}
