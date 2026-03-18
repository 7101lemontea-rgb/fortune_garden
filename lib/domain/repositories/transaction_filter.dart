// lib/domain/repositories/transaction_filter.dart
//
// 거래 내역 조회 필터 파라미터 모델.
// ITransactionRepository.getList()에서 사용.

/// 거래 내역 목록 조회 필터.
/// 모든 필드는 optional — null이면 해당 조건 미적용.
class TransactionFilter {
  /// 특정 프로필만 조회 (null = 전체 프로필)
  final int? profileId;

  /// 특정 계좌만 조회
  final int? accountId;

  /// 특정 카테고리만 조회
  final int? categoryId;

  /// 조회 시작일 Unix timestamp (ms, 이상)
  final int? fromDate;

  /// 조회 종료일 Unix timestamp (ms, 미만)
  final int? toDate;

  /// 수동 입력만 조회 (true), CSV만 조회 (false), 전체 (null)
  final bool? isManualOnly;

  /// 페이지네이션 — 건너뛸 행 수
  final int offset;

  /// 페이지네이션 — 가져올 행 수
  final int limit;

  const TransactionFilter({
    this.profileId,
    this.accountId,
    this.categoryId,
    this.fromDate,
    this.toDate,
    this.isManualOnly,
    this.offset = 0,
    this.limit = 50,
  });
}
