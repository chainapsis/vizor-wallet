# Vizor 계약 문서 그래프 설계안

2026-09-12 · 조사·계획 단계 · `rowan/agent-contract-docs`

**상위 탐색은 피라미드, 실제 계약 참조는 조건이 붙은 그래프로 재구성한다.**
도메인 문서 안에 공통 규칙을 끼워 넣는 대신, 그 규칙을 독립 문서의 정본으로
옮긴다. 에이전트는 작업과 관계없는 형제 도메인이나 주변 절을 읽지 않고 필요한
계약으로 직접 갈 수 있어야 한다. 파일 수와 깊이는 이 목적에 맞춰 늘린다.

이 문서는 분화 후보와 실행 순서를 제안한다. 현재 계약·루트 AGENTS·코드는
변경하지 않았다. Vizor 로컬·원격 main 변경, 커밋·푸시, 모델 비교 실행은 범위 밖이다.

## 현재 구조에서 확인한 문제

현재 계약은 16개, 합계 **93,177 UTF-8 bytes**다. Send만 분리한 상태이며 다른
문서는 여전히 여러 읽기 목적을 함께 가진다. 다음은 현재 파일과 그 안의 관련
절 본문 크기다. 새 파일의 예상 크기나 토큰 절감률이 아니다.

| 질문 | 현재 파일 | 관련 절 본문 |
| --- | ---: | ---: |
| Linux/Apple 저장소 차이는? | `security-lifecycle.md` 6,240 bytes | Platform storage boundaries 1,451 bytes |
| 앱 링크 host 설정은? | `payment-links.md` 7,414 bytes | Deep-link origin 997 bytes |
| UI 문구의 대소문자 규칙은? | `ui-platform.md` 8,762 bytes | Copy 585 bytes |
| Figma 비교 절차는? | 같은 파일 8,762 bytes | Figma comparison 1,765 bytes |
| Pay 재시도에서 무엇을 복원하나? | `swap-pay.md` 5,301 bytes | Pay-specific state 602 bytes |

실제 에이전트가 매번 파일 전체를 읽는다는 뜻은 아니다. 현재도 부분 읽기가
가능하다. 다만 제목 검색·구간 선택 없이 정본 파일 하나만 읽는 경로가 부족하다.
분리 후에는 파일 본문뿐 아니라 라우팅, 의존 문서, 반복 읽기 비용도 함께 봐야 한다.

특히 다음 결합이 남아 있다.

- `lock-sync.md`: 잠금/해제 전이, destructive mutation 정지 순서, 계정별 잔액,
  proposal 해제 후 refresh, 네트워크 전환.
- `payment-requests.md`: ZIP-321 문법, 들어오는 요청의 TTL/카드, Receive 요청 생성.
- `swap-pay.md`: Swap/Pay 제품 상태와 공통 NEAR Intents quote·deposit·recovery.
- `ui-platform.md`: 토큰, OS 색인, 창, inset, copy, Figma 비교.
- `hardware-signing.md`: 프로토콜 선택, QR 상관관계, proof/finalization, scanner 수명.

## 권장 계층과 소유권

```text
AGENTS.md                         프로젝트 핵심 규칙 + 세 진입점
docs/contracts/
  domains/index.md                사용자 작업 → 도메인/세부 계약
    accounts/index.md
    accounts/delete.md
    wallet/reset.md
    send/index.md
    donation/review-status.md
    receive/request-draft.md
    swap/index.md
    pay/index.md
    gift-cards/index.md
    voting/index.md
    migration/index.md
    ...
  references/index.md             공통 책임/심볼 → 해당 계약
    transactions/proposal-release.md
    signing/desktop-review-recovery.md
    signing/pczt-finalization.md
    storage/secret-sessions.md
    wallet/mutation-barrier.md
    sync/account-balances.md
    network/route-policy.md
    navigation/deep-link-origin.md
    ui/copy.md
    ...
  platforms/index.md              OS/환경 질문 → 정본으로 직접 안내
    apple/keychain.md
    linux/keyring.md
    ios/background-transport.md
```

트리는 배치 예시이며 아래 이동표가 분화 범위다. 새 경로는 아직 생성되지 않았다.

- **도메인:** Accounts, Wallet lifecycle, Security flows, Send, Donation,
  Shielding, Receive, Payment requests, Swap, Pay, Gift Cards, Wallet Link,
  Voting, Migration을 구별한다. Settings/Home처럼 여러 기능을 보여 주는 화면이
  그 기능들의 계약까지 소유하게 만들지 않는다.
