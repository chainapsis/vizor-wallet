# QR 및 붙여넣기 입력 정책 구현 계획

작성일: 2026-09-14. 작업 브랜치: `rowan/qr-scan-flow`.
기준 커밋: `ddae41ccdda0539d15fd51876a8c9be9aaaa2bfe`.
최초 견적 이후 로컬 구현을 완료했다. 아래 정책은 후속 합의를 반영하며,
구현 및 검증 결과는 문서 하단에 기록한다.

## 목표와 완료 범위

기존 QR/붙여넣기 진입점에 동일한 용도·체인·네트워크 정책을 적용한다.
거부되거나 유효기간이 끝난 입력은 폼과 전역 결제 요청 상태를 변경하지 않는다.
모바일과 데스크탑 UI를 함께 다루며 OS 결제 URI 수신은 Zcash로 제한한다.
새 홈 스캐너, Pay 시작 화면의 새 버튼, Pay 단계 재설계는 별도 UI 논의 대상이다.
Swap/Pay 수신 주소 입력에서 연 요청 카드는 Keep editing(주소만)과
Review payment(요청 전체, exact-out)를 제공한다. 입력 화면과 연결되지 않은
글로벌 요청 카드의 기존 Edit은 요청 전체 적용을 유지한다.
구현 전달 단위는 로컬 변경과 검증 결과다. 커밋·푸시·PR 게시·실기기 재설치는
이번 계획 작성에 포함하지 않는다. Vizor main은 수정하지 않는다.

## 입력 정책

| 문맥 | 허용 입력 | 적용 방식 |
|---|---|---|
| Send | Zcash 일반 주소 및 zcash: 요청 | 주소는 폼에, 지원 결제 요청은 기존 요청 카드에 적용 |
| Pay | 지원 외부 체인의 일반 주소 및 크로스체인 결제 URI | 일반 주소는 선택한 체인 기준 검증, 요청은 자산·네트워크·조건 검증 후 카드 표시 |
| Swap ZEC → external | 선택한 외부 체인의 주소 및 지원 크로스체인 결제 요청 | 주소는 그대로 적용, 요청은 주소만 적용 또는 전체 결제 Review 선택 |
| Swap external → ZEC | 선택한 외부 체인의 환불 주소 | 환불 주소만 적용, ZEC 수신 주소는 지갑에서 결정 |
| Contacts | 일반 주소 및 단일 수신 주소를 안전하게 추출 가능한 URI | 네트워크 확인 후 주소만 적용, 자산·금액·메모는 적용하지 않음 |
| OS payment link | zcash: | 기존 Zcash 요청 카드 및 잠금 해제 대기 흐름 |
| Keystone / Link Mobile / Gift Card scanner | 각 기능의 전용 형식 | 기존 전용 디코더 및 제한 유지 |

- Swap/Pay는 주소 또는 URI에 테스트넷임이 드러나면 거부한다. 지갑을 테스트넷으로
  바꿨다고 외부 체인 결제를 테스트넷으로 허용하지 않는다.
- Send/Contacts의 Zcash는 현재 선택한 지갑 네트워크를 기준으로 검증한다.
  mainnet에서는 mainnet만, testnet에서는 testnet만 허용한다. 기존 regtest 검증
  환경도 해당 네트워크와 맞춰 유지하며, 문자열로 구별 불가능한 주소는 추측하지 않는다.
- Contacts의 외부 체인은 현재 모델에 별도 테스트넷 선택이 없으므로 지원 mainnet
  체인으로 해석한다. Zcash 지갑의 testnet 설정을 외부 체인에 적용하지 않는다.
- EVM/Solana 등 주소에 네트워크가 없는 경우 테스트넷 사용 이력을 탐지하지 않는다.
  URI에 명시된 chain ID는 검증하고, 일반 주소는 선택한 지원 네트워크에 적용한다.
- URI의 scheme/chain ID/네트워크는 주소 추출 전에 확인한다. 명시된 다른 체인을
  버리고 주소 모양이 같다는 이유로 현재 체인에 적용하지 않는다.
- Swap 수신 주소 입력과 Pay는 지원 결제 요청에 선택을 제공한다. Keep editing은
  요청 체인이 원래 선택 체인과 일치할 때 주소만 가져오며 자산·금액·입력 모드를
  유지한다. Review payment는 요청 전체를 exact-out Pay Review로 전달한다.
  금액이 없으면 Enter amount로 연결한다. 취소는 원래 초안을 유지한다.
- Swap 환불 주소는 계속 주소 전용이다. 금액·메모·label/message·토큰 전송 등
  조건이 있으면 거부한다. 수량 0이나 빈 파라미터도 결제 조건으로 분류하며,
  알 수 없는 필수 조건은 주소로 축소하지 않는다.
