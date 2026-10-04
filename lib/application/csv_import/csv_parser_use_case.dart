// lib/application/csv_import/csv_parser_use_case.dart
//
// SAD v1.1 §4.2 — CsvParserUseCase
//
// 수정 이력:
//   - parseFromString() 추가: 이미 디코딩된 문자열로 파싱 (Isolate에서 호출)
//   - parse()는 파일 읽기 + _decode() 후 parseFromString() 위임
//   - charset_converter를 parse()에서만 사용 (Isolate 밖 호출 보장)
//   - v1.2 텍스트 붙여넣기 지원
//       · headerKeyword로 표 위 메타 줄을 건너뛰고 헤더 행 탐색
//       · withdrawCol/depositCol 입출금 분리 형식 (amount = 입금 - 출금)
//       · balanceCol 거래 후 잔액, txnTypeCol 거래구분 수집
//       · rowOrder='desc'이면 저장 전 과거순으로 뒤집기
//       · 붙여넣기 시 탭이 공백으로 변형된 텍스트 자동 보정
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

// ─────────────────────────────────────────────────────────
// 붙여넣기 열 머리글 동의어 (은행 공통)
// ─────────────────────────────────────────────────────────
//
// 한국 은행 거래내역의 열 이름은 은행마다 조금씩 다르다.
// 뜻이 같은 표현을 모아 두고, 붙여넣기 파싱 시 자동으로 매칭한다.
// 더 구체적인 이름을 앞에 둔다('거래금액'을 '금액'보다 먼저 등).
//
// ※ 실제 은행 머리글이 여기에 없으면 해당 열을 못 찾아 "가져오기 실패"로
//   머리글이 표시된다(조용한 0건이 아님). 새 표현은 이 목록에 추가하면 된다.

const List<String> _dateSynonyms = [
  '거래일시', '거래일자', '거래날짜', '거래일', '거래 일시', '거래 일자',
  '일자', '날짜', '이용일시', '이용일자', '이용일',
];

const List<String> _typeSynonyms = [
  '거래구분', '구분', '거래유형', '유형', '적요구분',
];

const List<String> _merchantSynonyms = [
  '기재내용', '적요', '거래내용', '내용', '가맹점명', '가맹점',
  '거래처', '거래기관', '보내는분', '받는분', '받는분/보내는분', '상대방',
  '메모', '내역',
];

const List<String> _withdrawSynonyms = [
  '출금금액', '출금액', '출금', '지급금액', '지급', '보낸금액', '결제금액',
];

const List<String> _depositSynonyms = [
  '입금금액', '입금액', '입금', '받은금액',
];

// 출금·입금이 한 열에 +/-로 들어오는 형식(토스뱅크 등).
const List<String> _amountSynonyms = [
  '거래금액', '금액', '거래 금액',
];

const List<String> _balanceSynonyms = [
  '거래후잔액', '거래 후 잔액', '잔액', '잔고', '거래후 잔액',
];

// ─────────────────────────────────────────────────────────
// 행 분리 방식
// ─────────────────────────────────────────────────────────

/// 한 줄을 셀로 나누는 방식.
/// - [char]: 단일 문자 구분자. RFC 4180 따옴표 처리 포함 (CSV 파일용).
/// - [whitespaceRun]: 공백 2칸 이상 또는 탭. 웹 표를 복사해 붙여넣었을 때
///   탭이 공백으로 변형된 경우를 처리 (셀 내부의 단일 공백은 보존).
class _Splitter {
  const _Splitter.char(String this.char) : whitespaceRun = false;
  const _Splitter.whitespaceRun()
      : char = null,
        whitespaceRun = true;

  final String? char;
  final bool whitespaceRun;
}

// ─────────────────────────────────────────────────────────
// 컬럼 배치 (헤더 분석 결과)
// ─────────────────────────────────────────────────────────

class _Layout {
  const _Layout({
    required this.firstDataRow,
    required this.dateIdx,
    required this.merchantIdx,
    this.amountIdx,
    this.withdrawIdx,
    this.depositIdx,
    this.balanceIdx,
    this.txnTypeIdx,
  });

  final int firstDataRow;
  final int dateIdx;
  final int merchantIdx;
  final int? amountIdx;
  final int? withdrawIdx;
  final int? depositIdx;
  final int? balanceIdx;
  final int? txnTypeIdx;

