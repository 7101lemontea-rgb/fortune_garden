// lib/application/csv_import/csv_import_use_case.dart
//
// SAD v1.1 §4.2 — CsvImportUseCase
// CSV/XLSX 파일 파싱 오케스트레이션.
// Dart Isolate에서 실행. txn_hash 중복 체크 후 SQLite 저장.
// SAD v1.1 §5.2 CSV 가져오기 흐름 기준.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/repositories/i_transaction_repository.dart';
import '../../domain/repositories/i_import_history_repository.dart';
import '../../domain/repositories/i_csv_parser_profile_repository.dart';
import '../../domain/entities/parsed_transaction.dart';
import 'csv_parser_use_case.dart';
import '../category/category_classify_use_case.dart';

// ── Provider ──────────────────────────────────────────
final csvImportUseCaseProvider = Provider<CsvImportUseCase>((ref) {
  return CsvImportUseCase(
    transactionRepo:     ref.read(transactionRepositoryProvider),
    importHistoryRepo:   ref.read(importHistoryRepositoryProvider),
    csvParserProfileRepo: ref.read(csvParserProfileRepositoryProvider),
    classifyUseCase:     ref.read(categoryClassifyUseCaseProvider),
  );
});

// ── UseCase ───────────────────────────────────────────
class CsvImportUseCase {
  const CsvImportUseCase({
    required ITransactionRepository transactionRepo,
    required IImportHistoryRepository importHistoryRepo,
    required ICsvParserProfileRepository csvParserProfileRepo,
    required CategoryClassifyUseCase classifyUseCase,
  })  : _transactionRepo     = transactionRepo,
        _importHistoryRepo   = importHistoryRepo,
        _csvParserProfileRepo = csvParserProfileRepo,
        _classifyUseCase     = classifyUseCase;

  final ITransactionRepository       _transactionRepo;
  final IImportHistoryRepository     _importHistoryRepo;
  final ICsvParserProfileRepository  _csvParserProfileRepo;
  final CategoryClassifyUseCase      _classifyUseCase;

  // ── 실행 ──────────────────────────────────────────

  /// CSV 파일 파싱 → 중복 체크 → DB 저장 → import_history 기록.
  /// SAD v1.1 §5.2 전체 흐름 구현.
  Future<ImportResult> execute({
    required File file,
    required int profileId,
    required int accountId,
    required String institutionCode,
  }) async {
    // 1. 파서 프로필 자동 매칭 (institution_code 기준)
    final parserProfile =
        await _csvParserProfileRepo.getByInstitution(institutionCode);
    if (parserProfile == null) {
      throw StateError(
        '파서 프로필을 찾을 수 없습니다: $institutionCode\n'
        '설정 화면에서 파서 프로필을 먼저 등록해주세요.',
      );
    }

    // 2. Dart Isolate에서 파싱 실행 (UI 스레드 블로킹 방지)
    final parsed = await Isolate.run(() async {
      return CsvParserUseCase().parse(
        file: file,
        parserProfile: parserProfile,
      );
    });

    // 3. 각 거래 처리 (중복 체크 → 카테고리 분류 → INSERT)
    int newRows       = 0;
    int duplicateRows = 0;
    int errorRows     = 0;

    for (final txn in parsed) {
      try {
        // txn_hash 계산 (account_id + date + amount + merchant)
        final hash = _computeHash(accountId, txn);

        // 중복 체크
        final exists = await _transactionRepo.existsByHash(hash);
        if (exists) {
          duplicateRows++;
          continue;
        }

        // 카테고리 자동 분류
        final categoryId = await _classifyUseCase.classify(
          merchant:  txn.merchant,
          profileId: profileId,
        );

        // DB 저장
        await _transactionRepo.upsert(TransactionsCompanion(
          profileId:    Value(profileId),
          accountId:    Value(accountId),
          txnHash:      Value(hash),
          txnDate:      Value(txn.txnDate),
          amount:       Value(txn.amount),
          merchant:     Value(txn.merchant),
          balanceAfter: Value(txn.balanceAfter),
          categoryId:   Value(categoryId),
          isManual:     const Value(0),
          createdAt:    Value(DateTime.now().millisecondsSinceEpoch),
        ));

        newRows++;
      } catch (_) {
        errorRows++;
      }
    }

    final result = ImportResult(
      totalRows:     parsed.length,
      newRows:       newRows,
      duplicateRows: duplicateRows,
      errorRows:     errorRows,
    );

    // 4. import_history 기록
    await _importHistoryRepo.insert(ImportHistoryCompanion(
      profileId:     Value(profileId),
      accountId:     Value(accountId),
      fileName:      Value(file.path.split('/').last),
      importedAt:    Value(DateTime.now().millisecondsSinceEpoch),
      totalRows:     Value(result.totalRows),
      newRows:       Value(result.newRows),
      duplicateRows: Value(result.duplicateRows),
      errorRows:     Value(result.errorRows),
    ));

    return result;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  /// SHA-256 해시 계산 (account_id + txn_date + amount + merchant).
  /// DB ERD v1.1 §4.3 txn_hash 정의 기준.
  String _computeHash(int accountId, ParsedTransaction txn) {
    final raw = '$accountId|${txn.txnDate}|${txn.amount}|${txn.merchant}';
    return sha256.convert(utf8.encode(raw)).toString();
  }
}

// dart:convert utf8 import를 위해 추가
