# 모바일 온보딩 진행률 설계 및 후속 PR 범위

작성일: 2026-09-30
기준: #794–#799의 모바일 디자인과 데스크탑 분리 PR #800.
상태: 사용자 확인 기준으로 로컬 구현·검증·영상 녹화 완료.
2026-10-01 요청에 따라 데스크탑 디자인·테스트넷 처리는 독립된 Draft로 분리한다.
이 PR은 #800 위에 모바일 진행률과 관련 정리만 적용한다.

## 1. 목적과 현재 문제

Gift 추가 전에 모바일 상단 진행률의 의미와 계산을 통일한다. 화면별 숫자를 없애고
플로우의 단계 목록에서 계산한다. 모바일 fixture와 사용하지 않는 스타일도 정리한다.

현재 소스에서 확인한 문제:

- `mobile_onboarding_progress.dart`에 생성/가져오기 단계 수, 선택 화면 채움,
  Keystone/Link/Ledger 전용 분수가 혼재한다.
- 생성 Introduction 30.6% → Address Types 37.5% 등 생성과 가져오기의 계산 기준이 다르다.
- 선택 화면 → Link/Keystone Introduction은 30.6% → 20%, Ledger Connect는 30.6% → 25%로 감소한다.
- 패스코드를 건너뛰는 추가 계정에서도 단계 수가 같다.
- Birthday/Customise의 임의 `double` 오버라이드로 호출자가 계산을 우회한다.

기존 라우트 재현에서 감소를 확인했다. 감소 현상은 #798/#799에서 새로 생긴 회귀가 아니다.

## 2. 진행률의 의미와 기준

**진행률은 계정 준비 과정의 현재 위치다.** 남은 시간이나 네트워크 처리량을 뜻하지 않는다.

사용자가 확인한 기준:

1. 첫 채움 `60 / 196` (약 30.6%) 유지.
2. 이후 해당 진입에서 필요한 단계 목록으로 계산.
3. 추가 계정에서 필요 없는 패스코드는 목록에서 제외.
4. 뒤로 가면 해당 단계의 값으로 복귀.

이를 구체화한 제안:

- Welcome에는 바를 표시하지 않고 숨겨진 Welcome을 단계 수로 세지 않는다.
- 생성 Introduction, 가져오기 방식 선택, 하드웨어 종류 선택은 같은 시작 위치다.
  방식 선택 → 하드웨어 종류 선택은 값이 같아도 된다. 실제 다음 단계는 증가한다.
- 계정 준비 성공 전에는 100%가 되지 않는다. 성공 뒤 생체 인증 제안은 현재처럼 100%다.
  이는 계정 준비 완료이며 생체 인증 사용 여부를 뜻하지 않는다.
- 생체 인증 미지원 기기와 추가 계정은 기존대로 성공 후 Home으로 이동한다.
  100% 화면을 새로 삽입하지 않는다.
- 바의 크기·색·위치·전환 표현과 copy는 유지한다. 퍼센트/단계 번호를 새로 노출하지 않는다.
  실제 완료 여부는 기존 계정/보안 로직이 판단한다.

## 3. 단계 목록과 계산

`A = 60 / 196`, 시작 이후 계정 준비 단계 수를 `N`, 단계 순서를 `i` (1부터)로 둔다.

```text
시작 위치: A
계정 준비 단계: A + (1 - A) × i / (N + 1)
계정 준비 성공 후: 1
```

마지막 미완료 단계와 완료 사이에도 한 구간을 남긴다. 다음 표에만 순서를 정의하며
화면은 숫자 인덱스를 넘기지 않는다.

| 플로우 | 시작 위치 화면 | 시작 이후 계정 준비 단계 |
| --- | --- | --- |
| 생성 | Introduction | `addressTypes` → `thingsToKnow` → `secretPassphrase` → `passcode` → `customiseAccount` |
| 문구 가져오기 | 방식 선택 | `phraseEntry` → `phraseReview` → `birthday` → `passcode` → `customiseAccount` |
| Keystone | 방식/하드웨어 종류 선택 | `deviceIntro` → `deviceScan` → `accountSelection` → `birthday` → `passcode` → `customiseAccount` |
| Ledger | 방식/하드웨어 종류 선택 | `deviceConnect` → `birthday` → `passcode` → `customiseAccount` |
| Link Vizor Desktop | 방식 선택 | `linkIntro` → `linkScan` → `accountSelection` → `contactSelection` → `passcode` |

