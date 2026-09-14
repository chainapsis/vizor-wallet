# Vizor 에이전트 문서 정리 — 다음 페이즈 견적

2026-09-12 · 견적 전용 · 기준 `rowan/agent-contract-docs` / `5b2783bb2`

추천은 **프로젝트 검증 지침의 적용 범위 명확화 + migration 계약과 중복 주석 정리**다. 예상 변경은 5–6개 파일, 에이전트 작업시간 합산 약 2–3시간이다. 독립 작업을 병행하면 경과 시간은 약 1.5–2.5시간으로 예상한다. 표본 조사 기반 계획치이며 실제 실행 시간이나 토큰 절감 실측이 아니다.

## 완료된 범위와 이번 경계

- 문서 브랜치에는 루트 AGENTS.md 경량화, 계약 문서 11개, 코드 6개 파일의 주석 정리가 보존돼 있다.
- 루트 AGENTS.md는 기준 `efbc2f3dea`의 64,680 bytes / 977줄에서 5,485 bytes / 98줄로 바뀌었다. **루트 파일 바이트만 91.5% 감소**한 수치다. 계약 문서는 합계 67,618 bytes / 1,175줄이며, 총 문서량이나 실전 입력 토큰이 같은 비율로 줄었다는 뜻이 아니다.
- Rowankit 및 사용자 AGENTS.md 정리·main 반영·Codex 재설치는 완료된 별도 작업으로 이번 견적에서 제외한다.
- **Vizor의 로컬·원격 main은 변경하지 않는다.** 실행하더라도 기존 문서 작업 브랜치에서만 변경한다. 이 견적 작성은 구현·커밋·푸시·설치·모델 실험을 수행하지 않는다.
- 문서 경량화를 위해 실행 코드, API 문서, 지시 주석, 보안·경합·순서·복구의 유일한 설명을 삭제하지 않는다.

## 추천 작업

| 작업 | 산출물·범위 | 합산 작업시간 |
| --- | --- | --- |
| 검증 지침 적용 범위 명확화 | `CONTRIBUTING.md`의 문서·주석·동작·FFI/native 변경별 확인 범위를 구분. 필요할 때만 AGENTS.md의 연결 문구 조정 | 30–45분 |
| Migration 계약 보완과 반복 주석 정리 | 기존 `migration.md`와 아래 코드 3개. 새 계약 파일을 만들지 않고 누락된 경계와 구체적 테스트 진입점을 보완 | 60–90분 |
| 통합 검토와 전달 | 문서와 코드의 의미 대조, 변경부가 주석에 한정되는지 확인, 링크·심볼·기존 테스트 사례 확인, 변경 요약 | 20–35분 |

합계 110–170분을 반올림해 **약 2–3시간**으로 잡는다. 전체 빌드·regtest, 신규 테스트 프레임워크, 외부 프로토콜 전수 감사는 포함하지 않는다. 실행 의미의 수정이 필요해지는 발견은 별도 이슈로 보고하며 이 문서 정리 작업에 섞지 않는다.

### 검증 지침

