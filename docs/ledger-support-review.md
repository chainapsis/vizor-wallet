# Ledger 지원 검토 — 2026-09-10

현재 기준은 `rowan/ledger-advanced`의 `0c74730724bc8d3f141cd89c82d9268609f8043d`다.
Linux USB는 `796d2a60e`, Bluetooth는 `0c7473072`로 각각 커밋·푸시했다.
[지원 사양](ledger-support.md)을 기준으로 제품 진입점, 공통 signer, OS adapter, 복구와 테스트를 대조했다.
초기 검토 기준은 `0e66e86bc548b1d23a62e489fb50e6b4a766f258`이며, 이후 UFVK 취소,
Wallet Link, Windows USB·BLE, 온보딩 후속 작업의 결과를 구분해 기록한다.

## 결론

일반 송금·TEX·shield·swap/pay·투표의 연결은 존재하며, Ledger가 없는 서명 경로로
자동 우회하는 것을 전제로 하지 않는다. Windows USB·BLE 구현과 Release 교체까지 끝났고,
Windows Stax BLE의 실제 트랜잭션 실행과 주요 복구 경로는 사용자 확인을 받았다.
Linux USB 트랜잭션과 Ubuntu VM의 Stax Bluetooth 연결·트랜잭션 서명도 사용자 확인을 받았다.
Linux BLE 기본 연결·서명 확인을 마쳤고, 다음 종단 확인은
Wallet Link의 실제 데스크톱 QR→모바일 가져오기→BLE 서명이다.
이 과정에서 발견한 전송 취소 후 잔액 갱신 누락은 BLE와 별개인 공통 전송 후속 이슈다.

| 항목 | 판정 | 다음 행동 |
| --- | --- | --- |
| Windows USB / BLE | 구현·Release 빌드·설치 완료. Stax BLE 트랜잭션 실행·주요 복구는 사용자 확인 | 지원할 다른 모델·OS·어댑터 및 기능별 검증표 보완 |
| Linux USB | `796d2a60e` 반영·Ubuntu Release·Stax HID 접근·트랜잭션 사용자 확인 | 최종 BLE 빌드의 USB 실기기 재송금과 기능별·복구별 검증 공백 보완 |
| Linux BLE | `0c7473072` 반영·Release 실행·Stax pairing/연결·계정 가져오기·기존 USB 계정 BLE 등록 확인; 연결·트랜잭션 서명 사용자 확인 | 다른 모델·배포판·어댑터와 기능별·복구별 검증 공백 보완 |
| 전송 취소 후 잔액 갱신 | DB 잠금 해제 후 UI 갱신 누락 확인, 미수정 | BLE와 분리해 discard 완료 후 잔액 갱신 및 회귀 테스트 검토 |
| 실제 배포 앱과 OS·기기별 종단 검증 | 출시 확인이 남음 | 실제 설치 가능한 3.9.3 빌드로 지원 조합 검증 |
| BLE UFVK 요청 중 뒤로 가기/취소 | 후속 코드 수정·제어된 회귀 테스트 통과, Windows 주요 복구 사용자 확인 | iOS/Android/Apple BLE의 pending exchange 경계는 별도 확인 |
| Wallet Link의 Ledger 제외 | 후속 클라이언트 구현·제어된 회귀 테스트 통과 | 실제 데스크톱 QR→모바일 가져오기→BLE 서명 종단 검증은 남음 |
| 수신 주소의 기기 화면 확인 | 미구현 | 하드웨어 지갑의 수신 검증 범위로 포함할지 결정 |
| 4개 shielded display output 제한 | host 선행 검사가 없음, 현재 단일 수신자 경로의 blocker로 보지 않음 | 다중 수신자/배치 출력 확장 전에 계약·테스트 추가 |
| Android 11 최소 버전 | 실제 빌드 제약 | 앱 전체 지원 OS 정책에 이 영향 포함 |
| 과거 probe 문서의 4초 cooldown | 현재 3초와 다른 과거 기록 | 과거 관측값을 보존하고 현재 사양 링크 추가 |