진입 당시 `appSecurityProvider.isPasswordConfigured`를 기준으로 목록을 만든다.
Welcome의 Back 버튼이나 계정 수로 패스코드 필요 여부를 추측하지 않는다.

- `createPasscode`: 표의 전체 단계. `reusePasscode`: `passcode`만 제외.
- 생체 인증은 `N`에 포함하지 않는다.
- Link는 Customise를 사용하지 않는다. 기존 지갑에서 연락처만 가져오는 경우도
  현재 선택 화면을 유지하고 Contacts의 가져오기가 성공하면 Home이다.

### 예시 값

각 열은 **시작 이후** 단계 순서다. 표기만 소수 첫째 자리로 반올림한다.
렌더러에는 원래 값을 전달한다. 모든 시작 위치는 30.6%다.

| 플로우 | 패스코드 생성 필요 | 패스코드 재사용 |
| --- | --- | --- |
| 생성 | 42.2 → 53.7 → 65.3 → 76.9 → 88.4% | 44.5 → 58.4 → 72.2 → 86.1% |
| 문구 가져오기 | 42.2 → 53.7 → 65.3 → 76.9 → 88.4% | 44.5 → 58.4 → 72.2 → 86.1% |
| Keystone | 40.5 → 50.4 → 60.3 → 70.3 → 80.2 → 90.1% | 42.2 → 53.7 → 65.3 → 76.9 → 88.4% |
| Ledger | 44.5 → 58.4 → 72.2 → 86.1% | 48.0 → 65.3 → 82.7% |
| Link | 42.2 → 53.7 → 65.3 → 76.9 → 88.4% | 44.5 → 58.4 → 72.2 → 86.1% |

문구 가져오기에서 패스코드를 생성하는 경로는 #799에서 고친 값과 동일하다.
다른 경로의 채움은 위 규칙에 맞게 바뀐다.

## 4. 건너뛰기·Back·재시도

| 상황 | 규칙 |
| --- | --- |
| Introduction에서 교육 Skip | 교육 두 단계를 통과하여 `secretPassphrase` 값으로 이동. 목록을 줄여 이전 값을 바꾸지 않는다. |
| Paste ↔ Manual | 둘 다 `phraseEntry`. 입력 방식 변경으로 증가하지 않는다. |
| Review의 Clear | 기존 동작대로 문구를 지우고 `phraseEntry`로 복귀. 감소가 정상이다. |
| Birthday 탭/Skip/추가 계정 발견 시트 | 같은 `birthday`. 다음 단계로 이동할 때만 증가한다. |
| 패스코드 입력 → 확인/불일치 → 재입력 | 같은 `passcode`. 확인을 별도 단계로 세지 않는다. |
| QR 조각/권한/연결·스캔 재시도 | 같은 스캔/연결 단계. QR 디코딩 진행률과 별개다. |
| Customise 프로필 시트/저장 대기/실패 | 같은 값. 저장 성공 전에는 완료로 표시하지 않는다. |
| Link 제출 실패 | Contacts 또는 Passcode 단계에 유지. 재시도로 증가하지 않는다. |
| 기존 Back/스와이프/취소 | 원래 화면 값으로 복귀. 새 Back 경로나 취소 버튼은 추가하지 않는다. |
| 선택 화면에서 방식 변경 | 같은 보안 스냅샷으로 새 목록 선택. 이전 최대값을 이어받지 않는다. |
| Welcome 재시작/Home에서 계정 추가 | 현재 보안 조건으로 새 목록 생성. 이전 실행 값을 보관하지 않는다. |

