// lib/domain/entities/parsed_transaction.dart
//
// CSV 파싱 결과 중간 모델.
// CsvParserUseCase → CsvImportUseCase 사이에서 사용.
// DB 저장 전 단계의 raw 데이터.

class ParsedTransaction {
  const ParsedTransaction({
    required this.txnDate,
    required this.amount,
    required this.merchant,
    this.balanceAfter,
  });

  /// 거래 일시 Unix timestamp (ms)
  final int txnDate;

  /// 금액 (원). 지출 음수(-), 수입 양수(+)
  final int amount;

  /// 거래처명 (CSV 원문)
  final String merchant;

  /// 거래 후 잔액 (컬럼이 없으면 null)
  final int? balanceAfter;
}

/// CSV 가져오기 결과 요약.
class ImportResult {
  const ImportResult({
    required this.totalRows,
    required this.newRows,
    required this.duplicateRows,
    required this.errorRows,
  });

  final int totalRows;
  final int duplicateRows;
  final int newRows;
  final int errorRows;
}
