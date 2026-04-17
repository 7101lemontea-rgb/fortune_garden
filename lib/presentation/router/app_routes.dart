// lib/presentation/router/app_routes.dart
//
// 앱 전체에서 사용하는 라우트 경로 상수.
// context.go(), context.push(), GoRoute.path 등 모든 경로 참조를 여기서 관리합니다.

abstract final class AppRoutes {
  // ── 최상위 경로 ──────────────────────────────────────────
  static const setup = '/setup';
  static const dashboard = '/dashboard';
  static const transactions = '/transactions';
  static const report = '/report';
  static const accounts = '/accounts';
  static const import = '/import';
  static const categories = '/categories';
  static const settings = '/settings';
  static const profiles = '/profiles';

  // ── 거래 하위 경로 (GoRoute path: 상대 경로) ─────────────
  /// GoRoute path 선언용 상대 경로 ('transactions/' 없음)
  static const transactionNewSeg = 'new';
  static const transactionIdSeg = ':id';

  // ── 거래 절대 경로 헬퍼 ──────────────────────────────────
  static const transactionNew = '/transactions/new';

  /// 특정 거래 상세 경로 생성
  static String transactionDetail(int id) => '/transactions/$id';
}
