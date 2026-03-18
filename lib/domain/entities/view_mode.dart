// lib/domain/entities/view_mode.dart
//
// 개인 뷰 / 통합 뷰 전환 상태를 나타내는 enum.
// SAD v1.1 §5.4 기준.

enum ViewMode {
  /// 개인 뷰: 활성 프로필의 계좌·거래만 표시
  personal,

  /// 통합 뷰: 두 프로필 합산, 프로필 색상 태그 표시
  combined;

  /// app_settings DB 저장 문자열 → enum 변환
  static ViewMode fromString(String value) =>
      value == 'combined' ? ViewMode.combined : ViewMode.personal;

  /// enum → DB 저장 문자열
  String get value => name; // 'personal' | 'combined'
}
