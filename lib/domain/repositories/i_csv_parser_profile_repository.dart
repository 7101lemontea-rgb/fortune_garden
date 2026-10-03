// lib/domain/repositories/i_csv_parser_profile_repository.dart

import '../../data/database/app_database.dart';

/// CSV 파서 프로필 데이터 접근 추상 인터페이스.
abstract interface class ICsvParserProfileRepository {
  /// institution_code + source_type으로 활성화된 파서 프로필 반환.
  /// SCR-008 가져오기 화면에서 계좌 선택 시 자동 매칭.
  ///
  /// [sourceType]: 'file'(CSV 파일) | 'paste'(텍스트 붙여넣기).
  Future<CsvParserProfile?> getByInstitution(
    String institutionCode, {
    String sourceType = 'file',
  });

  /// 모든 파서 프로필 반환 (비활성 포함).
  Future<List<CsvParserProfile>> getAll();

  /// 파서 프로필 삽입 또는 업데이트 (upsert).
  Future<int> upsert(CsvParserProfilesCompanion companion);

  /// 파서 프로필 비활성화 (is_active = 0).
  /// 삭제 대신 비활성화하여 기존 데이터 참조 유지.
  Future<void> deactivate(int id);
}