이 표에서 “미지원”은 곧 버그라는 뜻이 아니다. 명시된 미지원 기능을 열거나 SDK를 교체하는 변경은
초기 문서 최신화 범위에 포함하지 않았다. 이후 Linux USB와 BLE 구현은 각각 사용자 요청으로 진행했다.
전체 보안 감사 또는 모든 사용자 경로의 무결함 판정은 아니다.

## 다음 작업 순서

1. **Wallet Link 실기기 종단 확인.** 현재 desktop/mobile 클라이언트로 Ledger 계정을 QR 전송한다.
   기기 없이 가져온 계정의 그룹 이름·index·birthday·동기화를 확인하고, 첫 서명에서 모바일 BLE
   기기를 선택해 wallet fingerprint와 UFVK를 검증한다. 연결만으로 서명하지 않고 `Try again` 이후
   진행하는지, 다른 Ledger는 차단하고 연결을 취소하면 서명하지 않는지도 확인한다.
   실제 송금은 사용할 계정·금액을 먼저 정한다.
   완료 증거는 양쪽 앱 revision·OS·모델·앱 버전과 가져오기→연결→서명 결과다.
2. **출시할 조합의 검증 공백만 보완.** 아래 OS 표에 이미 확인한 조합과 남은 조합을 구분한다.
   Windows Stax의 정상 송금·주요 복구와 Linux USB 송금·Stax BLE 연결/서명 확인을 유지한다.
   iOS/Android의 물리 취소·재연결, Linux 최종 BLE 빌드에서 USB 재송금·기능별 복구,
   출시 대상으로 정한 다른 모델/transport는 별도 확인한다.
   TEX 2회 승인·shield·swap/pay·투표는 일반 송금 성공으로 대체하지 않고 기능별 결과를 남긴다.
3. **출시 조건 확정.** 공개 채널에서 설치 가능한 Zcash 앱과 최소 버전 `3.9.3`의 계약을 대조하고,
   지원 OS·기기 안내 및 최종 배포 빌드의 검증 범위를 맞춘다. 현재 개발 빌드 성공을 공개 배포 확인으로
   기록하지 않는다. Android API 30 하한과 Windows BLE의 OS/어댑터 범위도 포함한다.

수신 주소의 기기 화면 확인은 별도 제품 결정이다. 모바일 USB 지원이나
Orchard→Ironwood 가드 해제도 현재 남은 검증과 묶어 자동으로 구현하지 않는다.

## Linux USB 후속 구현·확인 — 2026-09-09

Ubuntu 24.04 x86_64 VM에서 기존 Rust HID transport를 Linux 빌드에 포함했다.
이 라운드에서는 capability를 mainnet만 허용하고 USB만 연결했다.
이후 9월 10일 BLE 라운드에서 transport preference를 데스크톱 공통 규칙으로 바꿨다.
USB 빌드 의존성에는 `libudev-dev`를 추가했다.

| 확인 항목 | 결과 | 증거의 범위 |
| --- | --- | --- |
| 집중 Dart tests | 45 passed | capability, connection, cancellation, onboarding — 4 files; mock 기반 검사 포함 |
| 변경 Dart analyze | 6 files 통과 | 전체 suite 아님 |
| Ubuntu x86_64 Release | 빌드 exit 0 | Flutter 3.41.6, Rust 1.98.1, 실제 Linux HID 코드 컴파일 |
| VM runtime | 의존성 해석 및 일반 사용자 native library load 통과 | 번들의 `lib` 검색 경로는 기존 AppRun과 같이 `LD_LIBRARY_PATH`로 지정 |
| 실제 앱 화면 | `Connect Ledger` 및 USB 버튼만 표시되는 화면 확인 | 기기 미연결 상태. 가져오기·서명 성공을 뜻하지 않음 |
| Stax USB 접근 | VM passthrough 및 일반 사용자 장치 open 통과 | APDU·가져오기·서명 성공을 뜻하지 않음 |
| Linux native unit tests | 미실행 | Rust unit tests는 이번 라운드에서 별도 실행하지 않음 |

