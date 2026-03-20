// lib/application/csv_import/csv_import_use_case.dart
//
// SAD v1.1 §4.2 — CsvImportUseCase
//
// 수정 이력:
//   - charset_converter (네이티브 플러그인)를 Isolate 밖에서 먼저 실행.
//     EUC-KR 디코딩을 메인 스레드에서 완료 후 UTF-8 문자열을 Isolate에 전달.
//     (Bad state: BackgroundIsolateBinaryMessenger 오류 해결)

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
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
    transactionRepo:      ref.read(transactionRepositoryProvider),
    importHistoryRepo:    ref.read(importHistoryRepositoryProvider),
    csvParserProfileRepo: ref.read(csvParserProfileRepositoryProvider),
    classifyUseCase:      ref.read(categoryClassifyUseCaseProvider),
  );
});

// ── Isolate 전달 파라미터 ──────────────────────────────
// charset_converter가 완료된 UTF-8 문자열을 전달.
class _ParseParams {
  const _ParseParams({
    required this.content,       // 이미 디코딩된 UTF-8 문자열
    required this.parserProfile,
  });
  final String           content;
  final CsvParserProfile parserProfile;
}

// ── UseCase ───────────────────────────────────────────
class CsvImportUseCase {
  const CsvImportUseCase({
    required ITransactionRepository       transactionRepo,
    required IImportHistoryRepository     importHistoryRepo,
    required ICsvParserProfileRepository  csvParserProfileRepo,
    required CategoryClassifyUseCase      classifyUseCase,
  })  : _transactionRepo      = transactionRepo,
        _importHistoryRepo    = importHistoryRepo,
        _csvParserProfileRepo = csvParserProfileRepo,
        _classifyUseCase      = classifyUseCase;

  final ITransactionRepository       _transactionRepo;
  final IImportHistoryRepository     _importHistoryRepo;
  final ICsvParserProfileRepository  _csvParserProfileRepo;
  final CategoryClassifyUseCase      _classifyUseCase;

  Future<ImportResult> execute({
    required File   file,
    required int    profileId,
    required int    accountId,
    required String institutionCode,
  }) async {
    // ── 1. 파서 프로필 자동 매칭 ──────────────────────
    final parserProfile =
        await _csvParserProfileRepo.getByInstitution(institutionCode);

    if (parserProfile == null) {
      throw StateError(
        '[$institutionCode] 파서 프로필을 찾을 수 없습니다.\n'
        '설정 > CSV 파서 프로필에서 먼저 등록해주세요.',
      );
    }

    // ── 2. 인코딩 변환 (메인 스레드에서 먼저 처리) ────
    // charset_converter는 네이티브 플러그인이므로
    // BackgroundIsolateBinaryMessenger 초기화 전에는 Isolate에서 호출 불가.
    // → 파일 읽기 + 디코딩을 메인 스레드에서 완료 후 문자열을 Isolate에 전달.
    final bytes   = await file.readAsBytes();
    final content = await _decodeBytes(bytes, parserProfile.encoding);

    // ── 3. Dart Isolate에서 CSV 파싱 (CPU 집약적 작업) ─
    // 이미 UTF-8 문자열이므로 Isolate 내에서 인코딩 처리 불필요.
    final params = _ParseParams(
      content:       content,
      parserProfile: parserProfile,
    );

    final parsed = await Isolate.run(() {
      return CsvParserUseCase().parseFromString(
        content:       params.content,
        parserProfile: params.parserProfile,
      );
    });

    // ── 4. 거래별 처리: 중복 체크 → 분류 → DB 저장 ───
    int newRows       = 0;
    int duplicateRows = 0;
    int errorRows     = 0;

    for (final txn in parsed) {
      try {
        final hash = _computeHash(accountId, txn);

        final exists = await _transactionRepo.existsByHash(hash);
        if (exists) {
          duplicateRows++;
          continue;
        }

        final categoryId = await _classifyUseCase.classify(
          merchant:  txn.merchant,
          profileId: profileId,
        );

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

    // ── 5. import_history 기록 ────────────────────────
    await _importHistoryRepo.insert(ImportHistoryCompanion(
      profileId:     Value(profileId),
      accountId:     Value(accountId),
      fileName:      Value(file.path.split(RegExp(r'[/\\]')).last),
      importedAt:    Value(DateTime.now().millisecondsSinceEpoch),
      totalRows:     Value(result.totalRows),
      newRows:       Value(result.newRows),
      duplicateRows: Value(result.duplicateRows),
      errorRows:     Value(result.errorRows),
    ));

    return result;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  /// 바이트 → UTF-8 문자열 디코딩.
  /// 메인 스레드에서 실행 (charset_converter 네이티브 플러그인 제약).
  Future<String> _decodeBytes(Uint8List bytes, String encoding) async {
    final enc = encoding.toUpperCase().replaceAll('-', '');
    if (enc == 'UTF8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return await CharsetConverter.decode(encoding, bytes);
  }

  /// SHA-256(accountId|txnDate|amount|merchant)
  String _computeHash(int accountId, ParsedTransaction txn) {
    final raw = '$accountId|${txn.txnDate}|${txn.amount}|${txn.merchant}';
    return sha256.convert(utf8.encode(raw)).toString();
  }
}