교육은 시작할 때 제시된 선택 가능한 구간이므로 Skip은 통과한 것으로 표현한다.
패스코드는 진입 조건상 존재하지 않는 구간이므로 제외한다. 두 동작을 같은
“화면 삭제 후 재계산”으로 처리하지 않는다.

`max(previous, current)`로 감소를 숨기거나 방문 횟수/스택 길이/시간으로 누적하지 않는다.
재빌드·로딩 이벤트로 값이 변하지 않아야 한다.

## 5. 구현 구조

**순수 단계 목록 모델 + 모바일 라우트가 전달하는 불변 UI 문맥**을 사용한다.
현재 단계나 진행률 숫자를 저장하는 전역 컨트롤러는 만들지 않는다.

| 표면 | 책임 |
| --- | --- |
| `mobile_onboarding_progress.dart` | 플로우·단계·보안 조건 타입, 불변 `OnboardingProgressPlan`, 목록·계산·검증 |
| `mobile_onboarding_progress_scope.dart` | 패스코드 필요 여부의 보안 스냅샷 전달. 플로우/목록/현재 값이나 비밀 데이터를 새로 저장하지 않는다. |
| `mobile_onboarding_routes.dart` | 기존 payload 검증과 UI 문맥 제공. 최초 진입의 보안 스냅샷을 이동에 전달한다. |
| 각 화면 | 의미 있는 자신의 단계만 선택. 공용 Birthday/Passcode/Customise는 해당 플로우의 위치를 사용한다. |
| Scaffold / `MobileTopNav.steps` | 계산 결과 `double`을 그리는 기존 렌더러. Send 등 다른 기능은 변경하지 않는다. |

구현 API:

```dart
final plan = OnboardingProgressPlan.forFlow(
  OnboardingFlow.keystone,
  setupMode: OnboardingSetupMode.reusePasscode,
);
final position = plan.at(OnboardingStage.birthday);
// Only the rendering boundary consumes position.value.
```

공용 화면은 `OnboardingProgressPosition` 같은 타입을 받는다. production의 임의
`double` 오버라이드는 제거한다. Widgetbook/캡처도 같은 모델의 고정 fixture를 사용한다.
모델은 Flutter/Riverpod/저장소/네트워크에 의존하지 않는다.

선택 화면과 생성 Introduction은 공통 `start` 위치를 사용한다. 생체 인증 화면은
`accountReady` 위치를 사용한다. 이 두 위치는 플로우가 없어도 표현할 수 있다.
그 외 목록은 각 라우트가 아는 플로우 또는 기존 setup payload의 flow와 보안 스냅샷에서
순수하게 도출한다. 목록 자체를 라우트 문맥에 중복 저장하지 않는다.

### 문맥 전달과 수명

1. 패스코드 필요 여부는 진입 시 고정한다. 플로우는 해당 라우트/기존 payload가 정한다.
   빌드마다 보안 provider를 watch해 단계 수를 다시 정하지 않는다.
2. 모바일 이동용 작은 wrapper에 기존 payload와 UI 문맥을 싣고 page 아래 feature 전용
   scope에서 읽는 방식을 권장한다. `SetPasswordScreenArgs` 등은 payload로 유지한다.
   데스크탑 공용 args에 UI 필드를 추가하지 않는다.
3. guard는 payload를 꺼내 기존 타입/필수값 검증을 수행한다. 인증·저장 순서·`push`/`go`·
   `pop` 반환값을 유지한다. Manual/Review Clear 결과, pending passcode 수명,
   기존 mnemonic/provider 정리를 변경하지 않는다.
4. Welcome Create/Import에서 새 문맥을 만들고 선택 시 이동할 라우트로 플로우를 정한다.
   Back으로 남은 페이지는 자신이 받은 문맥을 유지한다.
5. 현재 허용된 직접 진입 `/import`, Keystone/Ledger/Link 시작 경로는 진입점에서
   새 문맥을 만든다. 선택 화면을 거치지 않아도 같은 전체 목록의 현재 위치를 사용한다.
   payload가 필요한 중간 경로의 오류/누락은 기존 redirect 정책을 유지한다.
