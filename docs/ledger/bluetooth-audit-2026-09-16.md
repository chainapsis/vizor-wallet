# Ledger Bluetooth 관리 분석 — 2026-09-16

분석 기준: `6ce81a85ea43195141b8dbe24284f17a773f4246`. 앱 코드는 수정하지 않았다. Dart UI/서비스, Swift/Kotlin 네이티브 핸들러, 실제 고정 버전 SDK 소스까지 추적했고 별도 실패 재현 테스트를 실행했다.

**결론: “Try again을 눌러도 진행되지 않는다”를 만드는 코드 경로가 확인됐다.** 특히 Apple의 끊어진 연결에서 미완료 응답이 영구 대기하는 문제, 모바일의 불완전한 재연결 정책, 복구 방법을 숨기는 UI가 겹친다. 다만 보고된 사용자 세션의 로그·기기·발생 화면이 없으므로 그 사건의 단일 원인을 특정했다고 주장하지 않는다. 아래는 재현 또는 코드로 확정한 동작이며, 무선/OS가 어떤 오류를 발생시키는지는 별도로 구분했다.

## 1. 플랫폼별 구조

| 플랫폼 | 실제 연결 | 재시도 시 연결 처리 | 권한 요청 위치 |
|---|---|---|---|
| macOS | USB 또는 BLE. BLE는 iOS와 같은 Swift 핸들러, Ledger BleTransport 1.0.1 | 기존 계정 작업에서 매번 `disconnect → connect → 앱 확인`. 선택창 재검색도 disconnect부터 수행 | BLE 선택창. 기존 계정의 서명 경로에는 요청 없음 |
| Windows/Linux | USB HID만 사용 | 저장된 선호가 Bluetooth여도 USB로 강제 | Bluetooth 권한/페어링 대상 아님 |
| iOS | BLE만 사용 | Dart의 저장된 연결 ID가 같으면 `currentApp`으로 확인. `disconnected`일 때만 connect 호출 | 모바일 기기 선택창 |
| Android | BLE만 사용. Ledger DMK 0.0.4 | iOS와 같은 Dart 정책. 네이티브는 DMK의 연결 객체와 자동 재연결도 사용 | 모바일 기기 선택창 |

근거: [플랫폼 지원](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/ledger_capability.dart:143), [공통 연결 흐름](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/services/ledger_connection_service.dart:90), [macOS에서 Swift 파일 공유](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/macos/Runner.xcodeproj/project.pbxproj:85).

계정에 영구 저장하는 것은 `ledgerDeviceId`, 이름, 모델, 연결 선호, 마지막 성공 transport이다. **Bluetooth bond/암호키를 앱이 저장하는 구조가 아니다.** OS/기기가 페어링을 관리하며, 앱의 device ID가 남아 있다는 사실은 페어링이나 연결이 유효하다는 증거가 아니다. [계정 모델](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/providers/account_models.dart:54).

## 2. 확인된 주요 문제

### A. P1 — macOS/iOS: 연결이 끊겨도 이전 APDU 대기가 끝나지 않아 재시도가 막힌다

확정한 순서:

1. `currentApp`, UFVK 읽기 또는 서명 APDU가 응답을 기다린다.
2. 응답 전에 Ledger 연결이 끊긴다.
3. BleTransport 1.0.1의 `clearConnection()`은 연결 변수와 `isExchanging`을 정리하고 disconnect 콜백을 호출한다. **대기 중인 `exchangeCallback`에는 실패를 전달하지 않는다.** async exchange는 `withCheckedThrowingContinuation`이므로 콜백 없이는 끝나지 않는다.
4. 앱의 `handleDisconnected()`는 Dart에 `disconnected`를 전달하고 Swift Task를 취소한다. 하지만 취소만으로 SDK continuation이 끝나지는 않는다.
5. 앱은 `exchangeTask != nil`인 동안 `connect`, `disconnect`, `startDiscovery`를 모두 `unavailable`로 거절한다. Task를 비우는 `defer`는 SDK 호출이 돌아와야 실행된다.
6. 실제로 이미 끊긴 기기에서는 이전 응답이 돌아오지 않는다. 화면을 닫고 다시 열어도 동일 핸들러/transport의 대기를 해결하지 못한다.