- **공통 참조:** 실제 같은 의미·helper·프로토콜을 공유하는 규칙을 소유한다.
  이름이 비슷하다는 이유로 서로 다른 취소·금액·재시도 정책을 합치지 않는다.
- **OS 계약:** 여러 도메인이 쓰는 Keychain/keyring/transport 구현 차이를 소유한다.
  iOS migration의 상태 전이처럼 특정 도메인만의 규칙은 그 도메인에 둔다.
  OS 색인은 그 문서로 연결하며 내용을 복제하지 않는다.
- **도메인 내부 참조:** migration preparation처럼 한 도메인에서만 쓰는 공통부는
  `domains/migration/reference/`에 둔다. 전역 `references/`로 올릴 이유가 없다.
- **기존 가이드:** 설치·검증 명령은 CONTRIBUTING/E2E 가이드가 소유한다. OS 색인이
  가이드나 특정 계약으로 연결하며 모든 빌드 설정을 다시 설명하지 않는다.

## 노드와 링크의 규칙

### 상위 색인

색인은 담당 범위, 작업/심볼, 도착 문서, 따라갈 조건만 담는다. 아래 계약 내용을
요약해서 다시 싣지 않는다. 계약이 이미 알려진 작업은 색인을 건너뛰고 바로 읽는다.
모든 폴더에 색인을 강제로 만들지 않는다. 하위 작업이 여러 개인 곳에만 둔다.

루트 AGENTS는 도메인 목록 전체를 계속 늘리는 대신 도메인·공통 참조·OS/환경
색인으로 안내한다. 기존 task-specific 가이드와 핵심 프로젝트 규칙은 유지한다.
문서 탐색에 고정 순서나 무조건적인 파일명 우선 검색을 새로 강제하지 않는다.

### 세부 계약

하나의 파일은 **한 변경에서 함께 판단해야 하는 규칙 묶음**을 소유한다.
문장 하나당 파일을 만들거나 줄 수에 맞춰 기계적으로 자르지 않는다.
각 파일에는 다음 정보만 필요한 만큼 둔다.

1. 이 문서가 답하는 질문과 소유하는 범위.
2. 조건, 결과, 순서, 예외, 실패·복구 의미.
3. 변경할 때 추가로 확인해야 하는 계약과 그 조건.
4. 담당 코드 심볼·기존 검증 사례의 좁은 링크.

검증 링크는 해당 규칙과 함께 이동한다. 각 파일에 전체 테스트 명령이나
프로젝트 규칙을 복사하지 않는다. 작은 파일도 의미·예외가 완결되면 유효하다.

### 참조 관계

| 관계 | 의미 | 읽기 동작 |
| --- | --- | --- |
| 라우팅 | 이 질문의 정본은 저 파일이다 | 목적에 맞는 한 갈래 선택 |
| 조건부 의존 | 이 동작/경계를 바꾸면 저 계약도 지켜야 한다 | 명시된 조건에 해당할 때 추가 읽기 |
| 근거 | 이 코드/테스트가 규칙을 구현·검증한다 | 구현 확인 또는 검증 설계 때 읽기 |

예: `proposal 해제 후 잔액 refresh/coalescing을 변경할 때만 account-balances.md를 읽는다`.
막연한 `관련 문서 모두 참고`는 사용하지 않는다. 중요한 의존 조건은 본문에서
명확히 보이게 하며, 조용히 생략해 적게 읽는 것을 성공으로 계산하지 않는다.

폴더 계층은 트리여도 참조는 여러 도메인이 같은 노드로 연결되는 그래프다.
항상 서로를 읽어야 하는 의존 순환은 소유권이 잘못 나뉜 신호다. 그 규칙들을
한 파일로 합치거나 책임을 다시 배치한다. 탐색용 상위 링크의 순환과는 구별한다.
처음에는 Markdown 색인과 조건부 링크만 사용한다. 별도 그래프 DB나 수동 YAML
정본을 추가해 같은 정보를 두 군데서 관리하지 않는다.

## 전체 이동 후보

아래 새 경로는 모두 `docs/contracts/` 기준이다. 색인은 본문 이동과 별도로,
실제로 여러 갈래가 생기는 도메인/참조 묶음에 추가한다.