VM의 `/home/vizor/ledger-usb-20260909`에 별도 배치했고 `Vizor Ledger USB Test` 실행 항목을 추가했다.
기존 AppImage·지갑 데이터는 교체하거나 초기화하지 않았다. UID 1000의 실제 데스크톱 세션으로 실행했다.
Stax 연결 후 `/dev/hidraw3`가 root 전용이라 일반 사용자 open에서 `Permission denied`를 재현했다.
앱 readiness classifier가 `denied`를 기기 거절로 오분류해 사용자에게 `request rejected`를 표시했다.
Ledger 전용 udev 규칙을 VM에 설치·적용한 뒤 UID 1000의 HID open이 통과했다.
규칙과 설치 안내를 저장소에 포함했고, 오분류 수정의 실패→통과 회귀 테스트도 추가했다.
후속 집중 Dart 5 files는 55 passed, 오류 분류 관련 Dart 2 files analyze도 통과했다.
9월 9일 종료 시에는 실행 중인 앱을 유지해 오류 문구 수정이 소스에만 반영된 상태였다.
9월 10일 실행한 후속 BLE Release에는 이 안내 수정도 포함했다.
USB 권한 변경 자체는 즉시 적용됐다. 이후 사용자가 Linux USB 실제 트랜잭션 성공을 확인했다.
이는 Linux BLE 또는 TEX·shield·swap/pay·투표 전체 검증 완료를 뜻하지 않는다.

## Linux BLE 후속 구현·확인 — 2026-09-10

BlueZ 시스템 D-Bus와 GIO로 검색·pairing·GATT notification·APDU 교환·취소를 구현했다.
Windows의 Ledger protocol/operation gate를 공통 헤더로 옮겼고, Dart 및 Rust signing API는 유지했다.
온보딩, 계정의 연결 설정, 서명 실패 화면에서 Linux Bluetooth를 선택할 수 있다.

### 초기 구현 검사

- Dart/화면 집중 테스트: 6개 파일, 93 passed. Linux Bluetooth 가져오기→birthday, USB 유지,
  preference·취소·연결 설정·서명 실패 transport 선택을 포함한다.
- USB 권한 오류 분류와 앱 readiness 회귀 테스트 10개도 통과했다. 합계 7개 파일, 103 passed.
- 변경 Dart 정적 검사: 12개 파일 통과.
- Ubuntu native 검사: 경고를 오류로 다루는 C++ 구문 검사 통과.
- 별도 테스트용 D-Bus의 fake BlueZ: UUID 검색, 전원 꺼짐, pairing 거절, 권한 거절,
  분할 APDU 왕복, 검색 시작 중 취소·정리, 취소 후 재연결, 연결 끊김을 실제 GIO 호출/신호로 검증했다.
- 공유 protocol 테스트는 macOS C++ 실행 통과. Windows OS adapter 재빌드는 하지 않았다.
- Ubuntu 24.04 x86_64 Release 빌드 exit 0. runner의 C++17 설정을 포함하며,
  VM 소스 해시와 최종 transport object의 갱신 시각도 확인했다.
- 새 번들 `/home/vizor/ledger-ble-20260910`의 의존성 확인과 일반 사용자 Rust library 로딩 통과.
  runner SHA-256은 `55b6e9afe10544a377b125c77899fee8acc3b10f22cac67ea6227de93c135a47`이다.
  Rust library 해시는 이전 USB 성공 빌드와 같다. USB 권한 오류 안내 수정도 새 Dart 빌드에 포함했다.

위 초기 검사 종료 시에는 동글을 관측하지 못했고 새 번들도 실행 전이었다.
이후 같은 날 사용자 승인으로 실제 앱 교체와 아래 물리 기기 확인을 진행했다.

### Stax 연결·서명 확인과 최종 커밋 검사

Ubuntu 24.04 x86_64 VM에 Bluetooth 동글을 연결하고 Linux 설정과 Stax에서 pairing을 완료했다.
pairing 후 연결 초기화가 멈추는 문제는 Ledger `0002` GATT characteristic에 보낸 write type이 원인이었다.
`WriteValue`를 응답이 있는 `request`로 고쳤고, fake BlueZ도 다른 write type을 거절하도록 보강했다.
MTU 초기화는 서명용 5분 대신 10초 제한으로 분리했다.

