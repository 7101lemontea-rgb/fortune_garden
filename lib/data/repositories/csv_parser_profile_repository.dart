// lib/data/repositories/csv_parser_profile_repository.dart

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../domain/repositories/i_csv_parser_profile_repository.dart';

class CsvParserProfileRepository implements ICsvParserProfileRepository {
  const CsvParserProfileRepository(this._db);
  final AppDatabase _db;

  @override
  Future<CsvParserProfile?> getByInstitution(String institutionCode) =>
      _db.getParserProfile(institutionCode: institutionCode);

  @override
  Future<List<CsvParserProfile>> getAll() =>
      (_db.select(_db.csvParserProfiles)
            ..orderBy([(t) => OrderingTerm.asc(t.institutionCode)]))
          .get();

  @override
  Future<int> upsert(CsvParserProfilesCompanion companion) =>
      _db.into(_db.csvParserProfiles).insertOnConflictUpdate(companion);

  @override
  Future<void> deactivate(int id) =>
      (_db.update(_db.csvParserProfiles)
            ..where((t) => t.id.equals(id)))
          .write(const CsvParserProfilesCompanion(
            isActive: Value(0),
          ));
}
