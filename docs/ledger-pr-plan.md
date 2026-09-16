# Ledger 코어·UI PR 분리 계획

상태: C01 #695 병합 완료, C02 #696 리뷰 중. C03은 C02를 base로 먼저 draft를
준비한다. 선행 PR 리뷰 수정은 후속 draft에 리베이스로 반영한다.

## 1. 목표와 기준점

기존 Ledger 구현을 기능별로 리뷰하고, 승인된 변경을 코어와 UI 모음 PR에
누적한다. 새로 구현하는 프로젝트가 아니라 현재 동작을 유지하며 리뷰 단위를
재구성하는 작업이다.

- 기준 구현: `rowan/ledger-advanced`, `fbe51859972213eb0c70dc80bda67c7ef7f249e8`.
- 비교 기준: `origin/main`, `7339fa94a62339d89bcbbb3f14916d7be931a26a`.
- 작업 시작 시 fetch 성공과 기준/복구 SHA를 다시 기록한다. main이 이동했다면
  그 차이를 확인하고 새 작업 브랜치에서 반영한다. 로컬/원격 main은 변경하지 않는다.
- 원본 브랜치와 기존 리베이스 백업은 유지한다. 기존 커밋을 의미 단위로 그대로
  cherry-pick할 수 있다고 가정하지 않고, 최종 코드의 파일·hunk를 옮긴다.
