// lib/application/csv_import/csv_import_use_case.dart
//
// SAD v1.1 §4.2 — CsvImportUseCase
//
// 수정 이력:
//   - charset_converter (네이티브 플러그인)를 Isolate 밖에서 먼저 실행.
//     EUC-KR 디코딩을 메인 스레드에서 완료 후 UTF-8 문자열을 Isolate에 전달.
//     (Bad state: BackgroundIsolateBinaryMessenger 오류 해결)
//   - v1.2 텍스트 붙여넣기 지원
//       · executeFromText(): 파일 없이 붙여넣은 문자열로 가져오기
//       · 중복 해시에 잔액 포함 (같은 초 거래 구분)
//       · 잔액 연속성 검증 → 누락 의심 구간 경고
//       · 거래구분(txnType) 분류 폴백
//       · 가져오기 후 accounts.balance / lastSyncedAt 갱신

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:charset_converter/charset_converter.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/repositories/i_transaction_repository.dart';
import '../../domain/repositories/i_import_history_repository.dart';
import '../../domain/repositories/i_csv_parser_profile_repository.dart';
import '../../domain/repositories/i_account_repository.dart';
import '../../domain/entities/parsed_transaction.dart';
import 'csv_parser_use_case.dart';
import '../category/category_classify_use_case.dart';

