// lib/data/repositories/settings_repository.dart

import '../database/app_database.dart';
import '../../domain/repositories/i_settings_repository.dart';

class SettingsRepository implements ISettingsRepository {
  const SettingsRepository(this._db);
  final AppDatabase _db;

  @override
  Future<String?> get(String key, {String? defaultValue}) =>
      _db.getSetting(key, defaultValue: defaultValue);

  @override
  Future<void> set(String key, String? value) =>
      _db.setSetting(key, value);

  @override
  Future<void> delete(String key) =>
      (_db.delete(_db.appSettings)
            ..where((t) => t.key.equals(key)))
          .go();
}
