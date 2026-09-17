# Ledger 모바일 Bluetooth 예외 상황 UX 분석 및 작업 순서

분석 기준: `6e4557f9a`. 대상은 iOS/Android의 기존 계정 연결, 서명,
온보딩 기기 선택 흐름이다. 사용자 요청에 따라 분석을 보존하고 작업을
단위별로 진행한다. 아래 분석은 수정 전 상태를 기록한다.

진행 상태: 사용자 요청으로 macOS Bluetooth까지 범위를 확장했고, 1차
오류 안내 보존 작업을 완료했다. [구현 및 검증 결과](bluetooth-guidance-result-2026-09-17.md)
참조. 2차 권한 재요청/설정 복귀도 구현했다.
[권한 복구 결과](bluetooth-permission-result-2026-09-17.md)를 참조한다.
기기 교체와 실제 기기를 이용한 OS별 검증은 후속 작업으로 남아 있다.

## 현재 결론

기존 Bluetooth 복구 패치로 실패한 세션 정리와 재연결은 개선되어 있다.
그러나 권한 취소, 페어링 초기화, 기기 교체에 필요한 사용자 복구 경로는
부족하다. 이전 분석 문서를 그대로 현재 동작으로 간주하지 말고 아래의
실패 시점별 차이를 유지한다.

### 1. Ledger 기기에서 페어링 초기화

- iOS: OS의 `peerRemovedPairingInformation`을 받으면 `pairing_invalid`로
  분류하고 휴대폰 Bluetooth 설정에서 기존 Ledger를 지운 뒤 재연결하라는
  메시지를 만든다. 모든 초기화가 반드시 이 오류를 낸다는 뜻은 아니다.
- Android: SDK의 `PairingFailed`를 `pairing_rejected`로 분류한다.
  사용자 거절과 페어링 정보 불일치를 구별하지 못한다.
- 재시도는 실패 세션을 정리하고 저장된 동일 기기 ID에 연결한다.
  OS bond를 삭제하거나 다른 기기를 선택하는 기능은 없다.
- 최초 연결 실패 또는 서명 통신 실패는 Send/Swap/Shield의 일반 오류
  문구로 바뀔 수 있다. 반면 Zcash 앱 준비 단계의 실패는 공용
  `LedgerSigningModal`이 readiness 메시지를 복원할 수 있다.
- 모바일 기기 선택창은 검색 결과가 남아 있으면 목록을 오류보다 우선
  표시하여 실제 실패 이유가 숨겨질 수 있다.

### 2. 앱의 Bluetooth 권한 취소

- 기존 계정의 `LedgerConnectionService._runBluetooth`에는 권한 요청이
  없다. 제품의 권한 요청 호출자는 온보딩 기기 선택창들이다.
- iOS: denied/restricted는 선택창에서 false로 처리하고 Settings 안내를
  표시한다. 기존 서명 실패에서 같은 복구 안내가 항상 유지되지는 않는다.
- Android: 재요청 가능한 상태라도 기존 서명 흐름은 권한을 요청하지 않는다.
  선택창은 요청하지만 재요청 가능 여부와 설정에서만 복구 가능한 거절을
  구별하지 않는다.
- 전용 설정 이동 및 복귀 후 상태 재확인 흐름이 없다.
- Android 12 이상은 SCAN/CONNECT, 이전 버전은 위치 권한을 요청한다.
  `LocationDisabled`는 네이티브에서 위치 활성화 메시지를 만들지만
  선택창이 `permissionDenied`로 묶어 일반 Bluetooth 권한 안내로 덮는다.

### 3. 같은 계정을 복원한 새 Ledger로 교체

- iOS는 저장된 기기 UUID, Android는 저장된 ID와 일치하는 기기로 연결한다.
  Android 재검색 경로는 최대 15초이며 다른 ID의 기기를 대신 선택하지 않는다.
- 기존 계정에 새 기기를 재지정하는 UI가 없다.
- 온보딩에서 동일 UFVK를 가져오면 중복 Ledger 계정으로 거절되며,
  기존 계정의 기기 정보를 갱신하지 않는다.
- 필요한 복구: 기존 계정에서 새 기기 선택 → 기기 승인으로 공개 계정
  정보 읽기 → 기존 UFVK와 비교 → 일치할 때 연결 메타데이터만 갱신.
  니모닉뿐 아니라 passphrase/계정 인덱스가 달라질 수 있으므로 기기 이름,
  모델 또는 연결 성공만으로 계정 일치를 판단해서는 안 된다.
- 계정 삭제/재가져오기를 정상적인 기기 교체 UX로 사용하지 않는다.

## 추가 검토 시나리오