// ── Provider ──────────────────────────────────────────
final csvImportUseCaseProvider = Provider<CsvImportUseCase>((ref) {
  return CsvImportUseCase(
    transactionRepo:      ref.read(transactionRepositoryProvider),
    importHistoryRepo:    ref.read(importHistoryRepositoryProvider),
    csvParserProfileRepo: ref.read(csvParserProfileRepositoryProvider),
    accountRepo:          ref.read(accountRepositoryProvider),
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
    required IAccountRepository           accountRepo,
    required CategoryClassifyUseCase      classifyUseCase,
  })  : _transactionRepo      = transactionRepo,
        _importHistoryRepo    = importHistoryRepo,
        _csvParserProfileRepo = csvParserProfileRepo,
        _accountRepo          = accountRepo,
        _classifyUseCase      = classifyUseCase;

  final ITransactionRepository       _transactionRepo;
  final IImportHistoryRepository     _importHistoryRepo;
  final ICsvParserProfileRepository  _csvParserProfileRepo;
  final IAccountRepository           _accountRepo;
  final CategoryClassifyUseCase      _classifyUseCase;

  // ════════════════════════════════════════════════════
  // ▣  CSV 파일 가져오기
  // ════════════════════════════════════════════════════

  Future<ImportResult> execute({
    required File   file,
    required int    profileId,
    required int    accountId,
    required String institutionCode,
  }) async {
    final parserProfile = await _requireParserProfile(
      institutionCode: institutionCode,
      sourceType:      'file',
    );

    // ── 인코딩 변환 (메인 스레드에서 먼저 처리) ────────
    // charset_converter는 네이티브 플러그인이므로
    // BackgroundIsolateBinaryMessenger 초기화 전에는 Isolate에서 호출 불가.
    // → 파일 읽기 + 디코딩을 메인 스레드에서 완료 후 문자열을 Isolate에 전달.
    final bytes   = await file.readAsBytes();
    final content = await _decodeBytes(bytes, parserProfile.encoding);

    final parsed = await _parseInIsolate(content, parserProfile);

    return _store(
      parsed:     parsed,
      profileId:  profileId,
      accountId:  accountId,
      sourceName: file.path.split(RegExp(r'[/\\]')).last,
    );
  }

  // ════════════════════════════════════════════════════
  // ▣  텍스트 붙여넣기 가져오기  ★ v1.2 신규
  // ════════════════════════════════════════════════════

  /// 은행 웹 화면의 거래내역 표를 복사해 붙여넣은 문자열로 가져오기.
  /// 파일 입출력·인코딩 변환이 없어 파일 방식보다 단계가 짧다.
  Future<ImportResult> executeFromText({
    required String content,
    required int    profileId,
    required int    accountId,
    required String institutionCode,
    String          sourceName = '붙여넣기',
  }) async {
    if (content.trim().isEmpty) {
      throw StateError('붙여넣은 내용이 없습니다.');
    }

    final parserProfile = await _requireParserProfile(
      institutionCode: institutionCode,
      sourceType:      'paste',
    );

    final parsed = await _parseInIsolate(content, parserProfile);

    return _store(
      parsed:     parsed,
      profileId:  profileId,
      accountId:  accountId,
      sourceName: sourceName,
    );
  }

  // ════════════════════════════════════════════════════
  // ▣  공통 처리
  // ════════════════════════════════════════════════════

  Future<CsvParserProfile> _requireParserProfile({
    required String institutionCode,
    required String sourceType,
  }) async {
    final profile = await _csvParserProfileRepo.getByInstitution(
      institutionCode,
      sourceType: sourceType,
    );

    if (profile == null) {
      final label = sourceType == 'paste' ? '붙여넣기' : 'CSV 파일';
      throw StateError(
        '[$institutionCode] $label 파서 프로필을 찾을 수 없습니다.\n'
        '설정 > CSV 파서 프로필에서 먼저 등록해주세요.',
      );
    }
    return profile;
  }

  /// CPU 집약적인 파싱을 Isolate에서 실행.
  /// 전달되는 content는 이미 UTF-8 문자열이므로 Isolate 내 인코딩 처리 불필요.
  Future<List<ParsedTransaction>> _parseInIsolate(
    String           content,
    CsvParserProfile parserProfile,
  ) {
    final params = _ParseParams(
      content:       content,
      parserProfile: parserProfile,
    );

    return Isolate.run(() {
      return CsvParserUseCase().parseFromString(
        content:       params.content,
        parserProfile: params.parserProfile,
      );
    });
  }

  /// 파싱 결과를 중복 체크 → 분류 → DB 저장 → 이력 기록까지 처리.
  /// [parsed]는 과거순(오름차순)으로 정렬되어 있어야 한다.
  Future<ImportResult> _store({
    required List<ParsedTransaction> parsed,
    required int                     profileId,
    required int                     accountId,
    required String                  sourceName,
  }) async {
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

        final categoryId = await _classify(txn, profileId);

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
      warnings:      _checkBalanceContinuity(parsed),
    );

    // ── 계좌 잔액·가져오기 시각 갱신 ──────────────────
    // parsed는 과거순이므로 마지막 잔액이 가장 최신 값.
    final latestBalance = parsed.reversed
        .firstWhere((t) => t.balanceAfter != null,
            orElse: () => const ParsedTransaction(
                  txnDate: 0,
                  amount: 0,
                  merchant: '',
                ))
        .balanceAfter;

    await _accountRepo.updateBalance(
      accountId,
      latestBalance,
      lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // ── import_history 기록 ──────────────────────────
    await _importHistoryRepo.insert(ImportHistoryCompanion(
      profileId:     Value(profileId),
      accountId:     Value(accountId),
      fileName:      Value(sourceName),
      importedAt:    Value(DateTime.now().millisecondsSinceEpoch),
      totalRows:     Value(result.totalRows),
      newRows:       Value(result.newRows),
      duplicateRows: Value(result.duplicateRows),
      errorRows:     Value(result.errorRows),
    ));

    return result;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  /// 거래처명으로 먼저 분류하고, 미분류면 거래구분으로 한 번 더 시도.
  Future<int?> _classify(ParsedTransaction txn, int profileId) async {
    final byMerchant = await _classifyUseCase.classify(
      merchant:  txn.merchant,
      profileId: profileId,
    );
    if (byMerchant != null) return byMerchant;

    final type = txn.txnType;
    if (type == null || type.isEmpty) return null;

    return _classifyUseCase.classify(
      merchant:  type,
      profileId: profileId,
    );
  }

  /// 바이트 → UTF-8 문자열 디코딩.
  /// 메인 스레드에서 실행 (charset_converter 네이티브 플러그인 제약).
  Future<String> _decodeBytes(Uint8List bytes, String encoding) async {
    final enc = encoding.toUpperCase().replaceAll('-', '');
    if (enc == 'UTF8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return await CharsetConverter.decode(encoding, bytes);
  }

  /// SHA-256(accountId|txnDate|amount|merchant[|balanceAfter])
  ///
  /// 잔액이 있으면 해시에 포함한다. 같은 초에 발생한 동일 금액·동일 내용의
  /// 서로 다른 거래를 구분하기 위함.
  /// 잔액이 없는 기존 CSV 형식은 과거와 같은 해시를 유지하므로
  /// 이미 저장된 거래의 중복 판정이 깨지지 않는다.
  String _computeHash(int accountId, ParsedTransaction txn) {
    final base = '$accountId|${txn.txnDate}|${txn.amount}|${txn.merchant}';
    final raw =
        txn.balanceAfter != null ? '$base|${txn.balanceAfter}' : base;
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// 잔액 연속성 검증.
  /// 이전 행의 잔액 + 현재 행의 금액 == 현재 행의 잔액이어야 한다.
  /// 어긋나는 구간은 조회 기간에 누락된 거래가 있다는 신호.
  List<String> _checkBalanceContinuity(List<ParsedTransaction> parsed) {
    final rows = parsed.where((t) => t.balanceAfter != null).toList();
    if (rows.length < 2) return const [];

    var mismatches = 0;
    int? firstMismatchAt;

    for (var i = 1; i < rows.length; i++) {
      final expected = rows[i - 1].balanceAfter! + rows[i].amount;
      if (expected != rows[i].balanceAfter) {
        mismatches++;
        firstMismatchAt ??= rows[i].txnDate;
      }
    }

    if (mismatches == 0) return const [];

    final at = DateFormat('yyyy-MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(firstMismatchAt!));

    return [
      '잔액 흐름이 맞지 않는 구간이 $mismatches곳 있습니다 (처음: $at). '
          '조회 기간 사이에 누락된 거래가 있을 수 있습니다.',
    ];
  }
}