| 현재 정본 | 분화할 정본 후보 |
| --- | --- |
| [account-storage.md](../contracts/account-storage.md) | `domains/accounts/{create-import,switch,delete}.md`; `domains/wallet/{bootstrap,reset}.md`; `references/accounts/account-model.md`; `references/storage/wallet-database.md` |
| [security-lifecycle.md](../contracts/security-lifecycle.md) | `domains/security/{setup,change-password}.md`; `references/security/credential-policy.md`; `references/storage/secret-sessions.md`; `platforms/{apple/keychain,linux/keyring}.md` |
| [lock-sync.md](../contracts/lock-sync.md) | `domains/wallet/lock-unlock.md`; `references/wallet/mutation-barrier.md`; `references/sync/{foreground-lifecycle,account-balances}.md`; transport 전환은 아래 route-policy 정본으로 |
| [sync-network.md](../contracts/sync-network.md) | `references/sync/{foreground-lifecycle,progress}.md`; `references/network/route-policy.md`; `platforms/ios/background-transport.md` |
| [send.md](../contracts/send.md) | `domains/send/{composer,navigation}.md` |
| [donation.md](../contracts/donation.md) | `domains/donation/{composer,review-status}.md` |
| [shielding.md](../contracts/shielding.md) | `domains/shielding/flow.md`; 현재 짧고 결합된 실행 계약은 유지 |
| [send-execution.md](../contracts/send-execution.md) | `references/transactions/{proposal-ownership,proposal-release,send-broadcast}.md`; `references/signing/desktop-review-recovery.md`; scanner 공통부는 아래 scanner 정본으로 |
| [hardware-signing.md](../contracts/hardware-signing.md) | `references/signing/{pczt-protocol-selection,keystone-batch-correlation,pczt-finalization,keystone-scanner-lifecycle}.md` |
| [payment-requests.md](../contracts/payment-requests.md) | `domains/payment-requests/{intake,card-handoff}.md`; `domains/receive/request-draft.md`; `references/zcash/zip321-codec.md` |
| [swap-pay.md](../contracts/swap-pay.md) | `domains/swap/composer.md`; `domains/pay/composer.md`; `references/swaps/{quote-amounts,quote-validity,software-deposit,hardware-deposit,provider-recovery}.md` |
| [payment-links.md](../contracts/payment-links.md) | `domains/gift-cards/{payload,intake,funding,claim-preparation,claim-submission}.md`; `references/navigation/deep-link-origin.md` |
| [wallet-link.md](../contracts/wallet-link.md) | `domains/wallet-link/{transfer-format,session,import,completion}.md`; shared storage/network 의존은 해당 reference로 직접 연결 |
| [voting.md](../contracts/voting.md) | `domains/voting/{session-ownership,signing-recovery,vote-execution,mutation-participant}.md`; Home/participation은 아래 기존 상세 정본과 통합 |
| [migration.md](../contracts/migration.md) | `domains/migration/{run-lifecycle,desktop-scheduling,ios-confirmation,signed-outbox}.md`; `domains/migration/reference/preparation-core.md` |
| [ui-platform.md](../contracts/ui-platform.md) | `references/ui/{form-factor,desktop-window,mobile-insets,copy,figma-comparison}.md`; OS 표는 `platforms/index.md`; progress는 sync/progress 정본으로 |

이 표는 약 **60–70개의 규칙 문서 후보**를 만든다. 기존 상세 정본의 추가 분화와
색인은 별도이며 파일 수 자체가 목표는 아니다. 문장별 이동표를 만들 때 항상 함께
필요한 후보는 합치고, 독립 소비자가 확인되지 않은 새 공통 계약은 만들지 않는다.
이는 현행 본문/참조의 재배치 후보이며 코드베이스 전체의 새 스펙을 발굴하는 견적이 아니다.

### 기존 상세 정본과 미문서화 영역

- [voting-home-discovery.md](../voting-home-discovery.md)는 voting의 Home/discovery
  정본이다. `domains/voting/home-discovery.md`로 이동하거나 직접 연결하되, 현재
  voting 요약과 같은 규칙을 이중 유지하지 않는다.
- [voting-participation.md](../voting-participation.md)는 약 14 KB로 proof/trust,
  cache/recovery, regtest 실행법이 섞여 있다. proof와 persistence 계약을 구별하고
  명령·fixture 설명은 별도 가이드로 빼는 추가 검토가 필요하다. 핀·측정 시점·
  인용·불확실성은 원문과 함께 보존한다.
