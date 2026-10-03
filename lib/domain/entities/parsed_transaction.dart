// lib/domain/entities/parsed_transaction.dart
//
// CSV/붙여넣기 파싱 결과 중간 모델.
// CsvParserUseCase → CsvImportUseCase 사이에서 사용.
// DB 저장 전 단계의 raw 데이터.

class ParsedTransaction {
  const ParsedTransaction({
    required this.txnDate,
    required this.amount,
    required this.merchant,
    this.balanceAfter,
    this.txnType,
  });

  /// 거래 일시 Unix timestamp (ms)
  final int txnDate;

  /// 금액 (원). 지출 음수(-), 수입 양수(+)
  final int amount;

  /// 거래처명 (원문)
  final String merchant;

  /// 거래 후 잔액 (컬럼이 없으면 null)
  final int? balanceAfter;

  /// 거래구분 (예: 현카구매, 체크우리, 타행자동).
  /// 컬럼이 없으면 null. 카테고리 분류 보조 키로 사용.
  final String? txnType;
}

/// 가져오기 결과 요약.
class ImportResult {
  const ImportResult({
    required this.totalRows,
    required this.newRows,
    required this.duplicateRows,
    required this.errorRows,
    this.warnings = const [],
  });

  final int totalRows;
  final int duplicateRows;
  final int newRows;
  final int errorRows;

  /// 저장은 되었으나 사용자가 확인해야 하는 사항.
  /// 예) 잔액 흐름이 맞지 않아 누락된 행이 의심되는 경우.
  final List<String> warnings;
}
