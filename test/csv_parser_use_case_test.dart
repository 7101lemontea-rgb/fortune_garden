// test/csv_parser_use_case_test.dart
//
// CsvParserUseCase 단위 테스트.
// 우리은행 '계좌거래내역' 화면을 복사해 붙여넣은 실제 형식을 기준으로 한다.
//
// 검증 범위:
//   - 표 위 메타 줄(발급기준일·조회기간·계좌번호)을 건너뛰고 헤더 탐색
//   - 출금·입금 분리 컬럼 → amount 부호 (지출 음수 / 수입 양수)
//   - '원'·쉼표가 붙은 금액 문자열 파싱
//   - 최신순(desc) 원본을 과거순으로 뒤집기
//   - 잔액·거래구분 수집
//   - 탭이 공백으로 변형된 붙여넣기 자동 보정

import 'package:flutter_test/flutter_test.dart';
import 'package:fortune_garden/application/csv_import/csv_parser_use_case.dart';
import 'package:fortune_garden/data/database/app_database.dart';

/// 우리은행 붙여넣기 파서 프로필 (seed_institutions.dart와 동일한 설정).
const _wooriPasteProfile = CsvParserProfile(
  id: 1,
  institutionCode: 'WOORI',
  sourceType: 'paste',
  dateCol: '거래일시',
  amountCol: '',
  withdrawCol: '출금금액',
  depositCol: '입금금액',
  balanceCol: '잔액',
  txnTypeCol: '거래구분',
  merchantCol: '기재내용',
  dateFormat: 'yyyy.MM.dd HH:mm:ss',
  encoding: 'UTF-8',
  delimiter: '\t',
  headerKeyword: '거래일시',
  rowOrder: 'desc',
  skipRows: 1,
  isActive: 1,
);

/// 실제 화면을 복사한 형태. 표 앞에 메타 줄이 붙고 최신순으로 정렬되어 있다.
/// 열 구분자는 탭.
const _pastedTabs = '계좌거래내역\n'
    '발급 기준일: 2026.10.02 22:57:15\n'
    '조회기간\t2026.07.02 ~ 2026.10.02\n'
    '계좌번호\t1002-84*-******\t예금주\t정*영\n'
    '현재잔액\t1,382,942원\t출금가능금액\t1,382,942원\n'
    '단위: 원\n'
    '거래일시\t거래구분\t기재내용\t출금금액\t입금금액\t잔액\t취급점\n'
    '2026.09.29 10:31:22\t현카구매\t현카캐쉬백\t0원\t76원\t1,382,942원\t098150\n'
    '2026.09.29 10:31:22\t현카구매\t주식회사 아성다이소\t15,200원\t0원\t1,382,866원\t098150\n'
    '2026.09.29 09:42:14\t체크우리\t할리스커피 유성\t5,900원\t0원\t1,398,066원\t리테일영업총괄부(카드)\n'
    '2026.09.28 09:48:47\t타행자동\t정*권\t0원\t350,000원\t1,403,966원\t신한은행\n';

/// 복사 과정에서 탭이 공백으로 바뀐 경우.
/// 셀 내부의 단일 공백('주식회사 아성다이소')은 유지되어야 한다.
const _pastedSpaces = '계좌거래내역\n'
    '발급 기준일: 2026.10.02 22:57:15\n'
    '거래일시    거래구분    기재내용    출금금액    입금금액    잔액    취급점\n'
    '2026.09.29 10:31:22    현카구매    현카캐쉬백    0원    76원    1,382,942원    098150\n'
    '2026.09.29 10:31:22    현카구매    주식회사 아성다이소    15,200원    0원    1,382,866원    098150\n'
    '2026.09.29 09:42:14    체크우리    할리스커피 유성    5,900원    0원    1,398,066원    리테일영업총괄부(카드)\n'
    '2026.09.28 09:48:47    타행자동    정*권    0원    350,000원    1,403,966원    신한은행\n';

void main() {
  const parser = CsvParserUseCase();

  group('우리은행 붙여넣기 (탭 구분)', () {
    final parsed = parser.parseFromString(
      content: _pastedTabs,
      parserProfile: _wooriPasteProfile,
    );

    test('메타 줄을 건너뛰고 거래 4건만 파싱한다', () {
      expect(parsed.length, 4);
    });

    test('과거순으로 뒤집힌다', () {
      final dates = parsed.map((t) => t.txnDate).toList();
      expect(dates, equals([...dates]..sort()));
      expect(
        DateTime.fromMillisecondsSinceEpoch(parsed.first.txnDate),
        DateTime(2026, 9, 28, 9, 48, 47),
      );
    });

    test('출금은 음수, 입금은 양수로 변환한다', () {
      expect(parsed[0].amount, 350000); // 타행자동 입금
      expect(parsed[1].amount, -5900); // 할리스커피 출금
      expect(parsed[2].amount, -15200); // 다이소 출금
      expect(parsed[3].amount, 76); // 캐시백 입금
    });

    test('기재내용·거래구분·잔액을 수집한다', () {
      expect(parsed[2].merchant, '주식회사 아성다이소');
      expect(parsed[2].txnType, '현카구매');
      expect(parsed[2].balanceAfter, 1382866);
      expect(parsed[3].balanceAfter, 1382942);
    });

    test('같은 초 거래는 결제 → 캐시백 순서가 된다', () {
      // 원본(최신순)에서 캐시백이 위에 있으므로 뒤집으면 결제가 먼저 온다.
      expect(parsed[2].merchant, '주식회사 아성다이소');
      expect(parsed[3].merchant, '현카캐쉬백');
    });

    test('잔액 흐름이 연속된다', () {
      for (var i = 1; i < parsed.length; i++) {
        expect(
          parsed[i - 1].balanceAfter! + parsed[i].amount,
          parsed[i].balanceAfter,
          reason: '$i번째 행의 잔액이 이어지지 않음',
        );
      }
    });
  });

  group('우리은행 붙여넣기 (탭이 공백으로 변형)', () {
    final parsed = parser.parseFromString(
      content: _pastedSpaces,
      parserProfile: _wooriPasteProfile,
    );

    test('공백 구분으로도 거래 4건을 파싱한다', () {
      expect(parsed.length, 4);
    });

    test('셀 내부의 단일 공백은 유지된다', () {
      expect(parsed[2].merchant, '주식회사 아성다이소');
      expect(
        DateTime.fromMillisecondsSinceEpoch(parsed[2].txnDate),
        DateTime(2026, 9, 29, 10, 31, 22),
      );
    });

    test('금액 부호가 탭 버전과 같다', () {
      expect(parsed.map((t) => t.amount).toList(),
          [350000, -5900, -15200, 76]);
    });
  });

  group('필수 컬럼이 없는 입력', () {
    test('헤더를 찾지 못하면 FormatException을 던진다', () {
      expect(
        () => parser.parseFromString(
          content: '아무 내용도 아닌 텍스트\n두 번째 줄\n',
          parserProfile: _wooriPasteProfile,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