- Payment request 카드의 버튼 위 상태 영역에는 오류만 표시한다. Checking,
  Preparing, Syncing 진행 상태는 버튼 문구로 표시하고 네트워크 선택 안내는
  해당 선택 UI에서 처리한다.
- Contacts에서 ERC-20 URI의 target contract를 수신자로 저장하지 않는다.
  다중 수신자 또는 모호한 요청은 임의의 첫 주소로 저장하지 않는다.
- malformed/지원 불가 요청을 일반 주소로 재시도하지 않는다. 기존 Send의 ZIP-321
  주소 fallback은 금액·메모 손실 여부를 확인해 명시적으로 처리한다.
- 잘못된 종류, 다른 체인, 다른 네트워크, 잘못된 주소, 지원하지 않는 요청 조건을
  구분해 안내한다. QR 오류는 스캐너 안에 표시하고 재스캔을 허용한다.

## 현재 코드에서 확인한 변경 지점

- `features/send/screens/mobile/mobile_send_scan_screen.dart`: cross-chain scheme을
  Zcash 검증 전에 허용한다. 이 우회 경로를 제거해야 한다.
- `features/send/screens/mobile/mobile_send_screen.dart::_pasteAddress`: Clipboard를
  읽은 뒤 주소 필드를 먼저 덮어쓰고 요청을 처리한다. 검증 후 반영으로 변경한다.
- `features/address_scan/widgets/payment_request_input.dart`: 입력 요청을 공통 intake에
  보내지만 Send/Pay/Swap 문맥을 구분하지 않는다.
- `features/address_scan/widgets/mobile_address_scan_card.dart`와
  `mobile_address_scan_view.dart`: await 이후 mounted만 확인한다. 동일 위젯에서
  정책/계정/네트워크가 바뀌거나 닫기 애니메이션 중인 경우를 별도로 무효화해야 한다.
- `features/address_scan/widgets/address_qr_scan_modal.dart`: 데스크탑은 동기 주소
  정규화와 callback 중심이다. 공통 비동기 검증 결과를 적용할 수 있게 연결한다.
- `features/address_book/models/address_format_validator.dart`: Bitcoin mainnet 검증은
  있으나 Litecoin 등은 default로 통과한다. Zcash 기본 네트워크는 빌드 상수다.
- `features/pay/models/payment_request_resolution.dart`: explicit EVM chain ID 및
  지원 자산 판별을 재사용한다. chain-less EVM 요청의 네트워크 선택을 유지한다.
- `core/payments/cross_chain_payment_request.dart`: BTC/LTC 요청의 mainnet 제한과
  지원 불가 결제 조건을 재사용한다. 전역 parser에서 cross-chain 지원을 삭제하지 않는다.
- 네이티브 수신: iOS Info.plist/AppDelegate, Android Manifest/MainActivity,
  macOS Info.plist/MainFlutterWindow, Windows protocol registry/utils,
  Linux desktop entry/my_application, Dart incoming_link_dispatch.

## 구현 순서와 공수

공수는 개발자 1인의 구현·리뷰·검증 작업시간 추정이다. 모델 실행시간이나 고정
납기 보장이 아니다. 단계별 18–28시간, 작업일로 약 3–4일을 예상한다.

### 1. 입력 분류와 네트워크 검증 공통화 — 4–6시간

`features/address_scan/domain/`에 문맥을 받는 작은 resolver를 두고 기존 parser와
validator를 조합한다. 결과는 주소 / 결제 요청 / 거부 이유를 구분하며 resolver는
폼이나 provider를 변경하지 않는다. 원본 URI, 명시 체인 및 네트워크 정보를 보존한다.

지원 목록 전체의 주소 식별 능력을 표로 점검한다. BTC/LTC 및 현재 노출된
BCH/DOGE/DASH, Cardano, TON, NEAR 등은 공식 형식과 기존 라이브러리를 확인해
테스트넷 식별이 가능한 범위를 채운다. 네트워크 불명과 검증 미구현을 구분한다.
기존 base58check/bech32 구현을 재사용하고 일반 주소 검증 전체를 재작성하지 않는다.
새 Rust API 또는 의존성이 꼭 필요한 경우 비용을 재산정한다.

검증: 문맥 × 입력 종류 × 네트워크의 순수 테스트. 실제 checksum을 가진 주소
벡터, explicit test chain ID, chain-less EVM, ERC-20 수신자, 모호한 수신자 포함.

### 2. 기존 QR 화면 연결과 폼 보존 — 5–7시간