**재현:** 현재 핸들러에 SDK와 동일하게 취소를 무시하는 pending transport를 주입하고 실제 disconnect 콜백을 발생시켰다. Dart 오류는 한 번 전달됐지만, 이후 3회의 연결·검색·연결 해제 요청이 모두 거절됐다. transport는 이미 `isConnected == false`인데도 새 connect/scan 호출은 0회였다. 테스트 정리를 위해서만 가상의 늦은 응답을 전달했다. 이는 단순히 “사용자가 Ledger 승인 버튼을 누르지 않았다”와 다른 상황이다.

근거: [disconnect 처리](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/ios/Runner/LedgerMobileHandler.swift:575), [미완료 작업 가드/취소](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/ios/Runner/LedgerMobileHandler.swift:719), [고정 SDK의 clearConnection·async exchange](https://github.com/LedgerHQ/hw-transport-ios-ble/blob/4df8fff21c1738a1dff4d2ee19175dd3263d6c5f/Sources/BleTransport/BleTransport.swift#L625).

수정 방향: transport 수준에서 disconnect 시 pending exchange를 정확히 한 번 실패 완료해야 한다. 취소했다고 슬롯만 비우고 같은 transport를 재사용하면 늦은 콜백/중복 응답 문제가 생기므로 안전한 종료 또는 transport 교체 경계까지 필요하다. macOS가 매번 reconnect하는 정책만으로는 이 문제를 해결하지 못한다.

### B. P1 — 기존 계정으로 Ledger를 사용할 때 권한을 다시 요청하지 않는다

`requestPermissions()`의 제품 호출자는 데스크탑 BLE 선택창과 모바일 기기 선택창뿐이다. 송금·스왑·실딩 등 기존 계정의 `LedgerConnectionService._runBluetooth()`에는 권한 확인/요청 단계가 없다. native `connect`, `currentApp`도 권한 요청 UI를 띄우지 않는다.

따라서 **Android에서 권한을 취소한 뒤 기존 계정으로 서명하면, 재요청이 가능한 상태라도 앱은 재요청하지 않고 연결 오류로 종료한다.** Try again도 같은 경로를 반복한다. 재현한 연결 서비스 테스트에서는 2회 작업 시도 동안 권한 요청이 0회였다. 선택창으로 진입하면 요청 경로가 있지만 기존 계정의 실패 UI에서 그 선택창으로 연결하는 기능이 없다.

Apple은 denied/restricted 상태에서 `requestPermissions()`가 false를 반환하도록 되어 있다. 거절된 권한을 자동으로 다시 허용시키는 기능은 없으며 선택창은 Settings 안내를 보여준다. 기존 계정 서명 화면에는 동일한 복구 안내가 일관되게 유지되지 않는다(C 참조).

근거: [서명 전 연결](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/services/ledger_connection_service.dart:135), [Android 요청](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt:113), [Apple 요청](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/ios/Runner/LedgerMobileHandler.swift:274).

수정 방향: BLE 진입점에서 권한 상태를 검사하고 Android의 요청 가능한 거절/설정에서만 복구 가능한 거절을 구분한다. 설정 이동과 복귀 후 재확인을 제공한다. OS가 허용하지 않는 재프롬프트를 반복하는 방식으로 해결해서는 안 된다.

### C. P1 — 페어링/권한/미완료 요청의 복구 안내가 서명 UI에서 소실된다

Apple native → Dart 서비스는 `pairing_invalid`를 “Bluetooth 설정에서 이 Ledger를 지운 뒤 다시 연결” 안내로 변환한다. 연결 서비스도 이를 보존한다. 하지만 desktop Send와 mobile Send의 마지막 오류 표시 함수는 문자열 일부만 검사하고 나머지를 **“Zcash 앱을 열고 다시 시도”**로 바꾼다. Swap/Shield도 해당 오류를 일반적인 서명/실딩 실패로 바꾼다.

결과적으로 사용자에게 필요한 조치는 OS 페어링 삭제나 권한 설정인데, UI는 기기 앱을 열고 Try again을 누르도록 안내한다. A의 “기기에 남은 요청 완료/거절” 메시지도 같은 경로에서 사라진다.

**재현:** mobile Send에 `pairingInvalid`, `permissionDenied`를 각각 주입했다. 두 경우 모두 원래 안내는 화면에 없고 Try again만 나타났다. 버튼을 누르면 signer는 두 번째 호출됐지만 구체적인 안내는 여전히 나타나지 않았다. desktop Send와 Swap/Shield는 해당 표시 함수를 직접 추적했다.

근거: [모바일 Send](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/send/screens/mobile/mobile_ledger_send_sign_screen.dart:317), [데스크탑 Send](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/send/screens/send_review_screen.dart:422), [Swap](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/swap/widgets/swap_ledger_signing_overlay.dart:639), [Shield](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/home/widgets/ledger_shield_signing_overlay.dart:534).

수정 방향: typed connection failure를 UI까지 전달하고 오류별로 권한 설정/페어링 초기화/기기 요청 완료/재연결을 구분한다. 일반 Try again보다 먼저 실제 복구 행동을 제공해야 한다.

### D. P2 — 모바일 기기 선택창은 목록이 있으면 연결 실패 이유를 숨긴다

`_handleFailure()`는 `_error`와 failed 상태를 설정하지만 기존 `_devices`는 유지한다. `build()`는 `_devices.isNotEmpty`를 먼저 검사해 목록만 렌더링하고 오류 설명을 렌더링하지 않는다. 아래에는 Try again 버튼이 나타난다.

**재현:** Ledger 한 대를 검색한 뒤 연결에서 `pairingInvalid`를 발생시켰다. 기기 행과 Try again은 표시됐지만 “OS에서 기기를 지우라”는 안내는 존재하지 않았다. 권한 취소/BT off가 검색 결과 이후 발생하는 경우에도 같은 분기다.

근거: [오류 상태 저장](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart:172), [목록 우선 렌더링](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart:232).

### E. P2 — 모바일은 오류 종류에 따라 동일 연결을 반복 사용하거나 정리 없이 재연결한다

기존 ID와 일치하면 `currentApp()`을 호출하고, 오직 `LedgerMobileFailure.disconnected`일 때만 `connect()`한다. `unavailable`, `pairingInvalid`, `permissionDenied`, `bluetoothOff`에는 연결 정리가 없다. Dart ID도 `currentApp`의 disconnected와 성공한 명시적 disconnect에서만 지운다. APDU 오류 자체에는 연결 ID 무효화가 없다.

**재현:** 동일 ID의 연결이 `unavailable`을 계속 반환하도록 했다. iOS/Android에서 2회 재시도해도 disconnect 0회, connect 0회였다. macOS는 동일 조건에서 disconnect/connect 각 2회였다. 이것은 “모든 unavailable이 재연결로 해결된다”는 뜻이 아니라 **재시도가 연결 복구를 수행하지 않는다는 확정 결과**다.

`disconnected` 분기도 기존 native 연결을 명시적으로 끊지 않고 connect한다. Android는 `NoResponse`를 disconnected로 매핑하지만 SDK에서는 빈 APDU 응답이 `NoResponse`가 될 수 있고 그 결과만으로 연결 맵을 지우지 않는다. 동일 ID가 아직 맵에 있으면 DMK의 새 connect는 `Device already connected`로 거절된다. Apple도 transport가 연결을 유지한 write/read 오류 후 새 connect를 호출하면 `Already connected to a peripheral`로 거절한다. **앱의 disconnected 분류와 SDK의 실제 연결 여부가 동일하지 않다.**

근거: [모바일 재연결 분기](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/services/ledger_connection_service.dart:165), [Dart ID 관리](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/services/ledger_mobile_ble_service.dart:177), [Android 오류 매핑](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt:545). SDK 근거는 DMK 0.0.4의 `ApduGlobalErrorHandler`, `DeviceConnectionStateMachine`, `AndroidBluetoothTransport.connect`를 대조했다.

반대로 Android의 **초기 connect가 실패한 경우** SDK는 `deviceConnections`에서 해당 항목을 지운다. 따라서 “Android는 실패한 모든 연결을 계속 캐시한다”는 주장은 맞지 않는다. 문제는 오류 후 앱과 SDK 상태가 어긋나는 경로와 재연결 경계다.

### F. P2 — 기존 계정의 Bluetooth 기기를 다시 지정하는 복구 UI가 없다

기기 선택은 onboarding에만 있고, 기존 계정의 실패 UI는 desktop의 Auto/USB/Bluetooth 선호 선택만 제공한다. `recordLedgerConnection()`에는 device ID 갱신 인자가 있지만 작업 성공 경로는 transport만 전달한다. 모바일 서명은 저장 ID만 사용하고, Android 재검색도 그 ID와 정확히 일치하는 기기만 찾는다.

따라서 기존 식별자로 다시 발견되는 기기는 재연결할 수 있지만, **다른 식별자로 노출되는 경우 기존 계정을 유지한 채 새 기기에 재연결하는 제품 경로가 없다.** “페어링을 지우면 언제나 ID가 바뀐다”는 주장은 하지 않는다. OS/장치별 식별자 변화 여부와 별개로, 바뀌었을 때의 복구 부재는 확정이다.

근거: [Android 저장 ID 재검색](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt:247), [연결 메타데이터 갱신](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/services/ledger_connection_service.dart:199), [실패 화면의 선호 선택](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/lib/src/features/ledger/widgets/ledger_signing_modal.dart:340).

수정 시 새 기기의 계정 공개키/계정 식별 일치를 검증한 뒤 ID를 갱신해야 한다. 단순히 주변의 첫 Ledger로 교체하면 안 된다.

## 3. Ledger가 자체 페어링을 지웠을 때

**macOS/iOS:** 다음 연결 시 CoreBluetooth가 `peerRemovedPairingInformation`을 반환하면 앱은 전용 `pairing_invalid`로 분류한다. SDK가 NSError를 문자열로 바꾸므로 OS의 해당 오류 localizedDescription과 정확히 같은 문자열도 인식한다. 자동 unpair/reset은 하지 않는다. OS Bluetooth 설정에서 해당 Ledger를 Forget한 뒤 재연결하는 안내가 의도된 복구 경로다. desktop onboarding은 안내를 표시하지만 mobile picker에는 D, 기존 서명에는 C가 적용된다. 끊김이 진행 중 APDU와 겹치면 A도 적용된다.

근거: [Apple 오류 분류](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/ios/Runner/LedgerMobileHandler.swift:1294), [Apple 공식 오류 정의](https://developer.apple.com/documentation/corebluetooth/cberror-swift.struct/code/peerremovedpairinginformation).

**Android:** OS/DMK가 페어링을 처리한다. DMK에는 PairingFailed/Unknown/timeout 등은 있지만 앱에서 pairing-invalid를 별도 생성하는 분기가 없다. PairingFailed는 `pairing_rejected`로 바뀌어 “거절되었거나 실패”라는 메시지만 제공한다. 앱에 bond 삭제, 양쪽 bond 일치 검사, 불일치 복구 절차는 없다. SDK 소스에서도 앱이 사용할 자동 removeBond 경로는 확인되지 않았다.

Ledger가 키를 지운 뒤 Android OS가 자동으로 새 pairing을 성립시키면 이어서 동작한다. 그렇지 않고 실패를 반환하면 위 매핑에 따라 일반 실패로 끝나며, 앱이 스스로 불일치를 교정하지 않는다. 어떤 오류가 실제 발생할지는 Android 버전·Ledger 펌웨어의 무선 동작을 측정해야 하므로 여기서 하나로 단정하지 않는다. **확정 결론은 현재 앱에 불일치를 감지하고 복구를 보장하는 관리 흐름이 없다는 것이다.**

## 4. 권한 취소 이후의 세부 동작

| 상황 | 현재 구현 |
|---|---|
| Android 12+ 기기 선택창 진입/재검색 | SCAN/CONNECT 누락 권한을 조회하고 시스템 요청 |
| Android 11 이하 기기 선택창 | FINE_LOCATION 요청. 위치 서비스 off도 SDK에서 실패 처리 |
| Android 권한 반복 거절 | 요청은 해도 OS가 대화상자를 다시 보여주지 않을 수 있음. UI는 Settings에서 허용하라는 텍스트만 제공 |
| macOS/iOS 최초 요청 | CoreBluetooth 초기화/검색 경로로 최초 시스템 권한 처리 |
| macOS/iOS denied/restricted | false/permission_denied. 선택창에서 설정 변경 안내 |
| 기존 계정 송금/스왑/실딩 | 권한 요청 단계 없음. native 실패를 수신하며 일부 UI가 원인 안내를 소실 |
| 설정에서 권한을 복구하고 앱 복귀 | Ledger 선택창에 복귀 자동 재확인 observer가 없음. 직접 재시도 필요 |

Android의 재요청 제한은 [공식 런타임 권한 문서](https://developer.android.com/training/permissions/requesting), SCAN/CONNECT 요구는 [Bluetooth 권한 문서](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)에서 확인했다.

또한 선택창 순서가 `stopDiscovery → disconnect → requestPermissions`이다. **앞선 cleanup이 실패/대기하면 권한 요청에 도달하지 않는다.** A가 발생한 Apple 세션은 이 조건에 해당한다. Android에서 권한 철회와 native cleanup 예외가 겹치는 경우에도 동일한 순서상의 제약이 있다. 모든 권한 철회가 이 cleanup 실패를 유발한다고 단정하지 않는다.

Android 구버전의 “위치 서비스를 켜야 함” 오류는 `permission_denied`에 함께 매핑되고, mobile picker는 이를 일반 Bluetooth 앱 권한 안내로 바꾼다. 앱 권한은 이미 있어도 위치 서비스를 켜야 하는 경우의 조치가 잘못 안내된다.

## 5. 그 외 확인사항

- **Apple 연결 완료 대기에도 구멍이 있다.** SDK connect는 GATT 연결 후 notification과 MTU 응답까지 받아야 성공한다. `inferMTU()`의 write 실패는 로그만 남기고 connect 실패 콜백을 호출하지 않는다. MTU 응답 대기에도 별도 deadline이 없다. 이 조건이면 앱의 `transportCallbackPending`이 남고, 취소 후에도 콜백을 기다리는 cleanup 경로가 막힌다. SDK의 5초 연결 timeout을 전체 handshake의 timeout으로 해석하면 안 된다. [고정 SDK inferMTU](https://github.com/LedgerHQ/hw-transport-ios-ble/blob/4df8fff21c1738a1dff4d2ee19175dd3263d6c5f/Sources/BleTransport/BleTransport.swift#L606).
- **Android는 연결 timeout과 자체 재연결이 있다.** 앱의 저장 기기 rediscovery는 15초, DMK 외부 connect 기본 timeout은 15초다. BLE 내부 초기 연결 제한은 1분이지만 외부 제한이 먼저 적용된다. 기존 연결의 SDK 재연결은 10초/5회 정책이다. Apple의 APDU 단절 문제를 그대로 Android에도 발생한다고 확장하지 않는다.
- **취소 직후 busy는 정상 보호인 경우도 있다.** 양쪽 native는 취소된 요청의 실제 SDK 작업이 끝나기 전 새 작업을 막는다. Ledger에 아직 승인창이 살아 있다면 기기에서 완료/거절해야 한다. Android는 Activity 재생성 후에도 SDK 전역 작업 소유권을 유지한다. 이 보호 자체를 제거해서 고쳐서는 안 된다. 문제는 영원히 끝나지 않는 경로와 안내의 소실이다.
- **선택창 재검색은 명시적 disconnect를 수행한다.** 따라서 일반적인 picker Try again이 무조건 이전 연결을 재사용한다는 해석은 틀리다. 새 검색 전에 cleanup이 성공하는지가 핵심이다.
- **자동 USB/BLE fallback은 작업 시작 전 준비 실패에만 적용된다.** 서명 콜백이 시작된 뒤에는 다른 transport에서 자동 재실행하지 않는다. 무조건 서명 재전송하는 구조는 아니다.
- **권한 선언은 존재한다.** Android 버전별 manifest 권한, iOS/macOS 설명 문구, macOS Bluetooth entitlement를 확인했다. 발견한 문제는 선언 누락보다 런타임 복구 흐름에 있다.
- **기존 테스트/Speculos만으로 무선 동작을 검증할 수 없다.** 기존 검증은 mock/가짜 응답 중심이다. 실제 bond 삭제·OS 권한 철회·무선 단절은 실기기 인수 테스트가 별도로 필요하다.

## 6. 검증 결과와 재현 자료

| 검증 | 결과 |
|---|---|
| 기존 Dart connection/mobile BLE/readiness/desktop onboarding | 68개 통과 |
| 기존 shared Apple handler | 34개 통과 |
| 기존 Android LedgerMobileHandler Robolectric | 27개 통과 |
| 추가 Dart 연결 재시도 비교 | iOS/Android/macOS 3개 통과: 위 E의 현재 결함 동작을 확인하는 재현 |
| 추가 Apple 단절 후 대기 재현 + 기존 테스트 | 35개 통과: 위 A 재현 1개 포함 |
| 모바일 picker/Send 기존 테스트 + 추가 재현 | 37개 통과: D 1개, C 2개 포함 |

**재현 테스트의 “통과”는 결함이 없다는 의미가 아니다.** 오류 안내가 없는 것, 새 연결이 호출되지 않는 것, 끊긴 transport인데 busy인 것 등 현재 결함 동작을 assertion으로 확인했다. Apple 단절 재현은 native 핸들러를 실행했고 무선 transport는 고정 SDK의 continuation 동작을 모사했다. 실제 라디오/실제 Ledger로 해당 순서를 실행한 것은 아니다.

모바일 추가 테스트의 최초 실행은 스캔 로더가 계속 애니메이션하는 화면에서 `pumpAndSettle`을 사용해 테스트 자체가 timeout됐다. 유한한 pump로 바꾸고 재실행해 위 최종 결과를 얻었다. Android는 wrapper 실행 파일이 없고 Java 25가 Gradle과 맞지 않아, 설치된 동일 Gradle 8.14와 Java 17로 실행했다.

- [검증 결과 발췌](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/docs/ledger/bluetooth-audit-2026-09-16/verification.txt)
- [실행한 재현 테스트 패치](/Users/yjh/.codex/worktrees/89a7/vizor-wallet/docs/ledger/bluetooth-audit-2026-09-16/reproduction.patch): 기존 테스트 파일에 추가할 수 있는 패치이며 제품 코드 변경은 없다. 조사 중 임시 테스트 파일은 제거했다.
- SDK 분석: Apple pin `4df8fff21c1738a1dff4d2ee19175dd3263d6c5f`와 [Android DMK 0.0.4 공식 배포 소스](https://repo.maven.apache.org/maven2/io/github/ledgerhq/device-management-kit-android/0.0.4/device-management-kit-android-0.0.4-sources.jar)를 사용했다.

패치를 적용한 별도 작업 사본에서 추가 재현은 아래와 같이 실행할 수 있다.

```bash
fvm flutter test test/features/ledger/ledger_connection_service_test.dart --plain-name AUDIT
fvm flutter test test/features/onboarding/mobile_ledger_connect_screen_test.dart test/features/send/mobile_ledger_send_sign_screen_test.dart --plain-name AUDIT --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile
python3 scripts/test-ledger-apple.py
```

## 7. 수정 우선순위와 완료 기준

1. Apple의 실제 disconnect/handshake 실패가 pending 작업을 정확히 한 번 종료하도록 수정. 응답 유실 후 재검색/재연결까지 테스트한다.
2. 모든 Ledger BLE 진입점에 권한 복구를 공통 적용하고, 원인별 UI 안내를 보존한다. 모바일 picker의 목록/오류 동시 표시도 수정한다.
3. 모바일 연결 상태를 Dart ID가 아닌 native 세션 상태와 함께 관리한다. 실패 분류에 맞는 정리 후 재연결을 구현하고 `already connected` 반복을 차단한다.
4. 기존 계정의 기기 재선택·재페어링 경로를 만들고 계정 일치 검증 후 저장 ID를 갱신한다.
5. 실기기에서 각 OS별로 연결 중 전원 off, APDU 응답 중 단절, Ledger 쪽 bond 삭제, OS 쪽 Forget, 앱 권한 철회/복구, Android 영구 거절과 구버전 위치 서비스 off를 검증한다. UI 버튼이 반응하는 것뿐 아니라 새 연결 성립과 이후 계정 확인/서명 성공까지 완료 기준으로 삼는다.
