// lib/data/repositories/profile_repository.dart

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../domain/repositories/i_profile_repository.dart';

class ProfileRepository implements IProfileRepository {
  const ProfileRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<Profile>> getAll() =>
      _db.select(_db.profiles).get();

  @override
  Future<Profile?> getById(int id) =>
      (_db.select(_db.profiles)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<void> upsert(ProfilesCompanion companion) =>
      _db.into(_db.profiles).insertOnConflictUpdate(companion);

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.profiles)
            ..where((t) => t.id.equals(id)))
          .go();
}
