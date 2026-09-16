# Ledger Bluetooth 복구 구현 결과

대상: [승인된 계획](bluetooth-recovery-plan-2026-09-16.md)의 1번(Apple 단절 후 미완료 응답), 2번(모바일 불완전한 재연결).

## 변경된 동작

- **macOS/iOS**: APDU 대기 중 단절되면 SDK가 원래 요청을 한 번 실패로 완료한다. 부분 응답·MTU 대기·notification listener·중단된 characteristic discovery를 정리하고, 이전 연결 콜백이 새 응답에 섞이지 않도록 세대 및 요청 소유권을 검사한다.
- notification/MTU 초기화는 60초 내 완료되지 않으면 실패로 반환하고 CoreBluetooth 연결을 취소한다. GATT 연결의 기존 5초 제한도 실제 radio 취소 및 teardown까지 작업 슬롯을 보존하도록 고쳤다. 늦게 연결 성공이 와도 다시 취소하며 새 연결의 성공으로 처리하지 않는다.
- **iOS/Android 공통**: 실패한 세션은 동일 device ID여도 정상 연결로 재사용하지 않는다. 다음 사용자 시도는 native disconnect 완료 후 connect/readiness를 수행한다. 이미 연결된 세션의 준비 단계에서 disconnected가 발생하면 한 번만 복구한다. 정리·첫 연결이 실패한 경우 같은 호출에서 다시 반복하지 않는다.
- **Android**: cleanup 실패 시 대상 객체를 유지한다. 취소된 connect가 뒤늦게 성공한 경우와 이전 handler가 남긴 SDK 세션도 drain 후 정리한다. 명시적 cleanup 뒤 DMK가 정확히 `Device already connected`를 반환하는 구간에만 100ms 간격, 최대 50회 대기(5초)를 적용한다. 일반 연결 실패·페어링 실패·APDU에는 이 재시도를 적용하지 않는다.
- `busy`를 연결 고장과 구분한다. 아직 실행 중인 작업을 실패한 연결로 취급하여 교체하지 않는다. 준비 단계 진입도 직렬화한다.
- **서명 APDU는 자동 재실행하지 않는다.** 사용자 승인 대기 자체에 임의 타임아웃을 추가하지 않았다. 기존 앱 열기/서명 라운드/저장·브로드캐스트 복구 경계를 유지한다.

## 재리뷰에서 추가로 수정한 결함

| 검토 | 확인한 문제 | 수정 및 검증 |
|---|---|---|
| 최초 분석 | Apple 단절 시 exchange continuation과 부분 응답이 남음 | 생산 SDK에 직접 회귀 테스트: 단절 후 한 번 완료, 이전 응답 무시, 새 APDU 성공 |
| 최초 분석 | 모바일이 오류 이후 같은 연결을 계속 probe하거나 cleanup보다 먼저 connect | Dart 세션 무효화, busy 분리, Android teardown 대기 및 실패 보존 |
| 2차 리뷰 | 취소한 Android connect의 늦은 성공에 대한 cleanup 실패 시 대상 유실 | 대상을 유지하고 이전 SDK job 종료 후 재확인; 늦은 콜백+cleanup 실패 재현 통과 |
| 2차 리뷰 | Widgetbook 테스트가 안내 없는 기본 failure를 선택한 채 readiness 안내를 기대 | reconnect fixture를 명시; 데스크톱 관련 전체 테스트 통과 |
| 3차 리뷰 | Apple GATT timeout이 실제 연결을 취소하지 않고 큐를 해제 | OS teardown까지 큐 소유권 유지, 늦은 성공 취소, 재시도 차단/복귀 검증 |
| 4차 리뷰 | 전체 변경, 오류 전파, 취소/정리 순서, 플랫폼 설정 재검토 | 추가 수정 대상 없음 |
| 5차 리뷰 | Bluetooth unavailable 경로는 transport만 정리하고 하위 큐를 보존 | 모듈 큐/listener/발견 대기 무효화 및 늦게 enqueue된 이전 세대 작업 차단 |

Apple 의존성은 Ledger BLE 1.0.1, revision `4df8fff21c1738a1dff4d2ee19175dd3263d6c5f`를 로컬 패키지로 고정했다. iOS/macOS와 네이티브 테스트가 동일한 소스를 사용한다. 출처·MIT LICENSE·변경 설명은 `third_party/ledger_ble_transport`에 있다.

