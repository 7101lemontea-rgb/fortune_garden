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
}