모바일/데스크탑 Send, Pay, Swap 양방향, Contacts 스캐너에 같은 정책을 연결한다.
검증 완료 전에는 주소 controller, 선택 자산, 금액, memo, contact, quote,
전역 payment intake를 변경하지 않는다. 거부 시 카메라 화면과 기존 폼을 유지한다.
Pay의 지원 요청은 기존 요청 카드로 보내되 카드 승인 전 기존 composer는 보존한다.

입력 세션 번호와 문맥 snapshot(계정, 지갑 네트워크, 자산/체인, Swap 방향,
화면 단계 및 사용자 편집 revision)을 비교해 오래된 성공/실패를 모두 버린다.
닫기 버튼/뒤로가기 시점에 먼저 무효화한다. dispose까지 기다리지 않는다.
최신 입력 한 번만 반영하고, 무효화 후 새 스캔이 가능한 상태로 복구한다.

검증: 지연된 resolver로 닫기, 닫고 다시 열기, 네트워크/계정/자산/방향 변경,
새 사용자 입력, 중복 프레임을 재현한다. 늦은 결과가 폼·오류·라우팅에 영향을
주지 않는지 확인한다. 거부 후 정상 QR을 다시 읽는 사용자 흐름도 포함한다.

### 3. 붙여넣기 및 수동 입력 경계 통일 — 3–5시간

전용 Paste 버튼과 기본 컨텍스트 메뉴/키보드 붙여넣기를 모두 조사·연결한다.
완성된 paste 후보는 QR과 동일한 resolver로 검증 후 반영한다. 단순히 onChanged
전체를 완성 주소 검증으로 막아 타이핑·IME·삭제를 깨뜨리지 않는다.
수동 입력 중 미완성 문자열은 편집 draft로 허용하되 Continue/저장/요청 적용 전
같은 정책을 적용한다. 입력 중인 draft와 실제 결제 state의 변경을 분리한다.
일반 입력 UI에 필요한 hook만 추가하고 앱 전체 텍스트 필드 구조를 바꾸지 않는다.

검증: QR/Paste 동일 입력의 동일 결과, 거부된 paste의 기존 값 보존,
Clipboard 응답 지연, 다른 입력으로 교체, 선택 영역 붙여넣기, 수동 타이핑,
빈 값/공백/삭제, 잘못된 URI 후 정상 입력으로 복구.

### 4. OS payment scheme 축소 — 2–4시간

다섯 플랫폼의 선언/수신 필터와 Dart 외부 링크 분류를 zcash:로 일치시킨다.
앱 내부 cross-chain parser와 Gift Card HTTPS 링크는 그대로 둔다.
Windows 기존 등록 처리와 테스트를 확인한다. 미배포 기능에 일반 마이그레이션
분기를 만들지 않는다. 이미 테스트 설치가 만든 association은 실제 소유권을
확인한 뒤 필요한 제거 경로만 다루고 다른 지갑의 기본 연결을 변경하지 않는다.

검증: native 계약 테스트, Dart incoming-link 테스트, zcash cold/warm/locked
진입과 cross-chain 거부, Gift Card 및 앱 내부 Pay 스캔 회귀.

### 5. 통합 확인과 리뷰 — 4–6시간

기존 테스트를 새 정책에 맞춰 갱신하고 의미 있는 실패/복구 회귀를 추가한다.
desktop/mobile test lane을 분리해 실행하고 변경 파일의 정적 분석을 수행한다.
그다음 필요한 native 빌드와 모바일 화면 검증을 수행한다. iOS 실기기 검증은
Release + VIZOR_FORM_FACTOR=mobile + devicectl 절차를 사용한다.
Keystone, Wallet Link, Gift Card 전용 QR이 일반 payment intake로 들어가지 않는지
확인한다. 실송금 없이 주소 입력, 거부 문구, 요청 카드/Review 직전 상태를 확인한다.
Windows/Linux 실제 OS 연결 검증이 불가능하면 portable 테스트와 구분해 보고한다.

## 완료 기준

1. Swap/Pay에서 식별 가능한 테스트넷 주소/요청은 QR과 paste 모두 차단된다.
2. Send/Contacts Zcash 검증은 실제 지갑 네트워크를 사용하며 반대 네트워크를 거부한다.
3. URI에서 주소를 추출해도 explicit chain/testnet 제한을 우회할 수 없다.
4. 잘못된 입력은 기존 폼과 전역 요청을 바꾸지 않고 해당 표면에서 이유를 표시한다.
5. 늦은 결과는 닫힌/변경된 화면을 수정하거나 다시 열지 않는다.
6. 일반 주소 QR, 주소 전용 URI, 지원 결제 URI 및 수동 입력은 허용 문맥에서 정상 동작한다.
7. OS cross-chain scheme은 제거되지만 Zcash 링크와 기존 Gift Card 링크는 동작한다.
8. 변경한 모바일/데스크탑 UI와 핵심 비동기 회귀 테스트가 통과한다.