- [gift-card-claim-outcomes.md](../gift-card-claim-outcomes.md)는 settlement 의미의
  정본으로 유지하거나 그대로 옮긴다. funding/claim-submission 문서에 결과 행렬을
  복제하지 않는다. 개발 데이터·검증 절차는 계약 본문과 구별한다.
- 현재 구조에 독립 계약이 없는 Activity, Address book, Address scan 등은 도메인
  색인에서 **소스 진입점만 있는 영역**으로 표시할 수 있다. 빈 계약 파일을 만들어
  전수 문서화가 끝난 것처럼 보이게 하지 않는다. 새 행동 계약 작성은 별도 조사다.

## 함께 유지해야 하는 계약

1. **Proposal release의 성공 의미:** Rust 해제와 authoritative balance refresh가
   모두 완료돼야 성공이라는 후조건은 release 파일 안에 유지한다. refresh 내부
   coalescing 구현만 별도 balance 계약으로 연결한다.
2. **요청 카드의 예외:** 3초 grace·추가 시도 뒤 미확인 release 상태에서도 인계하는
   현재 예외는 `card-handoff.md` 소유다. 일반 Send 취소 규칙을 약화하지 않는다.
3. **Keystone 검증:** request ID·ordered message IDs·서명 개수의 결합 검증,
   TEX 두 transaction 연결, Sapling params의 proof/finalization 양쪽 요구,
   broadcast 후 저장 실패와 blind resend 금지는 각각 완결된 단위로 보존한다.
4. **금액 의미:** Receive의 typed/derived USD, Donation의 현재 가격 변환, Swap의
   provider base units를 하나의 일반 금액 정책으로 합치지 않는다.
5. **Mutation barrier:** [wallet_mutation_guard.dart](../../lib/src/providers/wallet_mutation_guard.dart)의
   migration quiesce → voting drain → foreground sync pause와 성공/실패별 resume는
   한 정본이 소유한다. 각 participant의 추가 의무는 해당 계약으로 연결한다.
6. **Reset:** DB 경로 확보, 관련 writer 정지, DB/secure storage 삭제, cached DB 경로
   제거의 전체 전이는 reset 문서에 남긴다. DB 삭제 후 실패에서 sync를 재개하면 안
   되는 조건도 유지한다. 개별 API를 서로 다른 문서에서 조립하도록 맡기지 않는다.
7. **Lock/unlock:** 비밀 세션 차단 → account/sync clearing, unlock → 데이터 복구 →
   sync recovery → route/intent 해제의 순서는 사용자 전이 문서에서 이어서 읽힌다.
8. **iOS migration:** 필요한 알림 제출 성공 → continuation 기록 → task 완료 및
   계정별 continuation 제외 규칙은 같은 confirmation 파일에 둔다. watch-only
   confirmation과 이미 서명된 outbox 전송은 권한이 달라 별도 파일이다.
9. **Sync guard:** foreground mode 1과 preparation mode 2가 cancel token은 달라도
   `SYNC_RUNNING`을 공유한다는 조건을 양쪽에서 동일한 guard 정본으로 연결한다.

## 작업별 읽기 경로

이미 파일을 알면 첫 색인은 생략한다. 아래 추가 의존은 해당 변경에만 따른다.

| 작업 | 기본 경로 | 추가로 읽는 조건 |
| --- | --- | --- |
| 도네이션에서 Keystone 취소 후 재확인 | Donation 색인 → `review-status.md` → `desktop-review-recovery.md` | 해제 자체를 바꾸면 `proposal-release.md` |
| Receive에서 USD 가격 소실 후 Create 수정 | Receive 색인 → `request-draft.md` | URI 출력도 바꾸면 `zip321-codec.md` |
| 앱 링크 host 변경 | OS/참조 색인 → `deep-link-origin.md` | 실제 association 검증을 하면 기존 E2E 가이드의 해당 절 |
| UI copy 대소문자 변경 | UI 참조 → `copy.md` | 해당 화면의 문자열 fixture/test만 확인 |
| Linux에서 마지막 계정 삭제 중 정지 | Accounts delete → Wallet reset → `mutation-barrier.md` | keyring 대기면 `platforms/linux/keyring.md`; DB 삭제 경계면 `wallet-database.md` |
| iOS migration 완료 알림 반복 | Migration 색인 → `ios-confirmation.md` | native read API를 바꾸면 `preparation-core.md`; 전송이면 `background-transport.md` |
| Pay 취소 후 입력 복원 변경 | Pay 색인 → `composer.md` | quote 무효화면 `quote-validity.md`; hardware draft 해제면 `hardware-deposit.md` |

