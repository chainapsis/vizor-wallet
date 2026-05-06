# macOS fastlane

GitHub Actions 기준 macOS 외부 배포용 fastlane 설정입니다.

실행:

```bash
bundle exec fastlane mac build
bundle exec fastlane mac package
bundle exec fastlane mac release
```

`release` lane 순서:

1. mainnet/testnet flavor별로 `match`로 Developer ID 인증서 + provisioning profile 설치
2. flavor별 `fvm flutter build macos --release --dart-define=ZCASH_DEFAULT_NETWORK=<network>`
3. flavor별 `.app` notarize + staple
4. flavor별 `.zip` / `.dmg` 생성
5. flavor별 `.dmg` notarize + staple
6. GitHub Release에 모든 flavor asset 업로드

기본 release flavor는 `mainnet,testnet`입니다. 단일 flavor만 빌드하려면:

```bash
VIZOR_MACOS_FLAVOR=mainnet bundle exec fastlane mac build
VIZOR_MACOS_FLAVOR=testnet bundle exec fastlane mac build
VIZOR_MACOS_FLAVORS=mainnet,testnet bundle exec fastlane mac release
```

## Required environment variables

`release` lane은 아래 값이 없으면 해당 단계에서 바로 실패합니다.

- `MACOS_KEYCHAIN_PASSWORD`
- `MATCH_GIT_URL`
- `MATCH_GIT_BASIC_AUTHORIZATION`
- `MATCH_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_JSON`
- `GITHUB_TOKEN`
- `RELEASE_REPOSITORY`
- `RELEASE_COMMITISH`

태그 기반 워크플로우가 아니면 아래도 필요합니다.

- `RELEASE_TAG`

## Optional environment variables

- `MACOS_KEYCHAIN_NAME`
- `MATCH_GIT_BRANCH`
- `MATCH_READONLY`
- `MATCH_APP_IDENTIFIER`
- `RELEASE_NAME`
- `VIZOR_MACOS_FLAVOR`
- `VIZOR_MACOS_FLAVORS`
- `GITHUB_RELEASE_DRAFT`
- `GITHUB_RELEASE_PRERELEASE`

## Notes

- `APP_STORE_CONNECT_API_KEY_JSON`은 fastlane `notarize` 액션이 읽을 수 있는 App Store Connect API key JSON 전체 문자열을 기대합니다.
- `MATCH_GIT_BASIC_AUTHORIZATION`은 GitHub private repo 접근용 Basic auth Base64 문자열입니다. 예: `echo -n "github_user:pat" | base64`
- CI는 `MATCH_READONLY=true`로 두고, `match` 저장소는 로컬에서 한 번 시드해 둔 상태를 전제로 합니다.
- `MATCH_READONLY=false`로 돌리면 fastlane은 `match` write 모드로 동작합니다. 이때는 `APP_STORE_CONNECT_API_KEY_JSON`이 준비돼 있어야 하며, git commit identity는 deployment workflow가 설정합니다.
- `MATCH_READONLY=false`일 때 testnet Bundle ID(`com.keplr.vizor.testnet`)가 없으면 fastlane이 App Store Connect API로 먼저 생성한 뒤 Developer ID provisioning profile을 생성합니다.
- 산출물은 repo root의 `dist/macos` 아래에 생성됩니다.