현재 [CONTRIBUTING.md](../../CONTRIBUTING.md#testing)는 가장 작은 관련 검증을 먼저 하라고 하면서 Dart/Flutter 변경에 `analyze`와 전체 `flutter test`, Rust 변경에 `cargo test`를 기본 명령으로 나열한다. 문서·주석 변경에도 전체 실행이 필요한지 적용 범위가 명확하지 않다. 문서/일반 주석 변경, 동작 변경, UI 변경, API/FFI/native 변경을 구분해 필요한 증거를 명시하는 것이 후보이다.

이는 전체 검증이 불필요하다고 판정한 결과가 아니다. 실제 동작·통합 경계의 필수 검사는 유지하고, 같은 변경에 대한 중복 지침과 모호한 분류만 정리한다. [E2E 가이드](../../scripts/e2e/README.md#running-regtest-safely)의 명시적 실행 요청과 공유 상태 보호 조건도 유지한다.

### Migration

대상 코드:

- [BackgroundMigrationPreparationManager.swift](../../ios/Runner/BackgroundMigrationPreparationManager.swift)
- [ironwood_migration_coordinator_provider.dart](../../lib/src/features/migration/providers/ironwood_migration_coordinator_provider.dart)
- [ironwood_migration_service.dart](../../lib/src/features/migration/services/ironwood_migration_service.dart)

기존 [migration.md](../contracts/migration.md)에 다음 현재 구현 계약을 짧게 보완한다.

1. Desktop wallet-open epoch는 창 표시 여부와 다르며, sleep/활동 공백 판단과 authoritative entry height가 overdue-at-open 허용량을 결정한다. OS별 clock 차이를 담당 심볼과 연결한다.
2. iOS 여러 계정의 tracking/foreground continuation 집합을 구별한다. 계정 A의 handoff가 정상 추적 중인 계정 B를 멈추면 안 된다. `migrationPreparationHandoffContinuationScopes`와 `migrationPreparationHandoffHasBoundPreparation`은 서로 다른 질문에 답한다.
3. 계약 끝의 넓은 테스트 디렉터리 링크를 실제 해당 사례가 있는 파일·심볼로 좁힌다.

확인한 중복 예시는 Swift helper의 cold-launch 설명(637–653행)과 호출부 설명(1022–1028행), coordinator의 epoch/clock 설명(23–53, 239–245, 773–794행)이다. 행 번호는 기준 커밋에서의 위치이며 작업 시 심볼로 찾는다. 함수 API 문서와 변경 지점의 짧은 이유를 남기고 반복된 회귀 경위만 축약한다.

그대로 유지할 예시는 `setTaskCompleted` one-shot race, authoritative entry height가 없을 때의 fail-closed, accepted-but-not-stored txid 구분이다. 주석 개수나 파일 길이는 삭제 판단 기준이 아니다.

## 선택 범위

| 선택 항목 | 예상 범위·시간 | 판단 |
| --- | --- | --- |
| Voting 실행 순서 보완 | 기존 문서·코드 2–3개, 추가 40–60분 | 같은 bundle의 `submit → confirm → tree re-sync` 순서와 bundle 간 병렬성을 기존 voting 계약에 연결. API docs와 local race 이유는 유지 |
| Payment Links / Swap 추가 주석 정리 | 25–40분 후보 | 우선 보류. 표본에서는 주석이 적고 durable marker, reorg, secret-session 보호 등 남길 이유가 많음 |
| 11개 계약 전체 재작성·전역 주석 삭제 | 별도 견적 | 현재 필요성을 입증하지 못함. 이번 페이즈에 포함하지 않음 |

Voting까지 포함하면 합산 약 **2.5–4시간**, 예상 변경 7–9개 파일이다. 새 검색 규칙, 하위 AGENTS.md 다량 생성, 강제 파일명 우선 탐색은 제안하지 않는다.

## 위임과 완료 조건

주 에이전트는 검증 지침, 계약 간 소유권·링크, 최종 diff와 전달을 맡는다. 서브에이전트 1개는 Migration 3개 코드 파일과 계약 문서만 맡는다. 최대 동시 작업은 2개이며 서브에이전트에는 필요한 경로·완료 조건만 전달한다. 후보마다 검증 에이전트를 새로 만들지 않는다. Voting을 추가하면 독립 작업 1개로 별도 배정할 수 있다.

완료 조건:

- 문서에 새로 정리한 계약이 현재 코드와 기존 테스트의 구체적 사례에 맞는다.
- 주석 외 실행 의미가 동일하다. API docs, 지시 주석, 라이선스와 실행 문서 예제는 보존한다. 정규식으로 문자열까지 지워 비교한 결과만으로 의미 불변을 주장하지 않는다.
- 변경한 문서의 파일 링크·심볼 진입점이 유효하고, 동일 계약의 정본이 두 곳으로 갈라지지 않는다. 다른 계약은 관련 경계를 넘을 때만 따라갈 수 있게 연결한다.
- 일반 문서/주석만 바뀌면 해당 diff·링크·기존 테스트 사례 대조로 마친다. 새 단위 테스트나 전체 빌드·regtest를 이 작업 때문에 자동 추가하지 않는다.
- 결과 보고에는 실제 줄어든 문서/주석 범위, 미검증 항목, 잔여 후보를 적는다. 입력 토큰 20–30% 절감을 완료 조건으로 약속하지 않는다.

## 실행량과 비용

이 추천안에 추가 A/B 참가자 실행은 **0회**다. 주 에이전트 1개와 Migration 서브에이전트 1개의 구현·검토 작업으로 잡는다. 이는 무료라는 뜻이 아니며 해당 에이전트들의 일반 사용량은 발생한다. 이번 표본만으로 누적 입력 토큰·캐시 적중·주간 한도 차감·청구액을 예측할 근거가 없어 달러 금액으로 환산하지 않는다.

별도 벤치마크 대신 이후 실제 Migration 또는 Voting 작업에서 문서 진입, 불필요한 전체 검색, 중복 읽기, 계약 오해·재작업 여부를 기록할 수 있다. 기존 도구에 해당 작업 사용량이 남는 경우만 함께 보고한다. 이는 실전 관측이며 대조군 없는 수치를 인과적 절감률로 해석하지 않는다.

이전 검색 출력 확인 실험은 두 조건 모두 같은 계약 문서를 받았고 파일명 중심 조건의 누적 입력이 11.7% 증가했다. 따라서 전역 검색 규칙 채택은 중단했지만, 계약 문서 정리 자체를 기각한 실험은 아니다. 로컬 근거: `/Users/rowan/keplr-workspace/vizor-wallet-agent-context-lab/experiments/agent-context/search-output-confirmation-20260911/execution-report.md`의 결론 및 비교 조건. 과거 실험 환산 비용은 이번 구현 견적에 재사용하지 않는다.
