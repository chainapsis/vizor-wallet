# Ledger Bluetooth 권한 복구 결과

대상: iOS, Android, macOS. 기준 커밋: `3a3248f2b`.

## 사용자 흐름

- 기존 계정의 Bluetooth 연결과 온보딩 검색/기기 선택 전에 접근 상태를 확인한다.
  권한 조회는 시스템 팝업을 띄우거나 기기를 검색하지 않는다.
- 요청 가능한 상태에서는 `Allow permission`, 설정 변경이 필요한 상태에서는
  `Open settings`를 제공한다. 관리 정책으로 제한된 경우 반복 요청을 제공하지 않는다.
- Android 12 이상은 Bluetooth 권한, 이전 버전은 위치 권한을 안내한다.
  Bluetooth OFF와 위치 서비스 OFF는 권한 거부와 별도로 처리한다.
- macOS의 자동 연결에서 USB가 성공하면 Bluetooth 권한 조회/요청이 없다.
- 설정 복귀 시 상태만 재조회한다. 사용자가 `Try again`을 눌러야 연결/서명을
  다시 시도한다. 서명, 저장, 브로드캐스트를 자동 재실행하지 않는다.
- 설정 실행에 실패하면 직접 설정을 열도록 안내하고 복구 버튼을 유지한다.
- 계정 변경/잠금에 의해 무효화된 요청이나 사라진 화면의 늦은 결과는 버린다.
  중복 클릭과 중복 resume 이벤트는 권한 요청을 중복 실행하지 않는다.

적용 화면: Send, 모바일 Send, Swap, Shield, 즉시 migration, payment-link
Ledger 서명 실패 화면과 모바일/macOS 온보딩 Bluetooth 선택 화면.

## OS별 구현과 한계

- Apple: `CBManager.authorization`을 읽을 때 central manager를 생성하지 않는다.
  명시적인 권한 요청 때만 초기화하고, 실제 authorization callback을 기다린다.
  응답 없는 요청에는 30초 대기 한도를 두고 handler 종료 시 결과를 정리한다.
  iOS는 앱 설정, macOS는 System Settings 앱을 열고 Bluetooth 권한 경로를 안내한다.
- Android: 최초 미허용 상태를 영구 거부로 추정하지 않는다. 실제 요청 결과에서
  거부되었고 rationale도 제공되지 않을 때 settings 상태를 사용한다. 이 정보는
  handler 수명 동안만 유지한다. 재시작 후에는 요청을 한 번 더 시도할 수 있으며,
  요청 가능한 화면에서도 설정으로 이동할 수 있다. 기기 정책 제한은 별도로 조회한다.
- Apple의 radio 상태는 이미 생성된 transport의 callback으로 알고 있는 경우만
  보고한다. 모르는 상태를 OFF로 추정하지 않으며 실제 연결 단계에서도 오류를 처리한다.
- OS 페어링 삭제, 기기 교체, 공개 키 검증 후 재등록은 이 작업에 포함하지 않는다.

## 리뷰에서 수정한 문제

1. Apple의 기존 권한 요청은 사용자가 응답하기 전에 성공을 반환했다.
   실제 응답/timeout/종료까지 결과를 유지하고 대기 중 다른 Ledger 요청을 차단했다.
2. 공통 권한 오류 문구가 요청 가능/제한/구형 Android 위치 권한에도 Bluetooth
   설정만 안내했다. 상위 문구를 중립적으로 바꾸고 상태별로 행동을 안내한다.

전체 diff를 대상으로 수정 후 재리뷰했으며, 미해결로 보류한 항목은 없다.

## 검증

- 데스크톱 Flutter 회귀: 327개 통과, 모바일 태그 파일 1개 정상 skip.
- 모바일 form-factor 회귀: 55개 통과.
- Apple 공용 Swift handler: macOS에서 42개 통과.
- Android handler: Robolectric 38개 통과.
- `fvm flutter analyze --no-pub`: 문제 없음.
- 결정적 Flutter 캡처: 데스크톱 16개, 모바일 26개, 총 42개.
  권한 요청/설정 필요/제한/복구 완료, 구형 Android 위치 권한, 모바일 온보딩을 포함한다.

실물 Ledger와 실제 iOS/Android/macOS 권한 팝업을 이용한 end-to-end 검증은
실행하지 않았다. Swift 테스트는 macOS에서 공유 handler를 검증한 것이며,
iOS 앱 빌드나 실기기 검증을 대신하지 않는다. 스크린샷은 실제 Flutter 위젯과
모의 상태를 사용하며 OS 권한 팝업 자체의 스크린샷은 아니다.

공식 API 참고:

- [Android runtime permissions](https://developer.android.com/training/permissions/requesting)
- [Apple CoreBluetooth authorization](https://developer.apple.com/documentation/corebluetooth/cbmanagerauthorization)

## 다음 작업

기존 Ledger 계정의 기기 재선택/교체 흐름. 같은 니모닉을 복구한 새 기기의 공개
계정 식별 정보를 기존 계정과 비교하고, 일치할 때만 연결 메타데이터를 변경한다.
계정과 거래 내역은 유지하며 다른 니모닉/계정 인덱스는 교체로 승인하지 않는다.