| 상황 | 확인 또는 검증할 사용자 경험 |
| --- | --- |
| 휴대폰 Bluetooth OFF | 켜기 안내 보존, 설정 복귀 후 재확인 |
| Ledger 전원 OFF/방전/거리 이탈 | 단절 안내와 재연결. 준비 단계 기존 세션 단절은 한 번 자동 복구 |
| 페어링 팝업 취소 | 거래 승인 거절과 구분. Android 원인 불명 실패를 초기화 문제로 단정하지 않기 |
| Ledger 잠금/다른 앱/지원하지 않는 앱 버전 | 준비 단계 안내를 유지하고 서명 중 실패도 일관되게 처리 |
| 다른 앱/휴대폰이 기기 사용 중 | busy/검색 실패 안내. 원인이 확인되지 않으면 다른 앱 점유로 단정하지 않기 |
| 휴대폰에서 Ledger 등록 삭제 | 재페어링 및 ID 변화 여부를 실기기로 확인, 계정 보존 재선택 |
| 동일 기기를 다른 니모닉으로 초기화 | 연결 성공과 계정 일치를 구분 |
| 설정 복귀/화면 잠금/백그라운드/앱 종료 | OS별 세션 수명, 늦은 응답, 중복 요청 검증 |
| 승인 직후 단절 | 서명 미수신과 수신 후 저장/전송 실패를 구분 |

서명 수신 후 저장 실패에는 기존 모바일 Send의 `Retry saving`과 서명 보존을
유지한다. 일반 통신 오류 때문에 서명 전체를 자동 재실행하지 않는다.
이미 제출한 durable broadcast를 연결 복구 때문에 취소하지 않는다.

## 제안하는 작업 단위

### 1차: 오류 원인과 복구 안내를 화면까지 보존 (먼저 제안)

목표: 사용자가 권한/페어링 문제에 대해 엉뚱한 Zcash 앱 안내나 의미 없는
Try again만 보지 않도록 한다.

범위:

- 최초 연결, 앱 준비 확인, 서명 통신에서 발생한 오류를 공통 표현으로
  연결한다. 문자열 키워드만으로 사용자 거절 등을 판정하지 않도록 한다.
- Send/Swap/Shield의 권한, Bluetooth OFF, 페어링 실패/불일치, 연결 끊김,
  busy 안내를 일관되게 표시한다. 기타 Ledger 소비자의 적용 범위는 착수 시
  호출 경로를 확인하여 명시한다.
- 기기 목록이 남아 있어도 선택창의 오류 설명을 표시한다.
- Android 위치 서비스 OFF 설명을 일반 Bluetooth 권한 문구로 덮지 않는다.
- 지원 버전, 잠금, 실제 사용자 거절, 저장/브로드캐스트 복구 안내를 보존한다.

완료 기준:

- 동일 오류가 연결 전/준비 단계/서명 중 어느 시점에 발생해도 적절한 원인과
  다음 행동을 표시하는 위젯/서비스 테스트가 있다.
- 검색된 기기가 있는 상태에서 페어링/권한 오류를 주입해도 설명이 보인다.
- 권한 오류가 거래 거절로 표시되지 않는다.
- 기존 서명/저장 재시도 경계와 제한된 재연결 동작이 바뀌지 않는다.

이 단위에는 권한 재요청, 설정 이동, OS 페어링 삭제, 기기 교체를 포함하지
않는다. 따라서 안내 개선만으로 복구 흐름 전체가 완성됐다고 보고하지 않는다.

### 2차: 권한 및 설정 복귀 복구

모든 BLE 진입점의 권한 상태 확인, Android 요청 가능/설정 필요 구분,
iOS 설정 안내, 설정 이동 및 복귀 후 재확인을 처리한다. 권한 복구만으로
사용자 승인 서명을 자동 재실행하지 않는다.

### 3차: 기존 계정의 기기 재연결/교체

계정 설정과 서명 실패 화면에서 기기 재선택을 제공한다. 공개 키 일치를
검증하고 기존 계정/거래내역을 유지하며 기기 메타데이터만 갱신한다.
동일 계정 중복 import를 교체 우회 수단으로 사용하지 않는다.

### 4차: 실기기 시나리오 검증 및 잔여 수명 문제

iOS/Android에서 기기측 페어링 초기화, OS 등록 삭제, 권한 취소,
Bluetooth OFF/ON, 실제 기기 교체, 승인 전후 단절, 설정/백그라운드 복귀를
각각 검증한다. 각 작업 단위에서도 해당 실기기 검증이 가능하면 먼저 수행한다.

## 근거 파일

- `lib/src/features/ledger/services/ledger_connection_service.dart`
- `lib/src/features/ledger/services/ledger_mobile_ble_service.dart`
- `lib/src/features/ledger/services/ledger_app_readiness_service.dart`
- `lib/src/features/ledger/widgets/ledger_signing_modal.dart`
- `lib/src/features/send/screens/mobile/mobile_ledger_send_sign_screen.dart`
- `lib/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart`
- `lib/src/features/home/widgets/ledger_shield_signing_overlay.dart`
- `lib/src/features/swap/widgets/swap_ledger_signing_overlay.dart`
- `lib/src/providers/account_provider.dart`
- `ios/Runner/LedgerMobileHandler.swift`
- `android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt`
- `rust/src/wallet/keys.rs`

공식 OS 참고:

- [Apple peerRemovedPairingInformation](https://developer.apple.com/documentation/corebluetooth/cberror-swift.struct/code/peerremovedpairinginformation)
- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)

## 분석 시 실행한 검증

- 연결/BLE 서비스 테스트: 59개 통과.
- mobile define을 사용한 모바일 온보딩/송금 테스트: 34개 통과.
- 앱 코드 수정 없음. 물리 Ledger의 무선/페어링 시나리오는 실행하지 않았다.
- 테스트 통과는 현행 테스트의 회귀 확인이며, 이 문서의 미구현 UX가
  이미 검증됐음을 의미하지 않는다.