수정 Release `/home/vizor/ledger-ble-fixed-20260910`을 실행하고 실제 화면을 확인했다.
기존 지갑 데이터와 pairing은 유지했다. BLE 계정 가져오기와 기존 USB 계정의
`Ledger connection` → `Set up Bluetooth` 등록을 확인했으며, 후자는 같은 UFVK를 검증한 뒤
기존 계정에 BLE 메타데이터만 저장한다. 사용자는 이후 Bluetooth 연결과 트랜잭션 서명 정상 동작을 확인했다.
이 사용자 확인을 에이전트가 직접 검증한 broadcast txid·체인 확인 수나 모든 기능의 성공으로 확대하지 않는다.

| 최종 검사 — 2026-09-10 | 결과 | 범위 |
| --- | --- | --- |
| USB 커밋 스냅샷 | Dart 18 passed, 4 files analyze 통과 | 미커밋 BLE·UI 변경을 제외한 정확한 index 스냅샷 |
| BLE 커밋 스냅샷 | Dart 94 passed, 11 files analyze 통과 | 6개 test files; Linux 가져오기·USB 유지·preference·취소·focus 변화·연결 설정·서명 실패 UI |
| 공용 BLE protocol | macOS C++ 실행 통과 | Windows와 공유하는 framing/parser/operation gate; 알고리즘 변경 없이 헤더 이동 |
| Linux native | fake BlueZ 테스트와 handler/transport C++ 구문 검사 통과 | 스테이징 소스 사용; 취소·재연결·초기화 timeout·write type 포함, 실제 Ledger 미사용 |
| 실행 빌드와 소스 대조 | USB Rust 소스 및 BLE native 소스 해시 일치 | 앞서 빌드한 Linux Release의 소스와 최종 커밋 대상 대조 |
| Windows 전체 재빌드 | 미실행 | 이번 변경은 공유 헤더 이동과 include 경로 교체 |

USB·BLE의 실제 성공은 위 사용자 확인으로 남긴다. 다른 배포판·어댑터·모델,
최종 BLE 빌드의 USB 재송금, TEX·shield·swap/pay·투표 및 모든 복구 조합은 별도 검증 범위다.

## 별도 미해결 이슈: 전송 취소 후 잔액 갱신

데스크톱 Ledger 전송에서 연결 실패 후 서명 화면을 나가면 proposal 입력 잠금은 해제되지만,
UI가 사용 가능 잔액을 즉시 다시 읽지 않는다. BLE 설정을 마치고 전송 화면으로 돌아왔을 때
`Insufficient shielded balance`가 남았고, 이후 자동 동기화로 해소됐다.

읽기 전용 DB 검사에서는 기존 0.0016 ZEC가 미사용·잠금 해제 상태였고 proposal lock도 없었다.
따라서 BLE 등록으로 계정이나 자금이 사라진 현상이 아니다.
[review 종료](../lib/src/features/send/screens/send_review_screen.dart)의 `_scheduleDiscard`와
[공통 cleanup](../lib/src/features/send/services/send_flow.dart)의 `discardSendProposal`은
잠금 해제 이후 SyncProvider 잔액 갱신을 요청하지 않는다.

수정 후보는 성공한 discard/unlock 직후 해당 계정 잔액을 갱신하는 것이다.
이번 USB/BLE 커밋에서는 수정하지 않았다. 공통 전송 cleanup의 별도 이슈로 추적하되,
실제 확인 경로는 데스크톱 Ledger 실패→review 이탈이며 모바일·다른 signer까지 전부 재현한 것은 아니다.

## Windows 후속 구현·확인 — 2026-09-09

USB는 `c37c9c150`, BLE와 중복 index 안내·온보딩 일러스트 재사용은 `6a313d06f`에 반영했다.
Windows BLE는 자체 C++/WinRT GATT adapter로 pairing·연결·framing·MTU·취소를 처리하며,
계정 identity·UFVK·PCZT 구성과 검증은 기존 Rust/Dart 경로를 사용한다.

확인 환경은 Windows 11 ARM64 VM, x64 Release, USB Bluetooth 동글, Ledger Stax다.
최종 Release 빌드와 교체·재실행을 확인했고 기존 지갑 데이터는 유지했다.
진단용 코드도 최종 빌드에서 제거했다.

