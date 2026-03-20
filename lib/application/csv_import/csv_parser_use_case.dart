// lib/application/csv_import/csv_parser_use_case.dart
//
// SAD v1.1 §4.2 — CsvParserUseCase
//
// 수정 이력:
//   - parseFromString() 추가: 이미 디코딩된 문자열로 파싱 (Isolate에서 호출)
//   - parse()는 파일 읽기 + _decode() 후 parseFromString() 위임
//   - charset_converter를 parse()에서만 사용 (Isolate 밖 호출 보장)
//
// ※ Isolate에서는 parseFromString()만 호출할 것.
//    charset_converter는 네이티브 플러그인이므로 Isolate 내 호출 불가.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../domain/entities/parsed_transaction.dart';

class CsvParserUseCase {
  const CsvParserUseCase();

  // ── 공개 API ──────────────────────────────────────

  /// 파일에서 직접 파싱.
  /// 내부적으로 인코딩 변환 후 parseFromString() 호출.
  /// ※ charset_converter 사용으로 메인 스레드에서만 호출 가능.
  Future<List<ParsedTransaction>> parse({
    required File             file,
    required CsvParserProfile parserProfile,
  }) async {
    final bytes   = await file.readAsBytes();
    final content = await _decode(bytes, parserProfile.encoding);
    return parseFromString(content: content, parserProfile: parserProfile);
  }

  /// 이미 디코딩된 문자열로 파싱.
  /// Isolate에서 호출 가능 (네이티브 플러그인 미사용).
  /// CsvImportUseCase에서 인코딩 변환 후 Isolate에 전달하는 방식으로 사용.
  List<ParsedTransaction> parseFromString({
    required String           content,
    required CsvParserProfile parserProfile,
  }) {
    // 1. 줄바꿈 정규화
    final normalized = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    // 2. 구분자 확인
    final delimiter = parserProfile.delimiter.isNotEmpty
        ? parserProfile.delimiter[0]
        : ',';

    // 3. 행 파싱
    final rows = _parseCsv(normalized, delimiter);
    if (rows.isEmpty) return [];

    // 4. 헤더 인덱스 매핑
    final header = rows.first
        .map((e) => e.toString().trim())
        .toList();
    final dataRows = rows.skip(parserProfile.skipRows).toList();

    final dateIdx     = header.indexOf(parserProfile.dateCol);
    final amountIdx   = header.indexOf(parserProfile.amountCol);
    final merchantIdx = header.indexOf(parserProfile.merchantCol);

    if (dateIdx < 0 || amountIdx < 0 || merchantIdx < 0) {
      throw FormatException(
        '필수 컬럼을 찾을 수 없습니다.\n'
        '파일 헤더: $header\n'
        '필요 컬럼: ${parserProfile.dateCol}, '
        '${parserProfile.amountCol}, '
        '${parserProfile.merchantCol}',
      );
    }

    // 5. 각 행 변환
    final result = <ParsedTransaction>[];
    for (final row in dataRows) {
      if (row.length <= merchantIdx) continue;
      try {
        final rawDate     = row[dateIdx].toString().trim();
        final rawAmount   = row[amountIdx].toString().trim();
        final rawMerchant = row[merchantIdx].toString().trim();

        if (rawDate.isEmpty || rawAmount.isEmpty || rawMerchant.isEmpty) {
          continue;
        }

        result.add(ParsedTransaction(
          txnDate:  _parseDate(rawDate, parserProfile.dateFormat),
          amount:   _parseAmount(rawAmount),
          merchant: rawMerchant,
        ));
      } catch (_) {
        continue;
      }
    }

    return result;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  /// 바이트 → 문자열 디코딩.
  /// ※ charset_converter 사용 → 메인 스레드에서만 호출 가능.
  Future<String> _decode(Uint8List bytes, String encoding) async {
    final enc = encoding.toUpperCase().replaceAll('-', '');
    if (enc == 'UTF8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return await CharsetConverter.decode(encoding, bytes);
  }

  /// RFC 4180 기반 CSV 파서.
  /// 따옴표 이스케이프, 멀티라인 필드 처리.
  List<List<String>> _parseCsv(String content, String delimiter) {
    final rows         = <List<String>>[];
    final lines        = content.split('\n');
    List<String>? currentRow;
    var currentField   = StringBuffer();
    var inQuotes       = false;

    for (final line in lines) {
      if (line.trim().isEmpty && !inQuotes) continue;

      for (int i = 0; i < line.length; i++) {
        final ch = line[i];

        if (inQuotes) {
          if (ch == '"') {
            if (i + 1 < line.length && line[i + 1] == '"') {
              currentField.write('"');
              i++;
            } else {
              inQuotes = false;
            }
          } else {
            currentField.write(ch);
          }
        } else {
          if (ch == '"') {
            inQuotes = true;
          } else if (ch == delimiter) {
            (currentRow ??= []).add(currentField.toString());
            currentField = StringBuffer();
          } else {
            currentField.write(ch);
          }
        }
      }

      if (inQuotes) {
        currentField.write('\n');
      } else {
        (currentRow ??= []).add(currentField.toString());
        rows.add(currentRow!);
        currentRow   = null;
        currentField = StringBuffer();
      }
    }

    if (currentRow != null || currentField.isNotEmpty) {
      (currentRow ??= []).add(currentField.toString());
      rows.add(currentRow!);
    }

    return rows;
  }

  /// 날짜 문자열 → Unix timestamp (ms)
  int _parseDate(String raw, String format) {
    final dt = DateFormat(format).parse(raw);
    return dt.millisecondsSinceEpoch;
  }

  /// 금액 문자열 → 정수 (원)
  /// △·▲·괄호·음수 부호·쉼표·공백 처리
  int _parseAmount(String raw) {
    String s = raw.trim();
    bool negative = false;

    if (s.startsWith('△') || s.startsWith('▲')) {
      negative = true;
      s = s.substring(1);
    }
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1);
    }
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }

    s = s.replaceAll(RegExp(r'[,\s\t]'), '');
    if (s.contains('.')) s = s.split('.').first;
    if (s.isEmpty) return 0;

    final value = int.parse(s);
    return negative ? -value : value;
  }
}
