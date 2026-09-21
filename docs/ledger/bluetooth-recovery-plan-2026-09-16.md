# Ledger Bluetooth 복구 수정 계획

대상은 직전 답변의 1번(Apple 단절 후 미완료 응답)과 2번(모바일의 불완전한 재연결)이다. 분석 보고서의 A/E에 해당한다. 현재 브랜치는 `codex/ledger-bluetooth-audit`이며 이 문서는 계획 제출용이다. 제품 코드 수정은 아직 시작하지 않았다.

## 분석 결과와 설계 결정

**Apple은 고정 SDK 내부를 최소 수정하고, 모바일은 오류 이후의 연결 재사용 정책을 명시적으로 관리한다.**

앱에서 `exchangeTask = nil`만 설정하거나 SDK 호출을 timeout으로 감싸는 방식은 채택하지 않는다. BleTransport 1.0.1은 미완료 콜백, 부분 응답 버퍼, 연결 준비 콜백을 private 상태로 보유한다. `clearConnection()`은 이들을 모두 정리하지 않는다. 앱만 대기를 포기하면 SDK 작업과 늦은 콜백이 남아 다음 작업과 충돌할 수 있다.

SDK의 `exchange` async API는 connect async API와 달리 continuation 중복 완료 방어도 없다. 따라서 disconnect에서 실패 콜백을 단순히 추가하는 것으로 끝내지 않고, 성공·실패·단절의 완료 처리를 한곳으로 모아 정확히 한 번만 호출해야 한다. 오류 전달 전 내부 상태를 정리하는 순서도 중요하다.

권장 의존성 방식은 현재 pin `4df8fff21c1738a1dff4d2ee19175dd3263d6c5f`의 패키지를 저장소의 `third_party/ledger_ble_transport`에 포함하고, iOS/macOS가 같은 로컬 Swift package를 사용하도록 하는 것이다. 원본 LICENSE, pin, 변경 내역을 남긴다. 대상 SDK는 외부 package 의존성이 없는 27개 소스 파일 규모다. upstream 전체 버전 변경 대신 검토할 패치를 한정하며, `scripts/test-ledger-apple.py`도 앱과 동일한 로컬 패키지를 테스트하도록 바꾼다.

Android는 앱의 `disconnect()` 완료만으로 SDK 내부 정리가 끝났다고 판단할 수 없다. DMK는 public session 목록을 먼저 제거할 수 있고, BLE `deviceConnections` 항목은 별도 coroutine의 종료 처리에서 제거한다. 따라서 `getConnectedDevices()`에 없다는 것만으로 다음 connect가 반드시 성공한다고 보장할 수 없다. 앱 handler에서 정리와 새 연결을 직렬화하고, SDK가 명시적으로 `Device already connected`를 반환하는 이행 구간만 제한적으로 기다려야 한다.

근거 파일:

- `ios/Runner/LedgerMobileHandler.swift`: `handleDisconnected`, `startExchange`, `cancelExchangeOperation`, `openZcashApp`, transport ownership.
- `lib/src/features/ledger/services/ledger_mobile_ble_service.dart`: Dart 연결 ID와 native 오류 변환.
- `lib/src/features/ledger/services/ledger_connection_service.dart`: probe/reconnect 및 operation-start 경계.
- `android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt`: SDK 작업 소유권과 disconnect/operationFailure.
- Apple SDK `BleTransport.swift`: `clearConnection`, `startListening`, `writeAPDU`, `inferMTU`, async exchange.
- Android DMK 0.0.4: `DisconnectFromDeviceUseCase`, `AndroidBluetoothTransport`, `AndroidBluetoothDeviceConnection`, `DefaultDeviceSessionRepository`.

## 1단계 — 실패 재현을 회귀 테스트로 전환

기존 재현 패치는 현재 결함을 확인하는 assertion이다. 이를 수정 후 기대 동작으로 바꿔 먼저 실패를 확인한다.

- Apple: APDU 대기 중 단절 → 원래 호출 한 번 실패 → 작업 슬롯 해제 → 재검색 또는 동일 Ledger 재연결 → 새 APDU 성공.
- iOS/Android: 기존 연결 probe가 통신 실패 → 기존 연결 정리 → 새 연결 → readiness 성공.
- APDU 도중 통신 실패는 현재 작업에 그대로 반환하되, 다음 사용 시 이전 연결을 정상 연결로 재사용하지 않는다.
- 진짜 busy/사용자 취소는 새 연결이나 APDU를 시작하지 않는다.

