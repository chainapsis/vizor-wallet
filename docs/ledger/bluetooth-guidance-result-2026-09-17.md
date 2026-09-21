# Ledger Bluetooth 오류 안내 보존 결과

대상: iOS, Android, macOS Bluetooth. Windows/Linux의 기존 USB 흐름도
관련 데스크톱 회귀 테스트에 포함했다. 출발점은
`codex/ledger-mobile-bluetooth-ux`의 `64442fe3b`이다.

## 변경 사항

- 연결/앱 준비 예외가 원래 오류를 `cause`로 보존한다. 새 공통
  `ledgerFailureGuidance`가 오류 종류를 사용자 안내로 변환한다.
- Send(데스크톱/모바일), Swap/Pay, Shield, Gift Card, 즉시 마이그레이션의
  공용 Ledger 화면에서 권한, 페어링, 단절, busy, 잠금 등의 안내를 보존한다.
- 모바일/맥 기기 선택 및 계정 연결 화면도 같은 안내를 사용한다.
  모바일 선택창은 검색 결과가 남아 있어도 오류 설명을 함께 표시한다.
- Android의 위치 서비스 OFF는 `location_disabled`로 구분한다.
  검색과 저장된 기기 재검색 모두 Bluetooth 권한 오류와 구별한다.
- 실패 모달이 전역 readiness 상태로 현재 오류를 덮지 않도록 했다.
  준비 단계 오류도 실제로 잡힌 예외를 통해 표시한다.
- 근거 없는 Zcash 앱 열기 안내를 실패 화면에서 제거했다. 잘못된 앱이
  확인된 경우에는 해당 안내를 유지한다. 버전/잠금 안내는 오류 메시지에
  보존된다. 원인을 알 수 없는 거래 오류는 각 흐름의 기존 복구 정책을 따른다.
- 모바일의 연결 실패 문구는 계정에 저장된 연결 선호와 무관하게 Bluetooth를
  안내한다. macOS의 USB/Bluetooth 선택과 Windows/Linux의 USB 처리는 유지한다.

## 유지한 경계

재연결 횟수, 페어링 수행, 사용자 승인, 서명/저장/브로드캐스트 재시도 정책은
변경하지 않았다. 일반 연결 오류로 서명 작업 전체를 자동 재실행하지 않는다.
송금의 서명 보존 및 Retry saving, Swap/Pay의 전송 후 저장/확인 복구도 유지한다.

권한 재요청, 설정 이동 및 복귀 감지, OS bond 삭제, 기존 계정에 다른 기기
재지정은 이번 범위에 포함하지 않았다. 이 결과는 Bluetooth 복구 전체의
완료를 의미하지 않는다.

## 리뷰

`iterate-review-fixes` 절차로 임시 브랜치에서 전체 변경을 반복 리뷰했다.
첫 리뷰에서 알 수 없는 오류에 앱 열기 안내가 남는 경로를 발견하고 수정했다.
재리뷰에서 해당 문제가 해결됐으며 보류한 발견 사항은 없었다.
동일 목적의 구현/후속 수정 커밋은 최종 tree를 보존해 정리한다.
커밋 정리 후 최종 검증과 리뷰를 거쳐 원래 작업 브랜치에 fast-forward한다.

## 검증

| 검증 | 결과 |
| --- | --- |
| Ledger 서비스/데스크톱 화면/온보딩/Widgetbook/Send/Gift Card 테스트 | 313개 통과, mobile 태그 파일 1개 기본 제외 |
| mobile 태그 + mobile define Ledger/온보딩/Send 테스트 | 55개 통과 |
| Android LedgerMobileHandlerTest | 35개 통과 |
| fvm flutter analyze --no-pub | 문제 없음 |

추가 회귀 테스트는 iOS/Android/macOS × 연결/준비/서명 단계의 오류 전달,
모바일 및 데스크톱 Send의 오류 표시와 재시도, 맥 Bluetooth 선택창의
준비 단계 페어링 오류, 기기 목록이 남은 모바일 선택창, Swap/Shield의
상세 및 미분류 오류, 이전 readiness 상태의 덮어쓰기 방지, Android
위치 오류의 네이티브/Dart 분류를 확인한다.

```sh
fvm flutter test --no-pub test/features/ledger test/features/onboarding/ledger_connect_screen_test.dart test/features/onboarding/ledger_setup_desktop_test.dart test/widgetbook/ledger_use_cases_test.dart test/features/send/send_review_screen_test.dart test/features/payment_links/payment_links_screen_ledger_test.dart
fvm flutter test --no-pub --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/ledger test/features/onboarding/mobile_ledger_connect_screen_test.dart test/features/send/mobile_ledger_send_sign_screen_test.dart
fvm flutter analyze --no-pub
# JDK 17, 프로젝트의 Gradle 8.14로 실행:
gradle -p android :app:testDebugUnitTest --tests com.keplr.vizor.LedgerMobileHandlerTest
```

실물 Ledger로 무선 단절/페어링 초기화를 실행한 검증은 하지 않았다.
OS에서 발생하는 오류 종류와 팝업 순서는 후속 실기기 검증 대상이다.
AGENTS.md에 언급된 두 copy-review CSV는 이 checkout에 없어, 명시된
sentence case 규칙과 기존 Ledger 문구를 기준으로 작성했다.
