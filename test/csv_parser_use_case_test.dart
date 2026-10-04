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

  group('날짜 형식 유연성', () {
    // 프로필은 'yyyy.MM.dd HH:mm:ss'로 지정돼 있지만,
    // 실제 우리은행 화면은 날짜만(2026.09.22) 오는 경우가 있다.
    // 두 경우 모두 파싱되어야 한다 (한쪽만 되면 전부 0건으로 걸러짐).

    test('날짜만 있는 행(시간 없음)도 파싱된다', () {
      final parsed = parser.parseFromString(
        content: '거래일시\t거래구분\t기재내용\t출금금액\t입금금액\t잔액\n'
            '2026.09.22\t예금신규\t우리은행\t0원\t100,000,000원\t100,000,000원\n',
        parserProfile: _wooriPasteProfile,
      );
      expect(parsed.length, 1);
      expect(parsed.single.amount, 100000000);
      expect(parsed.single.merchant, '우리은행');
      expect(
        DateTime.fromMillisecondsSinceEpoch(parsed.single.txnDate),
        DateTime(2026, 9, 22),
      );
    });

    test('시간이 포함된 행도 여전히 파싱된다', () {
      final parsed = parser.parseFromString(
        content: '거래일시\t거래구분\t기재내용\t출금금액\t입금금액\t잔액\n'
            '2026.09.22 15:00:00\t예금신규\t우리은행\t0원\t100,000,000원\t100,000,000원\n',
        parserProfile: _wooriPasteProfile,
      );
      expect(parsed.length, 1);
      expect(
        DateTime.fromMillisecondsSinceEpoch(parsed.single.txnDate),
        DateTime(2026, 9, 22, 15, 0, 0),
      );
    });
  });

  group('은행 공통 동의어 인식 (seed의 _bankPaste와 동일 설정)', () {
    // 열 이름을 은행별로 지정하지 않고 동의어로 자동 인식하는지 검증.
    const bankPaste = CsvParserProfile(
      id: 2, institutionCode: 'NH', sourceType: 'paste',
      dateCol: '거래일시', amountCol: '', withdrawCol: '출금금액',
      depositCol: '입금금액', balanceCol: '잔액', txnTypeCol: '거래구분',
      merchantCol: '기재내용', dateFormat: 'yyyy.MM.dd HH:mm:ss',
      encoding: 'UTF-8', delimiter: '\t', headerKeyword: '거래일시',
      rowOrder: 'desc', skipRows: 1, isActive: 1,
    );

    test('농협 형식(거래일자/적요/거래후잔액, 거래구분 없음)을 인식한다', () {
      // 열 이름이 프로필 기본값과 다르지만 동의어로 매칭되어야 한다.
      final parsed = parser.parseFromString(
        content: '거래일자\t적요\t출금금액\t입금금액\t거래후잔액\n'
            '2026.09.20\t김철수\t0\t500,000\t1,500,000\n'
            '2026.09.21\t마트결제\t30,000\t0\t1,470,000\n',
        parserProfile: bankPaste,
      );
      // 원본이 과거순(오름차순)이지만 rowOrder=desc라 뒤집힌다.
      expect(parsed.length, 2);
      // 뒤집힘: [마트결제(-30,000), 김철수(+500,000)]
      expect(parsed[0].merchant, '마트결제');
      expect(parsed[0].amount, -30000);
      expect(parsed[1].merchant, '김철수');
      expect(parsed[1].amount, 500000);
      expect(parsed[1].balanceAfter, 1500000);
      // 거래구분 열이 없으므로 txnType은 null
      expect(parsed[0].txnType, isNull);
    });

    test('토스 형식(단일 금액 열, +/- 부호)을 인식한다', () {
      // 출금·입금이 한 열에 부호로 들어오는 형식.
      final parsed = parser.parseFromString(
        content: '거래일시\t적요\t거래금액\t잔액\n'
            '2026.09.22 10:00:00\t스타벅스\t-4,500\t95,500\n',
        parserProfile: bankPaste,
      );
      expect(parsed.length, 1);
      expect(parsed.single.merchant, '스타벅스');
      expect(parsed.single.amount, -4500); // 단일 열 음수 부호
      expect(parsed.single.balanceAfter, 95500);
    });

    test("상대방 열 이름이 '받는분/보내는분'이어도 인식한다", () {
      final parsed = parser.parseFromString(
        content: '거래일시\t받는분/보내는분\t출금금액\t입금금액\t잔액\n'
            '2026.09.22\t홍길동\t10,000\t0\t90,000\n',
        parserProfile: bankPaste,
      );
      expect(parsed.length, 1);
      expect(parsed.single.merchant, '홍길동');
      expect(parsed.single.amount, -10000);
    });

    test("'출금금액'이 단일 금액('금액')으로 오인식되지 않는다", () {
      // 출금/입금 분리가 있으면 단일 금액 열은 찾지 않아야 한다.
      final parsed = parser.parseFromString(
        content: '거래일시\t적요\t출금금액\t입금금액\t잔액\n'
            '2026.09.22\t테스트\t1,000\t0\t9,000\n',
        parserProfile: bankPaste,
      );
      expect(parsed.single.amount, -1000); // 출금 1,000 → -1,000
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

    test('날짜를 어떤 형식으로도 해석할 수 없으면 그 행은 건너뛴다', () {
      // 헤더는 인식되지만 날짜가 깨진 행 → 0건 (예외로 전체 중단되지 않음)
      final parsed = parser.parseFromString(
        content: '거래일시\t거래구분\t기재내용\t출금금액\t입금금액\t잔액\n'
            '날짜아님\t예금신규\t우리은행\t0원\t100원\t100원\n',
        parserProfile: _wooriPasteProfile,
      );
      expect(parsed, isEmpty);
    });
  });
}
