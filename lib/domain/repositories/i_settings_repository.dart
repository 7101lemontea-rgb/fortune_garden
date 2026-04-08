// lib/domain/repositories/i_settings_repository.dart

/// 앱 전역 설정 데이터 접근 추상 인터페이스.
/// Key-Value 저장소. value는 JSON 직렬화 허용.
abstract interface class ISettingsRepository {
  /// 설정 값 조회. 없으면 defaultValue 반환.
  Future<String?> get(String key, {String? defaultValue});

  /// 설정 값 저장 (upsert).
  Future<void> set(String key, String? value);

  /// 설정 값 삭제.
  Future<void> delete(String key);

  /// 설정 값 실시간 구독. ★ 테마 동적 적용용 신규 추가
  ///
  /// [key]에 해당하는 값이 변경될 때마다 새 이벤트를 emit.
  /// 값이 없거나 null이면 [defaultValue]를 emit.
  Stream<String?> watchValue(String key, {String? defaultValue});
}
