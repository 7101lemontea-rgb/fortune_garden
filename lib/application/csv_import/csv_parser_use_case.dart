// lib/application/csv_import/csv_parser_use_case.dart
//
// SAD v1.1 §4.2 — CsvParserUseCase
// csv 패키지 의존성 제거 → 순수 Dart 내장 파싱으로 교체.
// RFC 4180 기반 직접 구현: 따옴표 이스케이프 처리 포함.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../domain/entities/parsed_transaction.dart';

class CsvParserUseCase {
  const CsvParserUseCase();

  Future<List<ParsedTransaction>> parse({
    required File file,
    required CsvParserProfile parserProfile,
  }) async {
    // 1. 파일 바이트 읽기
    final bytes = await file.readAsBytes();

    // 2. 인코딩 변환
    final content = await _decode(bytes, parserProfile.encoding);

    // 3. 줄바꿈 정규화 후 행 파싱
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final delimiter =
        parserProfile.delimiter.isNotEmpty ? parserProfile.delimiter[0] : ',';

    final rows = _parseCsv(normalized, delimiter);

    if (rows.isEmpty) return [];

    // 4. 헤더 인덱스 매핑
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final dataRows = rows.skip(parserProfile.skipRows).toList();

    final dateIdx = header.indexOf(parserProfile.dateCol);
    final amountIdx = header.indexOf(parserProfile.amountCol);
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
        final rawDate = row[dateIdx].toString().trim();
        final rawAmount = row[amountIdx].toString().trim();
        final rawMerchant = row[merchantIdx].toString().trim();

        if (rawDate.isEmpty || rawAmount.isEmpty || rawMerchant.isEmpty) {
          continue;
        }

        result.add(ParsedTransaction(
          txnDate: _parseDate(rawDate, parserProfile.dateFormat),
          amount: _parseAmount(rawAmount),
          merchant: rawMerchant,
        ));
      } catch (_) {
        continue;
      }
    }

    return result;
  }

  // ── CSV 파서 (RFC 4180 기반) ───────────────────────
  /// 따옴표로 감싼 필드 내 콤마·줄바꿈 처리 포함.
  List<List<String>> _parseCsv(String content, String delimiter) {
    final rows = <List<String>>[];
    final lines = content.split('\n');

    List<String>? currentRow;
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;

    for (final line in lines) {
      if (line.trim().isEmpty && !inQuotes) continue;

      for (int i = 0; i < line.length; i++) {
        final ch = line[i];

        if (inQuotes) {
          if (ch == '"') {
            // 다음 문자도 " 이면 이스케이프된 따옴표
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
        // 따옴표 안에서 줄바꿈 → 멀티라인 필드
        currentField.write('\n');
      } else {
        (currentRow ??= []).add(currentField.toString());
        rows.add(currentRow!);
        currentRow = null;
        currentField = StringBuffer();
      }
    }

    // 마지막 행 처리 (줄바꿈 없이 파일 끝나는 경우)
    if (currentRow != null || currentField.isNotEmpty) {
      (currentRow ??= []).add(currentField.toString());
      rows.add(currentRow!);
    }

    return rows;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────

  Future<String> _decode(Uint8List bytes, String encoding) async {
    final enc = encoding.toUpperCase().replaceAll('-', '');
    if (enc == 'UTF8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return await CharsetConverter.decode(encoding, bytes);
  }

  int _parseDate(String raw, String format) {
    final dt = DateFormat(format).parse(raw);
    return dt.millisecondsSinceEpoch;
  }

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