6차 전체 리뷰와 커밋 정리 후 7차 최종 리뷰에서 추가 수정 대상이 없었다.
보류하거나 사용자 수용으로 남긴 결함은 없다. 정리 전후 Git tree가 동일함을 확인했다.

최종 코드 커밋:

- `d5bcc13fc`: Apple BLE SDK 종료·타임아웃·radio/큐 무효화.
- `140387575`: 모바일 세션 복구 및 Android cleanup 소유권.
- `a39f4a5ef`: readiness 안내 테스트 fixture 수정.

## 검증

| 검증 | 결과 |
|---|---|
| `swift test --package-path third_party/ledger_ble_transport` | SDK 9개 통과 |
| `python3 scripts/test-ledger-apple.py` | 공용 Apple handler 35개 통과 |
| Android `:app:testDebugUnitTest --tests com.keplr.vizor.LedgerMobileHandlerTest` | 30개 통과 |
| Ledger 서비스/서명/온보딩/Widgetbook 데스크톱 관련 테스트 | 179개 통과, mobile 태그 1개 기본 제외 |
| mobile 태그 + `VIZOR_FORM_FACTOR=mobile` Ledger/연결/Send 테스트 | 39개 통과 |
| `fvm flutter analyze` | 문제 없음 |
| macOS debug / iOS Simulator debug 전체 빌드 | 둘 다 성공; 최종 코드로 증분 빌드 재확인 |

데스크톱 테스트 명령:

```sh
fvm flutter test test/features/ledger test/features/onboarding/ledger_connect_screen_test.dart test/features/onboarding/ledger_setup_desktop_test.dart test/widgetbook/ledger_use_cases_test.dart
```

모바일 테스트 명령:

```sh
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/ledger test/features/onboarding/mobile_ledger_connect_screen_test.dart test/features/send/mobile_ledger_send_sign_screen_test.dart
```

검증은 실제 생산 SDK의 상태 처리와 통제된 radio/MethodChannel/DMK 콜백을 이용했다. 물리 Ledger를 연결하여 전원 off/on·페어링 삭제·실제 Try again까지 실행한 검증은 하지 않았다. 따라서 실기기 무선 복구를 검증 완료로 표기하지 않는다.

## 범위와 후속 작업

권한 재요청 UX, OS 페어링 삭제 안내, 기존 계정의 장치 재지정 UI는 승인된 계획대로 후속 범위다. 이번 변경은 해당 오류가 자동 재연결 루프에 들어가지 않도록 분류를 보존한다. Windows/Linux USB 및 Rust 서명·브로드캐스트 구현은 변경하지 않았다.

로컬 통합 대상은 `codex/ledger-bluetooth-audit`이며 `main`이나 원격 브랜치가 아니다.

## 추가 리뷰 후 스캔 수명 수정

기존 완료 보고 이후 독립 리뷰에서, Bluetooth off 처리의 큐 제거가
`Scan` 타이머를 취소하지 않아 빠른 on/재검색 뒤 이전 타이머가 새 검색을
중단하는 P2 회귀를 확인했다. `cdc8d6037`에서 수정했다.

- 큐에서 제거하거나 이전 세대 작업을 거절할 때 `discard()`를 호출한다.
- `Scan.discard()`는 종료 상태를 먼저 설정하고 timeout/expiry 타이머,
  discovery/expired/stopped 콜백 및 검색 결과를 해제한다.
- 종료된 스캔의 늦은 timeout, 예약된 expiry 종료, 발견 이벤트 및
  stop/start 호출은 무시한다. 정상 종료는 기존처럼 한 번 통지한다.
- 시작되지 않은 스캔을 버릴 때는 진행 중인 다른 검색을 중단하지 않는다.

실제 Scan/Queue와 radio 대역을 사용하는 회귀 테스트에서 큐 수정 전
3개 테스트가 실패하는 것을 확인했고, 수정 후 추가한 expiry 경합 테스트까지
새 테스트 5개 모두 통과했다. 전체 SDK 14개, 공용 Apple handler 35개 통과.
macOS debug 및 iOS Simulator debug (`VIZOR_FORM_FACTOR=mobile`) 빌드 성공.
재리뷰와 최종 리뷰에서 이 수정 범위의 추가 결함은 없었다.
단일 원인 수정 커밋으로 유지하여 기존 커밋을 재작성하지 않았다.
실물 Ledger 무선 테스트는 이번에도 수행하지 않았다.