| 확인 항목 | 결과 | 증거의 범위 |
| --- | --- | --- |
| Stax BLE 연결·Zcash 앱 준비·wallet identity·UFVK | 연결 및 계정 가져오기 확인 | 해당 Windows 환경과 Stax |
| 이미 가져온 index로 재시도 | 사용자 정상 동작 확인 | 일반 추가 경로에서 UFVK 전에 차단하고 원래 화면에 inline 오류 표시 |
| 실제 트랜잭션 실행 | 사용자 성공 보고 | 거래 종류·금액·txid와 체인 확정 결과는 이 문서에 별도 기록하지 않음 |
| 승인 거절·대기 중 취소·끊김 후 재시도 | 사용자 정상 동작 보고 | 시나리오별 횟수·타이밍 로그는 없음. 모든 취소 타이밍 또는 앱 재시작 후 outbox 복구 인증은 아님 |
| Windows 최종 Release | 빌드·교체·프로세스 재실행 확인 | 전체 모델/어댑터 인증 또는 공개 배포를 뜻하지 않음 |
| 집중 Dart 회귀 | 97 passed | 온보딩 22개 + capability/connection/signing/BLE/accounts/dialog 75개, mock 기반 검사 포함 |
| 변경 Dart 15 files | analyze 통과 | 전체 suite 아님 |
| Windows native | C++/WinRT 컴파일 및 portable protocol test 통과 | 컴파일·framing 검증을 RF·서명 성공으로 대신하지 않음 |
| 온보딩 sidebar | birthday/password/customise × light/dark, 캡처 6개 통과·이미지 확인 | 기존 import artwork 재사용. sidebar 캡처이지 전체 실기기 온보딩 경로 검증은 아님 |

위 자동 검사는 Windows 후속 구현 라운드의 결과다. 아래 초기 검토·UFVK·Wallet Link 숫자와
합쳐 현재 head의 전체 suite 통과 수로 표시하지 않는다. 이번 문서 최신화에서는 코드를 변경하거나
Ledger 요청·트랜잭션을 다시 실행하지 않았다.

## OS별 남은 검증과 증거의 경계

### 공식 앱과 native transport를 함께 통과한 검증표

현재 자료는 서로 다른 층을 검증한다.

| 증거 | 실제로 확인하는 것 | 확인하지 않는 것 |
| --- | --- | --- |
| Dart service/widget tests | capability, retry, recovery, 화면 전환, mock 응답 처리 | 기기 firmware·실제 BLE·OS 권한 동작 |
| Rust unit tests | APDU/PCZT/계정/서명 검증, signed operation 상태 | USB/BLE radio, 실제 Ledger 승인, 공개망 반영 |
| Speculos integration 시나리오 | 앱 flow와 firmware emulator를 연결하는 테스트 구성 | 물리 USB/BLE와 실기기 OS 조합. mobile은 BLE service를 HTTP adapter로 대체 |
| Android native probe 기록 | unchanged handler + 공식 DMK + emulator Bluetooth + synthetic peer | 실제 Ledger firmware, RF, 전체 Flutter engine, 지갑 서명·broadcast |
| Apple XCTest | protocol parsing·앱 전환 coordinator | BleTransport 실제 callback·권한·pending exchange drain |

기존 [Android probe 기록](../scripts/ledger-ble-probe/README.md)은 2026-09-07의 관측이다.
정상 경로와 일부 복구는 통과했지만 지연 응답·nullable name 문제도 관측했다.
현재 handler에는 예외 containment와 GATT/session 종료 확인이 있다.
이 수정의 존재를 모든 타이밍과 실기기에서 문제가 사라졌다는 증거로 사용하지 않는다.

검증 시 조합별로 다음을 기록하면 된다.

