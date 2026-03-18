// lib/data/repositories/transaction_repository.dart

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../domain/repositories/i_transaction_repository.dart';
import '../../domain/repositories/transaction_filter.dart';

class TransactionRepository implements ITransactionRepository {
  const TransactionRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<Transaction>> getList(TransactionFilter filter) {
    final query = _db.select(_db.transactions);

    // 필터 조건 적용
    query.where((t) {
      Expression<bool> cond = const Constant(true);

      if (filter.profileId != null) {
        cond = cond & t.profileId.equals(filter.profileId!);
      }
      if (filter.accountId != null) {
        cond = cond & t.accountId.equals(filter.accountId!);
      }
      if (filter.categoryId != null) {
        cond = cond & t.categoryId.equals(filter.categoryId!);
      }
      if (filter.fromDate != null) {
        cond = cond & t.txnDate.isBiggerOrEqualValue(filter.fromDate!);
      }
      if (filter.toDate != null) {
        cond = cond & t.txnDate.isSmallerThanValue(filter.toDate!);
      }
      if (filter.isManualOnly != null) {
        cond = cond & t.isManual.equals(filter.isManualOnly! ? 1 : 0);
      }

      return cond;
    });

    // 날짜 내림차순 정렬 + 페이지네이션
    query
      ..orderBy([(t) => OrderingTerm.desc(t.txnDate)])
      ..limit(filter.limit, offset: filter.offset);

    return query.get();
  }

  @override
  Future<Transaction?> getById(int id) =>
      (_db.select(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<void> upsert(TransactionsCompanion companion) =>
      _db.insertTransactionIfNotExists(companion);

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .go();

  @override
  Future<bool> existsByHash(String txnHash) async {
    final row = await (_db.select(_db.transactions)
          ..where((t) => t.txnHash.equals(txnHash)))
        .getSingleOrNull();
    return row != null;
  }
}
