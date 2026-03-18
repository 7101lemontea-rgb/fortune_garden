// lib/data/repositories/repository_providers.dart
//
// 7개 Repository를 Riverpod Provider로 노출.
// UseCase는 이 Provider를 통해 Repository 인스턴스를 획득한다.
//
// 사용 예:
//   final profiles = await ref.read(profileRepositoryProvider).getAll();

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_provider.dart';
import 'profile_repository.dart';
import 'account_repository.dart';
import 'transaction_repository.dart';
import 'category_repository.dart';
import 'csv_parser_profile_repository.dart';
import 'import_history_repository.dart';
import 'settings_repository.dart';

import '../../domain/repositories/i_profile_repository.dart';
import '../../domain/repositories/i_account_repository.dart';
import '../../domain/repositories/i_transaction_repository.dart';
import '../../domain/repositories/i_category_repository.dart';
import '../../domain/repositories/i_csv_parser_profile_repository.dart';
import '../../domain/repositories/i_import_history_repository.dart';
import '../../domain/repositories/i_settings_repository.dart';

final profileRepositoryProvider = Provider<IProfileRepository>((ref) {
  return ProfileRepository(ref.read(appDatabaseProvider));
});

final accountRepositoryProvider = Provider<IAccountRepository>((ref) {
  return AccountRepository(ref.read(appDatabaseProvider));
});

final transactionRepositoryProvider = Provider<ITransactionRepository>((ref) {
  return TransactionRepository(ref.read(appDatabaseProvider));
});

final categoryRepositoryProvider = Provider<ICategoryRepository>((ref) {
  return CategoryRepository(ref.read(appDatabaseProvider));
});

final csvParserProfileRepositoryProvider =
    Provider<ICsvParserProfileRepository>((ref) {
  return CsvParserProfileRepository(ref.read(appDatabaseProvider));
});

final importHistoryRepositoryProvider =
    Provider<IImportHistoryRepository>((ref) {
  return ImportHistoryRepository(ref.read(appDatabaseProvider));
});

final settingsRepositoryProvider = Provider<ISettingsRepository>((ref) {
  return SettingsRepository(ref.read(appDatabaseProvider));
});