| 조합 | 필수 시나리오 | 현재 이 검토의 상태 |
| --- | --- | --- |
| macOS USB | 단일 기기, UFVK→서명, 앱 전환, 취소, TEX 2회 승인 | 실기기 재실행 안 함 |
| macOS BLE | 첫 pairing, 저장된 장치 재연결, 다른 transport로 사전 fallback | native 재실행 안 함 |
| Windows USB | import→서명, 앱 전환, 거절·취소, 연결 해제 | 구현·Windows 빌드 완료; 시나리오별 증거는 별도 정리 필요 |
| Windows BLE | pairing, UFVK, 서명, 거절·취소·재연결 | Stax 연결·가져오기 확인, 트랜잭션 실행·주요 복구 사용자 확인; 다른 모델/어댑터·하한 OS는 미확인 |
| Linux USB | 일반 사용자 HID 권한, 앱 준비, UFVK→서명, 취소·연결 해제 | Release·Stax HID 접근 및 트랜잭션 사용자 확인; 기능별·복구별 증거는 별도 확인 |
| Linux BLE | pairing, UFVK→서명, 취소·재연결, USB 회귀 | Ubuntu Release/Stax pairing·가져오기·기존 USB 계정 BLE 등록 확인, 연결·트랜잭션 서명 사용자 확인; 기능별·복구별·USB 재송금은 별도 확인 |
| iOS BLE | 권한 처음/거절, 같은 연결 유지·끊김 앱 전환, pending exchange 취소, background 복귀 | 실기기 재실행 안 함 |
| Android BLE | API 30 위치 권한 / API 31+ BLE 권한, 재탐색, GATT 종료 실패, 예외 이후 같은 프로세스 재연결 | probe·실기기 재실행 안 함 |
| 각 지원 기기 | 정상 서명·거절·연속 승인·최대 용량 | 개별 기기 인증표 미완성 |

위 조합의 검증에서 broadcast가 필요하면 사용할 네트워크·계정·금액을 먼저 정한다.
초기 검토에서는 설치, 기기 조작, 네트워크 송금, regtest/Speculos 실행을 하지 않았다.
Windows·Linux 후속 빌드·설치와 사용자 실기기 확인은 위 기록으로 구분한다.

### UFVK 취소 후속 수정 — 2026-09-09

초기 commit에서는 UFVK가 취소 대상 Task/Job에 등록되지 않았고, Dart의 `0x6901` 대기 중
취소해도 UFVK가 다시 호출되는 현상을 MethodChannel 테스트로 재현했다.