  /// 출금·입금이 분리된 형식인지 여부.
  bool get isSplitAmount => withdrawIdx != null || depositIdx != null;

  /// 행 길이 검증에 쓰는 최대 사용 인덱스.
  int get maxIdx => [
        dateIdx,
        merchantIdx,
        amountIdx,
        withdrawIdx,
        depositIdx,
        balanceIdx,
        txnTypeIdx,
      ].whereType<int>().reduce((a, b) => a > b ? a : b);
}

// ─────────────────────────────────────────────────────────
// UseCase
// ─────────────────────────────────────────────────────────

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
  /// CSV 파일·텍스트 붙여넣기 모두 이 메서드를 공유한다.
  List<ParsedTransaction> parseFromString({
    required String           content,
    required CsvParserProfile parserProfile,
  }) {
    // 1. 줄바꿈 정규화
    final normalized = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    // 2. 구분자 후보를 순서대로 시도.
    //    헤더에서 필수 컬럼을 찾아내는 첫 후보를 채택한다.
    List<List<String>>? rows;
    _Layout? layout;

    for (final splitter in _splitterCandidates(parserProfile)) {
      final candidateRows = _splitRows(normalized, splitter);
      if (candidateRows.isEmpty) continue;

      final candidateLayout = _resolveLayout(candidateRows, parserProfile);
      if (candidateLayout != null) {
        rows   = candidateRows;
        layout = candidateLayout;
        break;
      }
    }

    if (rows == null || layout == null) {
      throw FormatException(_layoutErrorMessage(normalized, parserProfile));
    }

    // 3. 각 행 변환
    final result = <ParsedTransaction>[];
    for (final row in rows.skip(layout.firstDataRow)) {
      if (row.length <= layout.maxIdx) continue;
      try {
        final parsed = _parseRow(row, layout, parserProfile);
        if (parsed != null) result.add(parsed);
      } catch (_) {
        // 합계 줄·주석 줄 등 거래가 아닌 행은 건너뛴다.
        continue;
      }
    }

    // 4. 원본이 최신순이면 과거순으로 뒤집는다.
    //    같은 초에 발생한 거래의 잔액 흐름을 바로잡기 위해 필요.
    if (parserProfile.rowOrder.toLowerCase() == 'desc') {
      return result.reversed.toList();
    }
    return result;
  }

  // ── 내부: 행 1건 변환 ─────────────────────────────

  ParsedTransaction? _parseRow(
    List<String>     row,
    _Layout          layout,
    CsvParserProfile profile,
  ) {
    final rawDate     = row[layout.dateIdx].trim();
    final rawMerchant = row[layout.merchantIdx].trim();
    if (rawDate.isEmpty) return null;

    final int amount;
    if (layout.isSplitAmount) {
      // 출금·입금 분리 형식: 지출 음수, 수입 양수 (프로젝트 부호 규칙)
      final withdraw = layout.withdrawIdx != null
          ? _parseAmount(row[layout.withdrawIdx!]).abs()
          : 0;
      final deposit = layout.depositIdx != null
          ? _parseAmount(row[layout.depositIdx!]).abs()
          : 0;
      // 양쪽 모두 0인 행은 거래가 아니거나 헤더 반복 줄
      if (withdraw == 0 && deposit == 0) return null;
      amount = deposit - withdraw;
    } else {
      final rawAmount = row[layout.amountIdx!].trim();
      if (rawAmount.isEmpty) return null;
      amount = _parseAmount(rawAmount);
    }

    if (rawMerchant.isEmpty && !layout.isSplitAmount) return null;

    final txnType = layout.txnTypeIdx != null
        ? row[layout.txnTypeIdx!].trim()
        : null;

    return ParsedTransaction(
      txnDate: _parseDate(rawDate, profile.dateFormat),
      amount: amount,
      // 기재내용이 비면 거래구분으로 대체 (잔액만 있는 이자 행 등)
      merchant: rawMerchant.isNotEmpty
          ? rawMerchant
          : (txnType?.isNotEmpty == true ? txnType! : '(내용 없음)'),
      balanceAfter: layout.balanceIdx != null
          ? _parseAmount(row[layout.balanceIdx!])
          : null,
      txnType: (txnType != null && txnType.isNotEmpty) ? txnType : null,
    );
  }

  // ── 내부: 구분자 후보 ─────────────────────────────

  /// 프로필에 지정된 구분자를 먼저 시도하고,
  /// 붙여넣기 모드에서는 공백 변형·CSV 복사 등 변형을 폴백으로 둔다.
  List<_Splitter> _splitterCandidates(CsvParserProfile profile) {
    final primary = profile.delimiter.isNotEmpty ? profile.delimiter[0] : ',';
    final candidates = <_Splitter>[_Splitter.char(primary)];

    if (profile.sourceType == 'paste') {
      // 탭이 보존된 경우 → 위에서 처리.
      // 탭이 공백으로 바뀐 경우 → 공백 2칸 이상으로 분리.
      candidates.add(const _Splitter.whitespaceRun());
      if (primary != ',') candidates.add(const _Splitter.char(','));
    }
    return candidates;
  }

  // ── 내부: 행 분리 ─────────────────────────────────

  List<List<String>> _splitRows(String content, _Splitter splitter) {
    if (splitter.whitespaceRun) {
      return _splitByWhitespaceRun(content);
    }
    return _parseCsv(content, splitter.char!);
  }

  /// 공백 2칸 이상 또는 탭으로 분리.
  /// 셀 내부의 단일 공백(예: '주식회사 아성다이소', '2026.09.29 10:31:22')은
  /// 그대로 유지된다.
  List<List<String>> _splitByWhitespaceRun(String content) {
    final pattern = RegExp(r'\t+| {2,}');
    final rows    = <List<String>>[];

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      rows.add(trimmed.split(pattern).map((c) => c.trim()).toList());
    }
    return rows;
  }

  // ── 내부: 컬럼 배치 분석 ──────────────────────────

  /// 헤더 행을 찾고 컬럼 인덱스를 매핑한다.
  /// 필수 컬럼(날짜 + 금액)을 못 찾으면 null.
  _Layout? _resolveLayout(
    List<List<String>> rows,
    CsvParserProfile   profile,
  ) {
    // 붙여넣기는 은행마다 열 이름이 달라(기재내용/적요 등)
    // 동의어 기반으로 열을 인식한다. 파일은 기존대로 지정 이름만 사용.
    if (profile.sourceType == 'paste') {
      return _resolvePasteLayout(rows, profile);
    }

    final keyword = profile.headerKeyword;

    // 헤더 행 위치: 키워드가 있으면 탐색, 없으면 첫 행.
    int headerRow = 0;
    if (keyword != null && keyword.isNotEmpty) {
      headerRow = -1;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].any((c) => c.trim() == keyword)) {
          headerRow = i;
          break;
        }
      }
      if (headerRow < 0) return null;
    }

    final header = rows[headerRow].map((e) => e.trim()).toList();

    final dateIdx     = _colIndex(header, profile.dateCol);
    final merchantIdx = _colIndex(header, profile.merchantCol);
    final amountIdx   = _colIndex(header, profile.amountCol);
    final withdrawIdx = _colIndex(header, profile.withdrawCol);
    final depositIdx  = _colIndex(header, profile.depositCol);

    if (dateIdx == null || merchantIdx == null) return null;
    if (amountIdx == null && withdrawIdx == null && depositIdx == null) {
      return null;
    }

    // 데이터 시작 행:
    //   headerKeyword 사용 시 헤더 바로 다음 행,
    //   미사용 시 기존 동작(skipRows) 유지.
    final firstDataRow = (keyword != null && keyword.isNotEmpty)
        ? headerRow + 1
        : profile.skipRows;

    return _Layout(
      firstDataRow: firstDataRow,
      dateIdx:      dateIdx,
      merchantIdx:  merchantIdx,
      // 분리 형식이 확인되면 단일 금액 컬럼은 쓰지 않는다.
      amountIdx:    (withdrawIdx != null || depositIdx != null)
          ? null
          : amountIdx,
      withdrawIdx:  withdrawIdx,
      depositIdx:   depositIdx,
      balanceIdx:   _colIndex(header, profile.balanceCol),
      txnTypeIdx:   _colIndex(header, profile.txnTypeCol),
    );
  }

  /// 붙여넣기 전용 레이아웃 분석 (은행 공통).
  ///
  /// 열 이름을 정확히 몰라도 한국 은행에서 흔한 머리글 표현을 동의어로
  /// 인식한다. 프로필에 지정된 이름을 먼저 시도하고, 못 찾으면 동의어로
  /// 폴백한다. 이렇게 하면 토스·농협 등 서로 다른 은행의 거래내역을
  /// 은행별 열 이름을 일일이 등록하지 않고도 처리할 수 있다.
  _Layout? _resolvePasteLayout(
    List<List<String>> rows,
    CsvParserProfile   profile,
  ) {
    final dateC     = _candidates(profile.dateCol, _dateSynonyms);
    final merchantC = _candidates(profile.merchantCol, _merchantSynonyms);
    final withdrawC = _candidates(profile.withdrawCol, _withdrawSynonyms);
    final depositC  = _candidates(profile.depositCol, _depositSynonyms);
    final amountC   = _candidates(profile.amountCol, _amountSynonyms);
    final balanceC  = _candidates(profile.balanceCol, _balanceSynonyms);
    final typeC     = _candidates(profile.txnTypeCol, _typeSynonyms);

    // 헤더 행: 날짜 열 + (출금/입금/금액/잔액 중 하나)이 함께 있는 행.
    // 표 위 메타 줄(발급기준일·조회기간 등)을 안전하게 건너뛴다.
    int headerRow = -1;
    List<String> header = const [];
    for (var i = 0; i < rows.length; i++) {
      final cells = rows[i].map((c) => c.trim()).toList();
      final hasDate = _findColumn(cells, dateC) != null;
      final hasMoney = _findColumn(cells, withdrawC) != null ||
          _findColumn(cells, depositC) != null ||
          _findColumn(cells, amountC) != null ||
          _findColumn(cells, balanceC) != null;
      if (hasDate && hasMoney) {
        headerRow = i;
        header = cells;
        break;
      }
    }
    if (headerRow < 0) return null;

    final dateIdx     = _findColumn(header, dateC);
    final merchantIdx = _findColumn(header, merchantC);
    final withdrawIdx = _findColumn(header, withdrawC);
    final depositIdx  = _findColumn(header, depositC);
    // 출금·입금 분리가 확인되면 단일 금액 열은 찾지 않는다.
    // ('출금금액'이 '금액' 부분일치에 걸리는 오인식 방지)
    final amountIdx = (withdrawIdx == null && depositIdx == null)
        ? _findColumn(header, amountC)
        : null;

    if (dateIdx == null || merchantIdx == null) return null;
    if (amountIdx == null && withdrawIdx == null && depositIdx == null) {
      return null;
    }

    // 서로 다른 열이 같은 셀로 매칭되면(= 분리가 제대로 안 됨) 거부한다.
    // 예: 구분자(탭)로 나눴더니 한 줄이 통째로 1개 셀이 된 경우.
    //     부분 일치로 date·merchant·금액이 모두 index 0을 가리킨다.
    // → 이 후보를 버리면 상위 루프가 다음 구분자(공백)로 재시도한다.
    final keyIdx = <int>[
      dateIdx,
      merchantIdx,
      if (withdrawIdx != null) withdrawIdx,
      if (depositIdx != null) depositIdx,
      if (amountIdx != null) amountIdx,
    ];
    if (keyIdx.toSet().length != keyIdx.length) return null;

    return _Layout(
      firstDataRow: headerRow + 1,
      dateIdx:      dateIdx,
      merchantIdx:  merchantIdx,
      amountIdx:    amountIdx,
      withdrawIdx:  withdrawIdx,
      depositIdx:   depositIdx,
      balanceIdx:   _findColumn(header, balanceC),
      txnTypeIdx:   _findColumn(header, typeC),
    );
  }

  /// 프로필 지정 이름을 맨 앞에 두고 동의어를 이어붙인 후보 목록.
  /// 지정 이름이 비었거나 이미 동의어에 있으면 중복을 피한다.
  List<String> _candidates(String? configured, List<String> synonyms) {
    if (configured == null || configured.isEmpty) return synonyms;
    if (synonyms.contains(configured)) return synonyms;
    return [configured, ...synonyms];
  }

  /// 후보 이름들로 헤더에서 열 위치를 찾는다.
  /// 정확히 일치를 모든 후보에 대해 먼저 시도하고(더 구체적인 이름 우선),
  /// 없으면 부분 일치를 시도한다.
  int? _findColumn(List<String> header, List<String> candidates) {
    for (final name in candidates) {
      final exact = header.indexOf(name);
      if (exact >= 0) return exact;
    }
    for (final name in candidates) {
      for (var i = 0; i < header.length; i++) {
        if (header[i].contains(name)) return i;
      }
    }
    return null;
  }

  /// 헤더에서 컬럼 위치 찾기. 정확히 일치 우선, 없으면 부분 일치. (파일 모드)
  int? _colIndex(List<String> header, String? name) {
    if (name == null || name.isEmpty) return null;
    return _findColumn(header, [name]);
  }

  String _layoutErrorMessage(String content, CsvParserProfile profile) {
    final firstLines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(3)
        .join('\n');

    if (profile.sourceType == 'paste') {
      return '거래내역의 열을 인식하지 못했습니다.\n'
          '· 열 사이가 탭으로 구분되어 있는지 확인하세요.\n'
          '· 날짜 열과 (출금/입금 또는 금액) 열, 잔액 열이 있어야 합니다.\n'
          '입력 앞부분:\n$firstLines';
    }

    final needed = [
      profile.dateCol,
      profile.merchantCol,
      if (profile.withdrawCol != null) profile.withdrawCol!,
      if (profile.depositCol != null) profile.depositCol!,
      if (profile.amountCol.isNotEmpty) profile.amountCol,
    ].join(', ');

    return '필수 컬럼을 찾을 수 없습니다.\n'
        '필요 컬럼: $needed\n'
        '입력 앞부분:\n$firstLines';
  }

  // ── 내부: 값 변환 ─────────────────────────────────

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
        final row = currentRow ??= [];
        row.add(currentField.toString());
        rows.add(row);
        currentRow   = null;
        currentField = StringBuffer();
      }
    }

    if (currentRow != null || currentField.isNotEmpty) {
      final row = currentRow ??= [];
      row.add(currentField.toString());
      rows.add(row);
    }

    return rows;
  }

  /// 날짜 문자열 → Unix timestamp (ms)
  ///
  /// 프로필에 지정된 형식을 먼저 시도하고, 실패하면 한국 은행에서 흔한
  /// 형식들을 차례로 시도한다. 같은 은행이라도 조회 화면에 따라 시간이
  /// 붙기도 하고(`2026.09.22 15:00:00`) 날짜만 오기도 해서(`2026.09.22`),
  /// 형식을 하나로 고정하면 한쪽이 전부 0건으로 걸러진다.
  ///
  /// parseStrict로 문자열 전체가 형식과 맞을 때만 인정한다.
  /// (`yyyy.MM.dd`로 `2026.09.22 15:00:00`을 부분 매칭해 시간을 버리는 것 방지)
  int _parseDate(String raw, String format) {
    // 지정 형식 우선, 이후 흔한 형식 폴백. 중복은 무해하므로 그대로 둔다.
    const commonFormats = [
      'yyyy.MM.dd HH:mm:ss',
      'yyyy.MM.dd HH:mm',
      'yyyy.MM.dd',
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd',
      'yyyy/MM/dd HH:mm:ss',
      'yyyy/MM/dd',
      'yyyyMMdd',
    ];

    for (final fmt in [format, ...commonFormats]) {
      try {
        return DateFormat(fmt).parseStrict(raw).millisecondsSinceEpoch;
      } catch (_) {
        continue;
      }
    }
    throw FormatException('날짜를 해석할 수 없습니다: "$raw" (지정 형식: $format)');
  }

  /// 금액 문자열 → 정수 (원)
  /// △·▲·괄호·음수 부호·쉼표·공백·통화 단위('원', '₩') 처리.
  /// 빈 값과 '-'는 0으로 본다.
  int _parseAmount(String raw) {
    String s = raw.trim();
    if (s.isEmpty || s == '-') return 0;

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
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }

    s = s.replaceAll(RegExp(r'[,\s\t원₩]'), '');
    if (s.contains('.')) s = s.split('.').first;
    if (s.isEmpty) return 0;

    final value = int.parse(s);
    return negative ? -value : value;
  }
}
