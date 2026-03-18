// lib/data/repositories/account_repository.dart

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../domain/repositories/i_account_repository.dart';

class AccountRepository implements IAccountRepository {
  const AccountRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<Account>> getByProfile(int profileId) =>
      (_db.select(_db.accounts)
            ..where((t) => t.profileId.equals(profileId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  @override
  Future<Account?> getById(int id) =>
      (_db.select(_db.accounts)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<int> upsert(AccountsCompanion companion) =>
      _db.into(_db.accounts).insertOnConflictUpdate(companion);

  @override
  Future<void> updateBalance(int id, int balance) =>
      (_db.update(_db.accounts)
            ..where((t) => t.id.equals(id)))
          .write(AccountsCompanion(balance: Value(balance)));

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.accounts)
            ..where((t) => t.id.equals(id)))
          .go();
}