## 검증 현황과 추정 오차

계획 전 단계에서 같은 커밋의 준비된 payment-pr-series 작업 폴더로 실행한
payment parser/resolution, address-format, mobile send-scan 테스트 130개가 통과했다.
이는 기존 동작의 기준점이며 새 정책 구현의 통과 증거는 아니다.
일부 검증은 Rust mock을 사용하므로 실제 parser/native 환경 검증을 대체하지 않는다.
가장 큰 추정 오차는 여러 텍스트 필드의 native paste hook, 기존에 검증하지 않던
주소군의 네트워크 판별, 플랫폼별 빌드/등록 확인이다. 여기서 신규 의존성이나
플랫폼 문제를 만나면 4–8시간이 추가될 수 있다.

## Implementation result

Implemented locally on `rowan/qr-scan-flow` in the isolated
`vizor-wallet-qr-scan-flow` worktree. No commit, remote update, or device
installation was performed in this implementation round.

- A pure context-aware resolver validates the original URI before extracting
  an address. Send accepts Zcash; Pay accepts external addresses and supported
  payment requests; Swap recipients accept supported payment requests with
  address-only or full-review choices, while refunds remain address-only; Contacts
  extract one valid recipient on their selected network.
- External network checks cover identifiable mainnet encodings, including
  Litecoin MWEB, CashAddr, TON friendly addresses and Cardano Shelley/Byron.
  Raw addresses without network information cannot identify a test network.
- QR, keyboard paste and selection-menu paste validate before updating the
  draft. Hooked address fields use the adaptive selection toolbar so its Paste
  action cannot bypass validation through the native iOS menu. Ordinary typing,
  selection, deletion and IME input remain editable.
- Input and route generations, current account/network/asset checks, and live
  clipboard context checks discard late success and failure results. Scanner
  rejection permits retry. Desktop Swap restores unsaved editor contents when
  its scanner or contact picker is cancelled.
- Pay passes its validated request to the common request card without parsing
  it again or replacing the composer before confirmation. Static fallback asset
  lists do not masquerade as a loaded payment-asset catalogue.
- OS payment scheme registration and receive filters use only `zcash` on all
  five platforms. Existing Gift Card HTTPS handling and dedicated Keystone,
  Wallet Link and Gift Card QR flows retain their own policies.

Initial policy implementation verification:

- Final focused desktop integration run: 538 tests passed, including resolver,
  network validators, scanner lifetime, native-paste hooks, incoming links,
  Send, Contacts, Swap, Pay and the existing cross-chain parser.
- Mobile integration run: 195 tests passed, including Send, Contacts, Swap,
  Pay, Keystone onboarding, Wallet Link and Gift Card scanners. After final
  Send/session and editor refinements, the affected mobile subset passed again
  (150 tests; overlaps the 195-test run).
- All 44 changed/new Dart source and test files passed static analysis.
- Windows protocol portable tests: six groups passed. iOS/macOS plist lint and
  `git diff --check` passed. Linux test script syntax was checked.
- iOS/Android native builds and native unit tests, device installation and OS
  camera behavior on physical devices were not run. Windows/Linux OS handler
  behavior was not tested on those operating systems.

## Payment request choice follow-up

- Swap recipient scans and validated URI paste offer `Keep editing` and
  `Review payment` (or `Enter amount` when the request has no amount).
  Keep editing fills only the recipient and preserves the original asset,
  amount and input mode. It is available only on the original selected chain.
  Full review uses the existing Pay exact-output flow. Cancel restores the draft.
- Pay recipient input uses the same address-only choice. Requests opened outside
  a local recipient editor retain the existing full-request Edit action.
- Local origins are ephemeral and cleared on lock/account changes. Stale local
  requests are discarded before replacing an existing visible request.
- Cross-chain and Zcash cards show only errors above their action buttons.
  Checking, preparation and syncing progress appear in the primary button.

Follow-up verification:

- Mobile request cards/hosts, Pay, Swap and Send integration: 204 tests passed.
- Desktop broad run: 362 passed with one outdated informational-copy assertion;
  after correcting that expectation, the affected host/origin/Zcash/widgetbook
  subset passed all 111 tests.
- Final origin and incoming-request regression subset: 50 tests passed, including
  the additional stale-origin protection. These subsets overlap earlier runs.
- Deterministic card captures verified mobile Keep editing without an amount,
  desktop checking, and Zcash syncing with progress confined to the button.
- No native build or physical-device installation was performed in this follow-up.
