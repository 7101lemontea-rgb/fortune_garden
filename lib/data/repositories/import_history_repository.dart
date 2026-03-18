// lib/data/repositories/import_history_repository.dart

import '../database/app_database.dart';
import '../../domain/repositories/i_import_history_repository.dart';

class ImportHistoryRepository implements IImportHistoryRepository {
  const ImportHistoryRepository(this._db);
  final AppDatabase _db;

  @override
  Future<int> insert(ImportHistoryCompanion companion) =>
      _db.into(_db.importHistory).insert(companion);

  @override
  Future<List<ImportHistoryEntry>> getByAccount(
    int accountId, {
    int limit = 20,
  }) =>
      _db.getImportHistory(accountId: accountId, limit: limit);
}