앱 handler mock 테스트뿐 아니라 수정하는 SDK의 완료/수신 버퍼/세대 관리 로직에도 직접 테스트를 추가한다. 무선 없이 검증하도록 내부 로직의 테스트 지점을 제한적으로 추출한다.

## 2단계 — Apple 연결 종료와 재사용 경계 수정

1. exchange의 완료 경로를 통합한다. 성공·write/read 실패·물리 단절은 같은 완료 함수를 사용하고 콜백을 먼저 소유권에서 제거한 후 한 번만 전달한다.
2. 단절 시 partial response, 남은 길이, MTU 대기, pending connect/exchange 상태를 정리한다. 취소되거나 끊긴 세션의 콜백은 새 세션 결과를 완료시킬 수 없도록 연결/작업 세대 번호를 검사한다.
3. BLE operation queue의 이전 연결 정리가 새 연결보다 먼저 끝나도록 순서를 맞춘다. 큐가 오래된 작업을 제거하기 전에 외부 콜백이 새 연결을 시작하는 경우도 테스트한다.
4. notification/MTU 초기화 실패를 connect 실패로 완료한다. GATT 연결 이후 프로토콜 초기화 구간에 제한 시간을 둔다. 사용자 페어링 승인 시간을 짧은 APDU timeout으로 취급하지 않는다. 제한 시간 만료 시에도 실제 연결 정리 전까지 재사용을 허용하지 않는다.
5. 핸들러는 단절 결과가 SDK에서 완료되면 실제 Task 종료 후 소유권을 해제한다. Flutter result는 이미 취소/단절 오류로 완료된 경우 중복 전달하지 않는다.
6. `openZcashApp`의 정상적인 앱 전환 단절은 기존 coordinator로 복구한다. 앱 열기 APDU는 한 번만 보내고 재연결 후 `currentApp`으로 확인한다. 응답이 유실되더라도 동일 명령을 다시 보내지 않는다.

연결이 살아 있고 사용자가 승인 중인 요청은 기존처럼 실제 응답을 기다린다. 임의 시간 경과만으로 서명 요청을 중단하고 다시 보내지 않는다. 이번 단계의 핵심은 단절/명시적 초기화 실패가 발생했는데도 대기가 끝나지 않는 경로를 제거하는 것이다.

## 3단계 — 모바일 연결 상태와 오류 분류 정리

Dart의 마지막 성공 device ID와 재사용 가능 여부를 분리한다. 마지막 연결 ID는 표시/대상 정보이며, 오류가 난 세션은 같은 ID여도 재사용할 수 없게 표시한다. native 작업 소유권 검사는 계속 최종 실행 경계로 유지한다.

`unavailable`에 섞여 있는 상태를 최소한 `busy`, 복구 가능한 통신 실패, 일반 기능 오류로 구분한다. 필요한 오류 코드는 Swift/Kotlin → MethodChannel → Dart까지 함께 추가하고 enum switch를 모두 갱신한다.

| 오류/상태 | 처리 정책 |
|---|---|
| disconnected, read/write 실패, NoResponse 등 확정된 통신 실패 | 세션 무효화. 작업 시작 전이면 정리 후 1회 재연결 가능 |
| native busy, 취소한 이전 작업이 아직 종료 중 | 연결을 덮어쓰지 않고 대기/오류를 유지. 무조건 재연결하지 않음 |
| 권한 거절, Bluetooth off, pairing invalid/rejected | 이번 호출 종료. 자동 재연결 반복 없음. 연결 상태는 재사용 불가로 표시 |
| locked, 사용자 요청 거절, 앱 미설치/미지원 | 해당 오류 반환. 이를 통신 실패로 간주하지 않음 |
| 원인이 분류되지 않은 unavailable | 현재 호출은 실패. 다음 명시적 시도에서 native가 idle이면 연결을 정리하고 다시 준비; 동일 연결 probe만 무한 반복하지 않음 |

disconnect를 시작할 때 Dart의 재사용 가능 상태부터 해제하고, 실패하면 cleanup 필요 상태를 유지한다. Dart ID만 null로 바꾸고 native를 그대로 둔 채 connect하는 동작은 금지한다. 연결 실패가 원래 pairing/권한 오류를 일반 오류로 덮어쓰지 않도록 원인도 보존한다.

## 4단계 — 준비 단계의 제한된 재연결