- [Apple handler](../ios/Runner/LedgerMobileHandler.swift#L522)와
  [Android handler](../android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt#L350)에서
  UFVK와 PCZT가 같은 단일 요청 소유권을 사용한다. 취소 결과는 한 번만 반환하고,
  늦은 응답과 후속 continuation APDU를 차단한다. 이전 요청이 끝나기 전 새 요청도 거절한다.
- [Dart BLE service](../lib/src/features/ledger/services/ledger_mobile_ble_service.dart)는
  cancel/disconnect 시 세대를 무효화해 예약된 재시도와 늦은 결과를 버린다.
- Apple SDK 1.0.1은 실제 승인 대기를 강제 중단하지 못한다. 이때 장치 선택 화면은
  무한 탐색 대신 “기기에서 이전 요청을 완료하거나 거절한 뒤 재시도” 안내를 표시한다.
  기기 응답이 끝난 뒤 disconnect와 새 UFVK 요청이 가능하다.
- 기존 Rust 취소→BLE 취소 순서는 유지했다. 추가로 시도한 병렬화는 이 순서를 보장하는
  기존 회귀 테스트가 실패해 제거했고, 원래 순서로 재검증했다.

| 후속 검증 | 결과 | 증거의 경계 |
| --- | --- | --- |
| Dart BLE·signer·voting·connection·readiness 5 files | 43 passed | 취소/끊기 후 재시도 중단, 늦은 결과 격리, 기존 서명 순서 |
| 모바일 Ledger connect widget | 18 passed | 복구 안내→재시도, 승인 대기 중 화면 이탈, 늦은 계정 결과 무시 |
| Apple 기존 XCTest + native 취소 회귀 | 19 passed | 실제 공용 handler + SDK protocol, macOS host의 제어된 transport; iOS 앱/물리 BLE 아님 |
| Android native 취소 회귀 | 4 passed | 실제 handler + DMK interface, JVM의 지연 응답; Flutter engine/물리 BLE 아님 |

Apple handler 타입 검사와 Android probe Kotlin 컴파일도 통과했다. 이 UFVK 수정 라운드에서는
전체 앱 빌드·실기기 설치·radio·Speculos/regtest·broadcast를 실행하지 않았다. Apple/Android에 남은 검증은 물리 BLE에서
“승인 대기→뒤로→재진입→이전 승인/거절→새 계정 추가”다. 잘못된 계정 저장이나 서명 우회가
재현됐다는 뜻은 아니며, 화면의 기존 `mounted` 보호도 유지한다.

## 제품 범위에서 결정할 것

### Wallet Link — 후속 구현 반영

초기 검토에서는 Ledger가 모바일 선택 대상에서 제외됐고, 지갑 식별값·그룹 이름·로컬 BLE 등록 계약이 없었다.
후속 승인으로 [내보내기](../lib/src/features/wallet_link/providers/wallet_link_provider.dart),
[transfer 모델](../lib/src/features/wallet_link/models/wallet_link_models.dart),
[가져오기](../lib/src/providers/account_provider.dart)를 수정했다.
Ledger의 wallet fingerprint·그룹 이름·birthday·index를 보존하며, 기기 없이 가져올 수 있다.

[모바일 연결 화면](../lib/src/features/onboarding/mobile/mobile_ledger_connect_screen.dart)은
기존 계정 연결 모드에서 저장된 wallet fingerprint와 UFVK를 모두 검증한다.
[공통 서명 화면](../lib/src/features/ledger/widgets/ledger_signing_modal.dart)의 재연결 버튼이
이 경로를 열며, 연결이 끝나도 별도의 `Try again` 전에는 서명하지 않는다.
데스크톱 BLE ID를 복사하지 않으며 서버 변경·배포도 필요하지 않다.
실제 QR 전송과 물리 BLE 서명을 결합한 검증 기록은 아직 없다.

후속 Wallet Link 검증은 다음과 같다. Rust·relay는 mock을 사용했으며 실제 서버나 Ledger에 접속하지 않았다.

| 검사 | 범위 | 결과 |
| --- | --- | --- |
| 이전 데이터·저장 | 실제 클라이언트 암호화→복호화, transfer model, AccountNotifier — 3 files | 32 passed, 모바일 전용 기존 테스트 1 skipped |
| 공통 연결·서명 | account service, connection service, recovery, signing modal — 4 files | 27 passed |
| 모바일 UI·회귀 | Ledger connect, Wallet Link 목록, send sign, swap/pay signing — 4 files | 46 passed |
| 정적 검사 | 이번 변경의 Dart 16 files | No issues found |
| 화면 확인 | `mobile-ledger-linked-connection`, light, 393×700 | widget capture 통과·렌더 이미지 확인 |

기능·회귀 테스트는 합계 105개 통과했다. 정상 지갑 연결, 다른 wallet fingerprint 차단,
같은 fingerprint의 UFVK 불일치 차단, 연결 취소, 연결 후 명시적 재시도만 서명하는 경로를 포함한다.
암호문 복호화 테스트에서는 wallet fingerprint·그룹 이름·복구 정보 보존과 데스크톱 BLE ID 미전송을 확인했다.
첫 모바일 회귀 명령의 잘못된 테스트 경로는 수정해 위 4개 파일 전체를 재실행했다.
전체 suite·native build·실기기 QR→BLE 서명은 실행하지 않았다. 서버 작업 트리는 변경되지 않았다.

### 기기에서 수신 주소 확인

[멀티 계정 문서](ledger-multi-account-import.md)는 이미 out of scope로 명시한다.
현재 Ledger API는 UFVK·no-display wallet identity·서명 경로이며 수신 주소 확인 API/진입점은 없다.
앱이 표시한 수신 주소를 Ledger 화면에서 대조할 수 없다는 신뢰 경계가 남는다.
이 기능을 지원 범위에 포함할지는 제품 결정이다. 추가 시 현재 receive-address rotation과
동일한 계정·index·receiver를 기기에서 확인하는 계약을 먼저 정해야 한다.

### 용량과 OS 제약

- upstream의 shielded display output 4개 제한은 [공식 계약](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/docs/PCZT_APDU.md)에 있지만
  [Vizor 선택기](../rust/src/wallet/sync/send/ledger_selection.rs)·serializer에는 별도 선행 계산이 없다.
  현재 송금 생성은 단일 payment이며, 이 검토에서 5개 display output을 만드는 제품 호출 경로는 확인하지 못했다.
  현행 정상 송금 blocker로 올리지 않고 다중 출력 확장 시의 조건으로 남긴다.
- [Android `minSdk = 30`](../android/app/build.gradle.kts#L73)은 Ledger 미사용자에게도 적용된다.
  “Android 10 이하에서 Ledger만 비활성화”되는 구조가 아니다. 지원 OS 안내와 릴리스 판단에 포함해야 한다.
- Apple Nano Gen5 BLE와 모바일 USB는 현재 미지원이다. Linux USB는 트랜잭션 사용자 확인을 받았고,
  Linux BLE도 Ubuntu Release/Stax 연결·트랜잭션 서명 사용자 확인을 받았다. Windows는 USB·BLE 모두 구현됐다.
  사용자가 지원 범위 확대를 원하기 전에는 미구현이라는 이유만으로 추가 작업을 자동 생성하지 않는다.

## 초기 문서 검토의 검증 기록

2026-09-09, 초기 기준 `0e66e86bc548b1d23a62e489fb50e6b4a766f258`에서 실행했다.
실제 결과는 아래에 기록하며 실행하지 않은 검사를 통과로 세지 않는다.

| 검사 | 범위 | 결과 |
| --- | --- | --- |
| Flutter 공통 계약 | capability, app readiness, connection, BLE APDU, signer, operation recovery, error messages, voting signer — 8 files | 56 passed |
| Flutter 모바일 UI | Ledger connect, send signing, account details, swap signing surface — 4 files | 37 passed |
| Flutter 인접 계약 | Wallet Link model, account import context, reconnect controller — 3 files | 17 passed |
| Rust Ledger unit tests | `cargo test --lib wallet::ledger:: --locked -- --test-threads=1` | 62 passed |
| Rust 용량 선택기 | `cargo test --lib wallet::sync::send::ledger_selection:: --locked -- --test-threads=1` | 8 passed |
| 전체 suite / native build / XCTest / Speculos / regtest / 실기기 | 이번 실행 범위 밖 | 미실행 |

Flutter 합계는 110개, Rust 합계는 70개다. 모바일 검사는 `--run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`로 실행했다.
native BLE probe의 opt-in 테스트는 이 숫자에 포함하지 않았다.
Rust 용량 선택기의 풀별 예산·padding·change·적격 note·예약/잠금 보존도 별도 필터로 실행했다.
문서의 로컬 파일 링크 57개와 줄 번호 범위, Markdown 원문 구조를 확인했다. 별도 Markdown renderer의 시각 검사는 하지 않았다.

## 문서 변경

- 통합 [지원 사양](ledger-support.md)을 추가해 OS·기기·기능·키·제한·복구 계약을 한 곳에서 찾을 수 있게 했다.
- 이 문서에서 현재 미지원과 실제 검증 공백을 분리했다.
- 멀티 계정 문서와 BLE probe 기록에 통합 사양 링크를 추가했다.
- probe 문서의 4초는 과거 실행값으로 보존하고, 현재 cooldown은 3초라는 안내를 덧붙였다.
- Windows USB·BLE 지원표, 최종 Release 확인, 사용자 보고의 경계와 다음 작업 순서를 최신화했다.
- 멀티 계정 문서의 Wallet Link fingerprint 이전과 일반 추가 경로의 중복 검사 시점을 바로잡았다.
- Linux USB/BLE 커밋과 Stax 실기기 확인, 최종 스테이징 스냅샷 검사를 반영했다.
- 전송 취소 후 잔액 갱신 누락을 BLE와 별도인 미해결 이슈로 기록했다.

UFVK·Wallet Link·Windows·Linux 후속 구현의 검증을 각각 보존한다.
Windows·Linux Stax에서 확인한 범위는 유지하고, 나머지 지원 OS·Ledger 조합은 별도 확인한다.