- 현재 구현 계약은 [기준 구현의 ledger-support.md](https://github.com/chainapsis/vizor-wallet/blob/fbe51859972213eb0c70dc80bda67c7ef7f249e8/docs/ledger-support.md)를 따른다.
  `ledger-support-review.md`는 이전 검증 기록이며 현재 설계의 정본으로 사용하지 않는다.
- 2026-09-16 fetch/조회 시 열린 Ledger PR은 없었고 main과 기준 구현 SHA는 위와 같았다.
  기존 `rowan/ledger-core`는 `c2d71817b08025c62650367fa125ac676f32b109`의 예전 구현이므로
  보존하고, 이번 모음은 `-collection` 이름을 사용한다.

## 2. 완료 조건과 범위

### 완료 조건

1. 코어와 UI 모음 draft PR이 각각 존재하며 포함 범위·하위 PR·검증 현황을 보여준다.
2. 각 하위 PR은 자신의 base에서 빌드/분석 가능하고, 해당 기능의 성공·실패·취소를
   검증한다. 완성본 테스트 결과를 분리된 PR의 검증 결과로 대신하지 않는다.
3. 코어에는 실제 동작을 결정하는 로직이, UI에는 표시와 사용자 입력 연결이 남는다.
4. 최종 통합 결과를 기준 구현과 비교해 빠진 변경을 모두 설명한다. 새 main 변경,
   최소한의 책임 분리, 리뷰 수정 외의 동작 변화는 별도 합의 없이 넣지 않는다.
5. software/Keystone 기존 경로의 회귀 검증을 통과한다. 실기기 미확인 항목은 명시한다.

### 코어 / UI 경계

| 코어 | UI |
| --- | --- |
| 계정 index 검증·전달, UFVK/metadata 저장 | Advanced 입력, 경로 표시, 이름·birthday 화면 |
| 연결·권한·pairing 상태, 오류 분류, 재시도 정책 | 기기 목록, pairing 확인 창, 오류 문구와 설정 버튼 |
| 서명·checkpoint·broadcast·취소·복구 상태 전이 | 서명 모달, 진행 표시, 버튼 배치, 화면 전환 표현 |
| 지원 모델·네트워크·거래 한도 판단 | 미지원 안내와 Max/Shield 도움말 |
| voting bundle 및 swap/pay 주문 상태 연결 | 투표·입금 상태 화면 |

기존 Widget 내부의 실행 로직은 필요한 부분만 service/notifier로 옮기고
화면에는 호출·상태 구독만 남긴다. 새 범용 framework나 대규모 폴더 재편은 하지 않는다.
앱 시작/잠금 해제 시 복구를 호출하는 최소 수명주기 연결은 코어에 포함하고,
toast·modal 표현은 UI에 둔다. UI가 없어도 필요한 코어 경로는 자동 테스트에서 실행 가능해야 한다.

이번 범위 밖: 계정 그룹핑/지갑 fingerprint 재도입, 모바일 USB, 기기에서 수신 주소 확인,
Orchard→Ironwood 지원 가드 해제, 새로운 OS/기기 지원, 의존 SDK의 별도 업그레이드.
기존 migration 가드와 막힌 경로에 남은 signer 코드는 별개다. 현재 desktop/mobile 진입점은
`ledgerAutomaticOrchardMigrationCapability`로 차단된다. 남아 있는 immediate migration의
prepare/sign/proof/complete/discard 계약은 C08 공통 signer와 C09의 차단된 실행 코드로
귀속해 기존 상태를 보존한다. 이관이 지원 활성화나 가드 해제를 뜻하지 않는다.

## 3. 브랜치와 리뷰 운영

| 용도 | head → base | 운영 |
| --- | --- | --- |
| 코어 모음 | `rowan/ledger-core-collection` → `main` | draft 유지, 기능 PR 상태표 누적 |
| UI 모음 | `rowan/ledger-ui-collection` → `rowan/ledger-core-collection` | draft 유지, 코어 이후의 UI diff만 표시 |
| 개별 코어 기능 | `rowan/ledger-core-<topic>` → `rowan/ledger-core-collection` | 준비되면 리뷰 요청 |
| 예외적으로 병렬 리뷰를 승인한 경우 | 후속 기능 브랜치 → 필요한 선행 브랜치 | 승인 후에만 사용, base와 선행 PR 명시 |

- 먼저 core 브랜치에 이 범위/계획 문서를, ui 브랜치에 UI 범위 문서를 넣어
  검토 가능한 문서 diff로 모음 draft 두 개를 연다. 빈 커밋이나 임시 기능을 넣지 않는다.
- Assignee는 사용자 계정. PR 제목에 `[codex]`, `[desktop]`, `[mobile]`를 붙이지 않는다.
- 리뷰 요청·리뷰 반영·모음 브랜치 병합의 경계를 구분한다. 생성/푸시와 리뷰 후 병합은
  각각 합의된 실행 범위에 따라 수행하며, 이 계획은 main 병합을 승인하지 않는다.
- 선행 PR을 모음에 합친 후 후속 PR의 base를 모음으로 바꾸고 누적 diff가 제거됐는지 확인한다.
  squash로 SHA가 달라졌다면 단순 base 변경에 그치지 않고 후속 고유 커밋만 재배치한다.
- rebase/force-push 전에 fetch, 원격 SHA와 복구 ref를 기록하고 명시적 lease를 사용한다.
  리뷰 중인 PR을 일괄 재작성하지 않는다.
- 후속 기능은 선행 PR 위에 **stacked draft**로 먼저 준비할 수 있다. 현재 승인된
  후속 draft는 C03이며 base는 C02다. 선행 PR 수정과 병합 후 후속 고유 변경만
  리베이스하고 base를 모음 브랜치로 바꾼다. 리뷰·모음 병합 순서는 의존성을 따른다.
- 독립 영역이라 병렬 리뷰가 가능하면 대상 PR·겹치는 파일·의존 관계·검증 범위를
  먼저 사용자에게 제안한다. 사용자가 확인하고 승인하기 전에는 추가 기능 PR을 열지 않는다.
- 서브에이전트의 읽기 전용 분류/검토는 기능 PR의 병렬 개설과 별개다.
  공유 파일 수정과 codegen은 같은 작업 디렉터리에서 동시에 수행하지 않는다.

## 4. 실제 분리에서 먼저 관리할 결합 지점

| 현재 파일 | 결합 | 분리 원칙 |
| --- | --- | --- |
| `rust/src/wallet/ledger/{mod,transport,apdu,serializer}.rs` | UFVK·USB·서명·작업 잠금·serializer helper가 연결됨 | 01에 장치 통신과 UFVK용 공통 helper만 포함. 전체 signer는 08에서 추가 |
| `rust/src/api/ledger.rs`, `lib/src/rust/*`, `rust/src/frb_generated.rs` | 모든 기능의 bridge 표면 공유 | 기능에 필요한 API만 단계적으로 추가하고 매번 재생성 |
| `keys.rs`, `account_models.dart`, `account_provider.dart` | signer 종류·연결 metadata·서명 복구 데이터 삭제가 섞임 | 계정 계약은 02, signed operation 정리는 10에서 추가 |
| `ledger_account_service.dart`, `ledger_connection_service.dart` | 계정 가져오기와 USB/BLE connector가 혼재 | 02는 UFVK/import/duplicate/metadata, 03은 connector·transport 선택·연결 기록. 02가 03의 BLE 계약을 당겨오지 않도록 분리 |
| `ledger_signing_service.dart` | 취소·mobile operation gate와 signer가 혼재 | 취소/gate 기반 계약은 03, 실제 PCZT signer와 서명 후 cooldown은 08 |
| `ledger_operation_recovery.dart` | 복구 coordinator·앱 수명주기·toast·swap 결과 처리 혼재 | 10에서 저장/복구 계약과 coordinator, 13에서 주문 adapter, UI에서 알림 표현 |
| send/shield/swap Widget | 실행 순서와 화면 상태가 혼재 | 11~13에서 실행 로직과 결과 계약을 분리, UI PR에서 화면 연결 |
| voting providers | 최신 main의 SDK 세션 흐름과 Ledger 분기 혼재 | 현 SDK 흐름에 Ledger 부분만 이관. 이전 resume/proof 파이프라인 복원 금지 |

실행 준비 단계에서 `base..source` 전체 파일/hunk에 `코어 PR ID / UI / 제외 사유`를
매핑한다. 빌드 설정·manifest·lockfile·권한·문서·테스트·예제·probe 스크립트도 빠뜨리지 않는다.
모듈을 미리 선언해 놓고 미구현 stub으로 빌드만 통과시키는 방식은 사용하지 않는다.
화면 route 등록은 UI가 소유하며 코어는 data/action 계약만 제공한다. 문서와 Speculos
통합 테스트도 전체 파일을 선행 PR에 넣지 않고 관련 절/시나리오와 fixture로 분리한다.

## 5. 코어 PR 목록

합의한 10개 기능 묶음 중 연결을 공통/계정 연계 정책과 OS별 adapter로 세분화해
총 15개 리뷰 단위로 시작한다. 번호는 식별자이며 모든 PR 사이에 기술적 의존이 있다는 뜻은 아니다.
운영은 별도 승인 전까지 01부터 하나씩 리뷰·병합하는 순서를 기본으로 한다.
아래 파일명은 현재 위치를 기준으로 한 이관 범위다.

### 01 — Add Ledger USB transport and device protocol

- **입력/출력:** 기존 main → 장치 앱/version 확인, 앱 열기, UFVK 요청/응답, 취소 가능한 USB 교환.
- **범위:** `ledger/{mod,transport,apdu}.rs`의 관련 부분, derivation helper,
  `api/ledger.rs`, Cargo/HID 빌드 의존성, Linux udev 규칙과 설치 설명.
- **제약:** mainnet, 장치 하나 사용, 응답 크기 제한, 물리 exchange의 취소 한계.
  signed-operation DB와 full PCZT signer는 포함하지 않는다.
- **완료:** 잘린/초과/오류 응답, timeout·취소·새 세션 재시도를 검증.
  USB 지원 OS의 빌드/권한 확인을 분리 기록한다.

### 02 — Import Ledger accounts with account-scoped metadata

- **의존:** 01의 UFVK export/decoder.
- **범위:** `keys.rs`, `account_models.dart`, `account_provider.dart`, bootstrap,
  `ledger_account_service.dart`의 가져오기·중복 검사. transport 선택 연결은 03.
- **동작:** 첫 Ledger 계정과 추가 index 가져오기, UFVK 중복 방지, signer 종류와
  index·birthday·연결 metadata 보존. seed/spending key는 가져오지 않는다.
- **제약:** 합성 `seedFingerprint`를 실제 seed fingerprint나 기기 식별로 취급하지 않는다.
  다른 seed의 같은 index는 허용. imported-only DB의 기존 migration 제약을 명시한다.
- **완료:** 중복/다른 계정/잘못된 index, 재시작, rename, software/Keystone metadata 보존 검증.

### 03 — Coordinate Ledger connections and cancellation

- **의존:** 01·02. OS adapter 없이도 fake transport로 검증 가능한 공통 계약을 제공.
- **범위:** capability, readiness, connection/recovery, mobile BLE service,
  pairing event/provider 계약과 typed failure. 앱 문구/버튼은 UI.
- **동작:** 마지막 transport 우선 연결, 시작 전 오류에서만 fallback,
  권한 재확인, readiness, 취소·late response 배제, 제한된 APDU 재시도.
- **완료:** 작업 시작 뒤 fallback 없음, reconnect만으로 서명 안 함,
  취소 뒤 continuation/retry 없음, 일반 disconnect와 invalid pairing 구분 검증.

### 04 — Add Ledger Bluetooth transport on Apple platforms

- **의존:** 03. 범위: `ios/Runner/LedgerMobileHandler.swift`, macOS 공유 연결,
  native 등록·권한·entitlement·Swift package 설정 및 native tests.
- **동작/제약:** iOS/macOS 검색·pairing·앱 전환 후 재연결. SDK가 중단할 수 없는
  exchange는 결과를 한 번만 완료하고 실제 callback까지 native slot을 유지.
- **완료:** 취소/late callback/removed pairing/reconnect 검사, 양 플랫폼 빌드.
  장치가 요청을 끝내기 전 즉시 취소가 된다고 표시하지 않는다.

### 05 — Add Ledger Bluetooth transport on Android

- **의존:** 03. 범위: `LedgerMobileHandler.kt`, MainActivity, Gradle/manifest, tests.
- **동작/제약:** DMK 연결·APDU 교환, scan/connect 권한, GATT teardown 확인 후 재사용.
  API 30 하한이 전체 앱에 적용되는 점을 본문에 명시.
- **완료:** 취소·disconnect·재연결 직렬화, nullable 기기 이름 오류,
  권한 거절·철회 검증 및 Android 빌드. 모바일 USB는 추가하지 않는다.

### 06 — Add Ledger Bluetooth transport on Windows

- **의존:** 03. 범위: `native/ledger/*`, Windows handler·등록·빌드 설정·protocol tests.
- **동작/제약:** 공용 UUID/framing/MTU/operation gate, WinRT GATT와 authenticated pairing.
- **완료:** framing 경계, MTU, generation·취소·notification 정리 검증과 Windows 빌드.
  VM/동글 결과를 Windows 전체 adapter 지원 증거로 확대하지 않는다.

### 07 — Add Ledger Bluetooth transport on Linux

- **의존:** 03·06의 공용 native protocol. Windows adapter 자체에는 의존하지 않는다.
  먼저 분리해야 할 필요가 생기면 06의 공용 헤더 부분만 선행한다.
- **범위:** BlueZ transport/handler, GIO·CMake, fake BlueZ tests.
- **동작/제약:** 명시적 pairing 코드 확인, 대상/service 제한, GATT write 및 notification,
  취소 worker와 물리 disconnect 완료 확인. 기존 bond를 삭제하지 않는다.
- **완료:** 거절·timeout·powered-off·취소 중 검색·재연결·write type을 fake BlueZ로 확인,
  Linux 빌드. 실제 pairing 시간 창과 장치 테스트 결과를 별도 기재.

### 08 — Validate and sign Ledger PCZTs

- **의존:** 01·02·03. BLE 실기기 통합 검증은 해당 OS adapter 후에 추가.
- **범위:** Rust PCZT parser/serializer/finalizer, `api/ledger.rs`, signing service,
  서명 검증에 필요한 공통 `sync/pczt.rs` 변경.
- **동작:** full/compact signer, transparent 및 shielded 서명, account/path metadata 확인,
  응답/서명 검증, 승인·거절 후 다음 명령까지 cooldown.
- **제약:** `0x9000`만으로 성공 처리 금지. 다른 seed의 기기는 승인 후 서명 검증에서
  거절될 수도 있음. raw signer와 제품 지원 가드를 구별.
- **완료:** 다른 계정/변조/누락·중복·잘못된 서명/지원하지 않는 형태와 연속 요청 검증.
  compact voting용 서명 계약도 여기서 제공하되 voting SDK 상태는 14에 둔다.

### 09 — Apply Ledger limits to transaction planning

- **의존:** 02·08의 signer 한도/지원 계약.
- **범위:** `sync/send.rs`, `send/ledger_selection.rs`, API quote/Max 결과,
  migration 진입 제한과 해당 tests, 현재 차단된 immediate migration request 수명주기 보존.
  Max 도움말·버튼과 migration overlay 표현은 UI.
- **동작:** note/UTXO 선택과 fee·Max·proposal이 같은 기기 예산을 사용.
- **제약:** transparent 입력 32/출력 10, pool별 shielded action 32,
  padding/change 포함. Sapling 및 현재 Orchard→Ironwood 미지원 조합 차단.
  device review 출력 예산의 host 사전검사 공백은 별도 명시하고 새로 해결하지 않는다.
- **완료:** 경계값, 예약/잠긴 note 제외, pool별 예산, fee 일치,
  software/Keystone selector 회귀 테스트 통과. 차단된 migration의 prepare/proof/complete/discard
  검증은 signed-operation checkpoint DB(C10)와 구별하며 제품 진입 가드는 유지한다.

### 10 — Persist and recover signed Ledger operations

- **의존:** 02·08의 계정/검증된 PCZT 계약.
- **범위:** `ledger/operations.rs`, bridge, signed-operation service/recovery coordinator,
  startup/unlock 연결, 계정 삭제·reset 정리. 주문별 adapter는 13.
- **동작:** signed PCZT checkpoint → broadcast → 결과 확인/ack, 재시작 후 이어서 처리.
- **제약:** 정확히 같은 데이터만 idempotent. broadcast 실패와 broadcast 후 저장 실패를
  구별. 저장 재시도는 기기 재서명과 분리. 만료·중복 동시 실행·잠금 상태를 처리.
- **완료:** 단계별 실패/재시작, 중복 ID, 다른 account/network, 만료,
  삭제·reset과 진행 중 작업의 경합을 검증. 실제 네트워크 테스트 여부는 별도 기록.

### 11 — Execute Ledger sends and TEX transfers

- **의존:** 08·09·10.
- **범위:** `send_flow.dart`, desktop/mobile send/review/status의 실행 로직과 handoff 계약.
- **동작:** proposal → proof/sign → checkpoint → broadcast, TEX 2개 PCZT의 순서 보존.
- **제약:** 취소 시 proposal 해제와 balance refresh 완료를 기다림.
  두 번째 TEX 서명 거절/재시도, checkpoint 중 back/중복 탭의 동작을 명시.
- **완료:** 정상/취소/해제 실패/retry, 기존 서명 재사용, 단계 중 화면 이탈 검증.
  기존 software/Keystone 송금 테스트도 실행. 화면 표현은 UI PR에서 연결.

### 12 — Shield Ledger funds in bounded rounds

- **의존:** 08·09·10.
- **범위:** shield overlay/mobile screen의 실행 부분, 남은 입력/round 계산 provider.
- **동작:** 승인당 최대 32개 입력, broadcast 후 잔여 확인과 다음 승인.
- **제약:** 남은 입력을 모르면 중단, 진전이 없으면 동일 입력으로 다음 서명 금지.
- **완료:** 32/33개 이상 경계, 중간 취소/실패, 잔여 조회 오류·진전 없음 검사.
  round badge·안내 카드·paused 화면은 UI.

### 13 — Sign and recover Ledger swap and pay deposits

- **의존:** 08·09·10. 일반 송금 화면 자체에 의존하지 않음.
- **범위:** swap/pay signing 실행부, hardware deposit draft/state,
  recovery의 주문 결과 adapter와 broadcast gate.
- **동작:** ZEC 입금 서명·checkpoint·주문 연결, 앱 재시작 후 결과 복원.
- **제약:** 다른 체인 서명 없음. 승인 후 취소 경계와 주문 기한을 유지하고
  만료된 입금을 재전송하지 않음.
- **완료:** 중복 시작, 승인 후 이탈, 기한 초과, queued broadcast, 결과 ack 재시도,
  Keystone 입금 및 일반 swap 경로 회귀 검증.

### 14 — Delegate voting bundles with Ledger signatures

- **의존:** 02·03·08. 일반 송금의 signed-operation DB가 아닌 voting SDK 저장 계약 사용.
- **범위:** voting service/session/state/submission-job의 Ledger 분기.
- **동작:** bundle별 compact 서명 검증·저장, 해당 세션의 delegation 진행/재개.
- **제약:** 요구된 pool/action과 정확히 일치, account/signer 전환 검사.
  host 표시 memo를 기기의 투표 내용 clear-signing 보장으로 설명하지 않음.
- **완료:** 다른 bundle/account, 여러 bundle, 재연결·취소·재개,
  software/Keystone voting 회귀 검증. 현재 main의 voting SDK 흐름 유지.

### 15 — Transfer Ledger accounts through Wallet Link

- **의존:** 02·03. 첫 모바일 서명까지 통합 검증하려면 04 또는 05와 08 필요.
- **범위:** Wallet Link transfer model/export/import, 기기 UFVK 대조 후 enrollment 로직.
- **동작:** UFVK/index/birthday/name/model 전송, 장치 없이 import/sync,
  처음 서명할 때 일치하는 BLE 기기 등록.
- **제약:** desktop device ID/transport 설정 미전송, connect만으로 sign/broadcast 안 함.
  양쪽 클라이언트 계약을 함께 명시. 미출시 Ledger metadata의 별도 legacy migration 없음.
- **완료:** round trip, metadata 누락/오류, 같은 index의 다른 seed 거절,
  일치 후 등록, 연결 취소 시 서명 없음, 기존 software/Keystone 전송 회귀 검증.

## 6. 실행 순서와 검증 경계

1. **준비:** 기준 SHA/fetch 확인, 전체 변경 귀속표, 공유 helper/API 의존성 정리,
   모음 브랜치와 문서 draft 생성. 이후 기능별 PR 목록을 모음 본문에 링크한다.
2. **기반:** 01 → 02 → 03. 이 경계에서 계정 가져오기·연결·취소 계약을 고정한다.
3. **OS와 signer:** 04 → 05 → 06 → 07 → 08을 기본 리뷰 순서로 둔다.
   04/05/06/08의 기술적 독립성은 병렬 리뷰 제안 근거일 뿐 자동 개설 권한이 아니다.
   API/codegen 변경은 합치는 순서대로 재생성한다.
4. **거래와 저장:** 09 → 10 → 11 → 12 → 13 → 14 → 15를 하나씩 리뷰·병합한다.
   앞당기거나 병렬 리뷰할 후보는 의존성 근거와 함께 사용자에게 먼저 제안한다.
5. **UI 연결:** 해당 코어 계약이 안정된 기능부터 연결. 코어를 향한 UI draft에는
   새로운 실행 정책을 숨겨 넣지 않는다. 전체 OS adapter 완료가 USB 기반 리뷰의 선행 조건은 아니다.
6. **통합:** 코어+UI 결과와 기준 구현의 diff 귀속을 재확인하고 최종 회귀/실기기 표를 작성.
   모음 PR의 ready 전환과 main 병합은 이 계획의 자동 실행 항목이 아니다.

### 검증 방식

- 각 PR의 정확한 head/base에서 관련 기존 테스트를 먼저 이관·실행한다.
  새 테스트는 분리 경계와 검증 공백에만 추가한다.
- Rust 변경: 관련 `cargo test --lib <filter> --locked`, 해당 platform build/check.
  Dart 변경: `fvm flutter analyze`, 해당 provider/service/widget 테스트.
- Rust API 변경 시 프로젝트 루트에서 `scripts/generate-rust-bridge.sh` 실행
  (내부에서 `flutter_rust_bridge_codegen generate` 호출). 생성물을 기능 PR에 포함한다.
  생성 파일을 손으로 합치거나 마지막 PR에 한꺼번에 몰지 않는다.
- 모바일 UI/통합 테스트는 `--tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
  데스크탑과 모바일 lane을 구분한다.
- native transport는 각 OS의 native tests와 빌드 결과를 별도 기록한다.
  다른 OS의 fake transport 통과만으로 실기기 검증 완료라 하지 않는다.
- UI PR에서는 결정적인 fixture/widget capture로 표시를 확인한다. native 권한·pairing·
  실제 서명은 그 표면에서 확인하며 필요한 실기기 결과를 별도 적는다.
- 물리 기기 표: OS/모델/transport/앱 버전/Vizor SHA, UFVK 가져오기, 취소·재연결,
  일반 송금, TEX, shield, swap/pay, voting. 자동 테스트·기존 기록·이번 확인을 구별한다.
  실제 자금 송금은 기존 승인 범위를 확인하고 계정·금액·수신처가 정해진 경우에만 실행한다.
- 최종 통합에서는 전체 desktop/mobile lane 및 Rust suite를 실행하고 환경 차단·skip·
  실기기 미확인을 남긴다. 단순 분리만으로 모든 플랫폼의 release 검증이 완료되지는 않는다.

## 7. PR description 공통 형식

PR 제목과 본문은 영어로 작성한다. 제목은 각 절의 제안을 출발점으로 사용한다.
모음 본문은 목적/범위, 하위 PR 진행표, 검증 공백, 최종 통합 조건을 담는다.
하위 PR은 아래 형식을 따르되 단순 변경에는 불필요한 절을 줄인다.

```markdown
## Behavior
Concrete trigger, previous behavior, and resulting behavior.

## Changes
APIs, stored data, state transitions, and the consumer of each change.

## Failure and cancellation
What stops, what is retained, and where a retry resumes.

## Constraints
Supported inputs/platforms, explicit exclusions, and known limits.

## Dependencies
Parent collection PR, prerequisite PRs, and the review base.

## Validation
Automated checks on this head; physical-device evidence with versions;
skipped, blocked, or unverified cases.
```

## 8. 중단·재판단 조건

- 한 PR을 빌드하기 위해 후속 기능 대부분을 넣어야 한다면 최소 공통 helper를 먼저 분리하거나
  경계를 조정한다. 파일 수 목표 때문에 의미 없는 stub/호환 분기를 추가하지 않는다.
- 분리 중 실제 결함을 찾으면 재현 근거와 수정 영향을 기록한다. 현재 동작 보존과 충돌하거나
  새 제품 결정을 요구하는 수정은 분리 작업에 조용히 섞지 않는다.
- main 이동으로 voting/송금/계정 계약이 바뀌면 영향받는 PR만 재조정하고 검증한다.
- 리뷰 피드백으로 공통 계약이 바뀌면 소비 PR과 생성물을 갱신한 뒤 해당 경계만 다시 검증한다.
- OS 빌드 환경이나 Ledger 기기가 없으면 해당 항목을 미확인으로 남기고 독립 작업을 계속한다.
  출시 준비 완료로 표시하지 않는다.

## 9. 실행 체크리스트

- [x] 완성본 미커밋 작업 커밋·푸시: `fbe518599`.
- [x] 코어 범위, UI 경계, PR 순서·완료 기준 정의.
- [x] 실행 시작 시 fetch·기준 SHA 확인 및 전체 변경 귀속표 작성: [inventory](ledger-change-inventory.md).
- [ ] core/UI 문서 seed와 모음 draft 두 개 생성. GitHub 생성 후 각 모음 PR 본문에서 상태와 링크 관리.
- [ ] 01부터 기능별 이관·검증·리뷰 진행.
- [ ] 최종 동작 대조와 검증 표 완성.

준비 이후 진행: C01 #695는 코어 모음에 병합됐고, C02 #696은 리뷰 중이다.
C03은 C02 위의 draft로 준비하며 main 병합은 승인 범위가 아니다.