공통 순서는 `기존 작업 종료 확인 → stop discovery/기존 세션 정리 → 동일 기기 connect → readiness → 실제 작업`으로 한다. 준비 과정에서 통신 오류가 발생하면 한 번만 이 복구 절차를 수행한다. 같은 작업에서 복구가 또 실패하면 상위로 반환한다.

- macOS의 작업 전 새 연결 정책은 유지하되 Apple 종료 수정 위에서 실행한다.
- iOS/Android는 건강한 연결을 계속 사용할 수 있다. 통신 실패 이후에는 반드시 정리를 거친다.
- Android는 정리 대상 객체를 확보한 뒤 cleanup을 실행하고 완료/실패 전까지 SDK 전역 작업 슬롯을 유지한다. handler 재생성 중에도 같은 규칙을 적용한다.
- Android의 SDK 내부 연결 맵이 늦게 제거되는 경우 `Device already connected`만 별도로 식별한다. 명시적 cleanup 이후 이 오류에 한해서 짧은 backoff로 재시도하며 총 5초를 상한으로 둔다. 시간은 주입 가능하게 하여 테스트한다. 다른 오류를 이 루프에 넣지 않는다.
- Android cleanup 실패를 성공으로 처리하지 않는다. 다음 시도에 정리를 재개할 수 있도록 대상 정보를 유지한다.
- readiness/연결 오류의 자동 복구는 실제 서명/UFVK operation callback을 시작하기 전까지만 적용한다. APDU가 이미 시작된 뒤 실패하면 현재 동작을 자동 재실행하지 않고 사용자 재시도로 넘긴다.
- 여러 호출이 연결을 동시에 정리/교체하지 않도록 native 작업 소유권과 Dart 준비 진입을 직렬화하거나 명시적 busy로 거절한다. 기존 signing status cooldown도 유지한다.

## 5단계 — 검증 및 완료 기준

| 계층 | 필수 시나리오 |
|---|---|
| Apple SDK | partial response 후 단절, callback 한 번 완료, 늦은 이전 응답 무시, 새 세션 버퍼 오염 없음, MTU write 실패/응답 유실 |
| Apple handler | currentApp/UFVK/sign 중 단절 후 새 작업 성공, 취소와 단절 경합, close 후 새 handler 연결, 앱 전환 단절 복구 |
| Android handler | NoResponse 후 기존 SDK 연결 정리, 지연된 맵 제거/already-connected, cleanup 실패 후 재시도, Activity 재생성 중 중복 작업 차단 |
| Dart service | healthy/invalid/busy 분기, 정리 실패 후 connect 차단, 준비 재연결 1회 상한, APDU 시작 후 자동 replay 없음 |
| 제품 흐름 | Send/Swap/Shield에서 실패 후 재시도 시 새 연결로 진행, 완료한 서명 및 TEX 이전 라운드 보존, checkpoint/broadcast 재시도는 기기 서명 반복 없음 |

실행할 검증: 관련 Dart 서비스·서명 화면 테스트, 모바일 태그 테스트는 `--run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`, shared Apple native/SDK 테스트, Android Robolectric, `fvm flutter analyze`, iOS Simulator/macOS 빌드로 로컬 Swift package 연결 확인. 필요한 macOS 실행은 기본 숨김 모드를 사용한다.

실기기 확인에서는 macOS/iOS/Android 각각 APDU 응답 중 전원 off 또는 BT 단절 → 기기 복귀 → Try again → 연결 및 기기 작업 성공까지 확인한다. 테스트 없이 실기기 복구가 검증됐다고 표시하지 않는다.

완료 기준은 버튼 반응이나 오류 문구 변화가 아니라 **이전 요청이 한 번 종료되고, 이전 콜백/버퍼와 분리된 새 연결에서 작업이 성공하며, 중복 서명 요청이 없는 것**이다.

## 변경 단위와 범위

구현은 세 단위로 나눠 검토 가능하게 만든다: ① Apple SDK 의존성 고정 및 종료 수정, ② 모바일 공통 오류/연결 복구와 Android 경계 수정, ③ 제품 흐름 회귀 검증.

권한 재요청 UX, OS 페어링 삭제 안내, 기존 계정 기기 재지정 UI는 직전 답변의 3~5번 후속 작업으로 남긴다. 다만 이번 복구 정책에서 해당 오류를 정확히 분류하고 보존하는 작업은 포함한다. Rust 서명/브로드캐스트 로직은 이번 수정 대상이 아니다.