6. `SetPasswordFlow` → `OnboardingFlow` 변환은 한 곳에서 exhaustive하게 한다.
   Passcode/Customise에 같은 분기표를 중복하지 않는다.
7. prepare/commit으로 보안 상태가 바뀌어도 현재 목록을 재계산하지 않는다.
   UI 스냅샷은 권한 판단 근거가 아니다. 인증·mutation guard는 현재 보안 상태로 판단한다.
8. 취소/완료 후 별도 progress 상태를 남기지 않는다. 재시작·잠금·지갑 초기화는
   기존 bootstrap/guard로 처리한다. UI 진행률을 영속화하지 않는다.
9. 잘못된 플로우/단계 조합은 명확히 실패한다. 임의 값이나 생성 플로우로 대체하지 않는다.

상수만 고치면 새 플로우에서 문제가 반복된다. 전역 progress provider는 Back·방식 변경·
다중 페이지의 수명 관리가 추가된다. 불변 문맥은 라우트 전달 부분을 손봐야 하지만
값이 변하는 이유가 명확하다. 범용 wizard 엔진, 새 ShellRoute, 라우트명 재설계로 확대하지 않는다.

## 6. Gift 확장 계약

Gift Claim/Home은 미확정이며 이번 PR에서 구현·활성화하지 않는다. 별도 기존 작업 트리에는
Gift 패스코드, 일반 가져오기 후 Claim 복귀, Home 이후 교육/백업/생체 인증 시안이 있다.
참고이며 통합된 요구사항이 아니다. 해당 작업 트리를 수정하거나 코드를 가져오지 않았다.

향후 확정 시:

- 일반 문구/하드웨어 가져오기는 해당 목록을 재사용한다. Claim 대기/복귀를 임의로 더하지 않는다.
- Gift 전용 준비 순서가 다르면 별도 플로우를 정의한다. 공용 화면에는 그 목록의 위치를 전달한다.
  `SetPasswordFlow`를 UI 진행률 분류로 확장하지 않는다.
- 계정 준비 완료와 Claim 완료는 다른 조건이다. Gift 바의 의미는 Gift 스펙에서 정한다.
  현재 100%는 카드 수령 성공을 뜻하지 않는다. Claim/sync 처리량과 상단 바를 혼합하지 않는다.
- Home 이후 교육/백업은 별도 과제다. 일반 온보딩의 100%를 다시 낮추거나
  일반 생성 목록의 패스코드 단계 수를 재사용하지 않는다.
- 이번에는 미사용 Gift enum/빈 목록/영속 checkpoint/가짜 Gift 테스트를 만들지 않는다.

Gift 스펙에서 결정할 사항: 첫 계정 준비 순서, 일반 가져오기 후 복귀, Claim 실패 후속 경로,
Home 과제 범위. 이 결정 없이 최종 단계 수를 확정하지 않는다.

## 7. 모바일 PR 범위

데스크탑 분리 PR #800을 기반으로 모바일 진행률을 올린다. `main`은 변경하지 않는다.
데스크탑 Welcome·선택 화면·Introduction과 테스트넷 설명은 별도의 독립 Draft에 포함한다.

### 모바일 정리

1. Birthday 테스트에 기존 `loadFigmaCompareFonts`를 적용한다.
   11px overflow는 테스트 폰트 문제였으므로 production 달력은 수정하지 않는다.
2. 모바일 disabled Gift 버튼의 무효한 active/pressed/focus 오버라이드와 전용 `ghostLabel`,
   `ghostHighlightedBackground` 토큰만 제거한다. disabled 스타일·접근성·최초 Welcome 표시·TODO는 유지한다.
3. 중복 생성 진입 테스트 두 개를 더 강한 최초/추가 계정 왕복 테스트로 통합한다.
   레이아웃/접근성/작은 화면/네트워크 조건 테스트는 유지한다.

최초/추가 계정 Back/Cancel, Birthday 기존 10개 테스트, 변경 Welcome 테스트를 집중 검증한다.
영상·포스터·lifecycle 테스트와 실제 사용 중인 공용 컴포넌트는 정리 대상이 아니다.

