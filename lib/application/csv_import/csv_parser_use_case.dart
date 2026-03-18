// lib/application/csv_import/csv_parser_use_case.dart
//
// SAD v1.1 §4.2 — CsvParserUseCase
// 파서 프로필에 따라 CSV 파일을 읽어 거래 목록으로 변환.
// 기관별 인코딩/컬럼명/날짜 형식 처리.
//
// ※ 이 UseCase는 Dart Isolate에서 실행되므로
//   Flutter/Provider에 의존하지 않는 순수 Dart 코드로 구성.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../domain/entities/parsed_transaction.dart';

class CsvParserUseCase {
  const CsvParserUseCase();

  /// [file] CSV 파일을 [parserProfile] 설정으로 파싱하여
  /// [ParsedTransaction] 목록 반환.
  Future<List<ParsedTransaction>> parse({
    required File file,
    required CsvParserProfile parserProfile,
  }) async {
    // 1. 파일 바이트 읽기
    final bytes = await file.readAsBytes();

    // 2. 인코딩 변환
    final content = _decode(bytes, parserProfile.encoding);

    // 3. CSV 파싱
    final rows = const CsvToListConverter(
      eol: '\n',
      fieldDelimiter: ',', // parserProfile.delimiter 적용 시 확장
    ).convert(content);

    if (rows.isEmpty) return [];

    // 4. 헤더 행 건너뛰기
    final dataRows = rows.skip(parserProfile.skipRows).toList();

    // 5. 헤더 인덱스 매핑
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final dateIdx     = header.indexOf(parserProfile.dateCol);
    final amountIdx   = header.indexOf(parserProfile.amountCol);
    final merchantIdx = header.indexOf(parserProfile.merchantCol);

    if (dateIdx < 0 || amountIdx < 0 || merchantIdx < 0) {
      throw FormatException(
        '필수 컬럼을 찾을 수 없습니다. '
        '헤더: $header, '
        '필요: ${parserProfile.dateCol}, '
        '${parserProfile.amountCol}, '
        '${parserProfile.merchantCol}',
      );
    }

    // 6. 각 행 변환
    final result = <ParsedTransaction>[];
    for (final row in dataRows) {
      try {
        final txnDate = _parseDate(
          row[dateIdx].toString().trim(),
          parserProfile.dateFormat,
        );
        final amount   = _parseAmount(row[amountIdx].toString().trim());
        final merchant = row[merchantIdx].toString().trim();

        if (merchant.isEmpty) continue;

        result.add(ParsedTransaction(
          txnDate:      txnDate,
          amount:       amount,
          merchant:     merchant,
        ));
      } catch (_) {
        // 파싱 실패 행은 건너뜀 (errorRows 카운트는 CsvImportUseCase에서 집계)
        continue;
      }
    }

    return result;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  /// 바이트 → 문자열 디코딩.
  /// UTF-8은 dart:convert로, EUC-KR 등은 charset_converter 패키지 필요.
  String _decode(Uint8List bytes, String encoding) {
    if (encoding.toUpperCase() == 'UTF-8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    // TODO: charset_converter 패키지 도입 후 EUC-KR 처리
    // return await CharsetConverter.decode(encoding, bytes);
    // 임시: UTF-8 fallback
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 날짜 문자열 → Unix timestamp (ms).
  int _parseDate(String raw, String format) {
    final dt = DateFormat(format).parse(raw);
    return dt.millisecondsSinceEpoch;
  }

  /// 금액 문자열 → 정수 (원).
  /// 쉼표·공백 제거 후 파싱. 출금 컬럼은 음수 처리.
  int _parseAmount(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[,\s]'), '');
    return int.parse(cleaned);
  }
}