그래프가 있다고 모든 연결을 재귀적으로 읽지는 않는다. 코드 수정의 영향이 경계를
넘는 경우에는 필요한 문서를 추가한다. 많이 읽는 편이 정확한 작업을 억지로 줄이지 않는다.

## 실행 순서와 위임

### 1. 정본과 참조를 먼저 이동

현재 절/문장 → 새 소유 파일 → 소비자/읽는 조건 → 코드/검증 근거의 이동표를 만든다.
cross-domain 소비가 명확한 proposal release, balance refresh, secret sessions,
Linux/Apple storage, app-link origin, copy/Figma부터 분리한다. 각 묶음은 원래
본문 제거와 모든 활성 참조 갱신까지 같은 작업 단위에서 끝낸다.

이 단계에서는 문장을 더 압축하거나 동작을 바꾸지 않는다. 이동과 의미 수정을
섞으면 누락 원인을 구별하기 어렵다. 잘못된 현재 설명을 발견하면 별도 교정으로 표시한다.

### 2. 도메인별 세부 계약과 색인 구성

Send만이 아니라 Accounts/Wallet/Security, 모든 결제 도메인, Wallet Link,
Voting/Migration, UI/OS를 이동표에 따라 분화한다. 도메인 색인은 형제 도메인 본문을
경유하지 않고 필요한 공통 정본을 직접 가리킨다. 이후 루트 AGENTS를 세 진입점으로 바꾼다.

### 3. 실제 참조 경로 검증

모든 활성 링크·anchor·정본 위치를 확인하고 위 작업 예시들의 필요한 문서 집합을
대조한다. 오래된 wrapper 문서를 상시 읽는 경로로 남기지 않는다. 역사적 계획·실험
보고서는 당시 경로를 기록한 자료로 구별하며 무조건 현재 구조로 다시 쓰지 않는다.

주 에이전트는 소유권 이동표, 공통 정본, 루트 색인과 최종 참조 검토를 맡는다.
서브에이전트 1은 결제/서명, 1은 계정·보안·sync/migration을 담당하고, 주 에이전트가
Voting/Wallet Link/UI를 통합한다. 공통 파일은 쓰기 소유자 한 명만 지정한다.
각 묶음 완성 후 다른 담당자가 이동 전·후 조건과 경로를 교차 확인한다.

## 완료 조건과 관측

- 기존 규칙·예외·숫자·source/test 근거마다 정본 위치가 하나씩 존재한다.
- 상위 색인은 계약 본문을 복제하지 않고 필요한 세부 파일로 직접 연결한다.
- 공통 계약을 읽기 위해 무관한 도메인 문서를 경유할 필요가 없다.
- 알맞은 조건부 의존은 보존되며 중요한 처리 순서가 여러 파일의 추측으로 바뀌지 않는다.
- 파일/anchor 링크, 고아 문서, 항상 함께 읽는 의존 순환, 변경된 source 심볼을 확인한다.
  Markdown 구조 검사만으로 의미 보존을 증명했다고 주장하지 않는다.
- 여덟 종류 이상의 실제 질문으로 도착 정본·관련 source/test를 찾는 경로를 확인한다.
  위 표의 일곱 질문에 일반 Send 또는 Voting recovery를 추가한다.
- 문서 읽기량을 비교할 때 루트/색인/leaf/필요 의존을 모두 포함한다. 같은 문서를
  여러 번 읽으면 그 노출도 기록한다. 파일 본문 바이트는 입력 토큰·캐시·청구액과 구별한다.
- 이번 구조 개편에 새 A/B 모델 실행은 기본 포함하지 않는다. 우선 링크/의미 검사와
  실제 작업 경로로 검증하고, 도구에 사용량이 남는 실전 작업에서만 추가 관측한다.

현재까지 수행한 것은 16개 계약의 절·참조 조사, 두 독립 검토, 일부 순서의 source
대조, 정적 문서 크기 측정이다. 새 구조의 검색 효율이나 토큰 절감은 아직 실측하지 않았다.