### 모바일 진행률 리팩토링

1. 순수 모델과 모바일 UI 문맥 전달을 함께 도입한다.
2. 생성·문구·Keystone·Ledger·Link와 공용 Birthday/Passcode/Customise/선택 화면을 전환한다.
3. Widgetbook/figma_compare/기존 테스트 fixture와 모바일 통합 테스트 지원 코드의 route 전달을 갱신한다.
4. 기존 step count, 정수 인덱스 함수, 분수, raw progress 오버라이드를 제거한다. 신구 계산을 동시 유지하지 않는다.

모델·라우트·호출처를 함께 전환해 사용하지 않는 모델이나 계산 방식 두 개가 남지 않게 한다.

## 8. 검증과 완료 기준

기존 테스트를 갱신하고 빠진 계약만 추가한다. 계산 함수를 복사한 기대값, 같은 검증의 복제,
매 단계/theme의 중복 캡처를 만들지 않는다.

- 모델: 다섯 플로우 × 두 조건의 목록, 시작 `60/196`, 독립적인 수치 기준, 인접 단계 증가,
  마지막 `< 1`, 완료 `1`, 제거한 Passcode/잘못된 단계의 실패.
- production 라우트: 최초/추가 계정의 생성 전체/교육 Skip, Paste/Manual/Clear,
  Keystone/Link/Ledger forward/Back. 기존 harness를 production route 정의로 확장한다.
- 기존 감소 세 경로: 선택 30.6% → Link/Keystone/Ledger 첫 화면이 증가하는 것을 실제 route와 바 값으로 확인한다.
- 수명: Passcode 제외, 확인/불일치/QR 재시도 값 유지, commit/provider 재빌드 시 값 유지,
  Back 후 방식 변경/새 진입 시 이전 최대값 미승계.
- 성공 경계: deterministic 계정/보안 fixture로 성공 전 오류는 같은 단계,
  성공 후 생체 인증은 1, 추가 계정은 Home. 기존 mutation/rollback 검증은 유지한다.
- 보안·라우트: required payload/잠금 redirect, Manual/Review 반환값, pending passcode 수명 유지.
  UI 문맥에 비밀을 중복 저장하거나 직렬화하지 않는다.
- 화면: 대표 생성/가져오기/하드웨어 단계와 추가 계정 조건을 기존 widget capture에 보강한다.
  393×852, light/dark, 모바일 define으로 바 길이를 확인한다. geometry·copy·색상은 유지한다.
- 정적 점검: 기존 숫자 함수·분수·raw 오버라이드 제거. desktop/send 바, QR 디코딩,
  미확정 Gift 작업은 diff에 포함되지 않는다.

모바일은 `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`,
데스크탑은 별도 기본 lane으로 검증한다. 캡처는
`scripts/figma-compare.sh widget --form-factor mobile`로 순차 실행한다.
실기기 연결/설치/regtest E2E는 이번 설계에서 실행한 증거가 아니다.

## 9. 현재 전달 상태

모델·라우트 문맥·화면 호출처를 함께 전환했다. 데스크탑 변경은 포함하지 않는다.
분리 전 합본에서 모바일 온보딩/라우트 193개, Widgetbook 27개 테스트와 light/dark 캡처를 확인했다.
생성·추가 계정 Skip/Back·가져오기 Clear·하드웨어/Link 진입을 iPhone 시뮬레이터에서 녹화했다.
실제 화면의 진행률 26개를 독립 기대값과 확인했고 저장·외부 연결은 deterministic fixture를 사용했다.
영상의 모바일 구현을 보존하여 #800 기반에 옮겼다. 이 기준에서 모바일 220개와 기존
데스크탑 경계 테스트 16개가 통과했다. 변경 Dart 파일 41개 정적 분석은 이상이 없고
대표 화면 light/dark 캡처 4개를 확인했다. 데스크탑 테스트넷 수정은 별도 Draft #801에 포함한다.
실기기·실제 저장·하드웨어 페어링·전체 저장소 테스트를 수행한 증거로 보지는 않는다.
