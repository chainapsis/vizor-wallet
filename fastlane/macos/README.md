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
2. flavor별 `fvm flutter build macos --release --dart-define=ZCASH_DEFAULT_NETWORK=<network> --build-name <tag version> --build-number <RELEASE_BUILD_NUMBER>`
3. flavor별 `.app` notarize + staple
4. flavor별 `.dmg` 생성
5. flavor별 `.dmg` Developer ID code sign + notarize + staple
6. stable release면 flavor별 Sparkle appcast/delta 생성
7. GitHub Release에 모든 flavor/Sparkle asset 업로드

Flavor별 앱 이름, bundle id, 기본 네트워크, macOS 앱 아이콘은
`fastlane/macos/Fastfile`의 `MACOS_RELEASE_FLAVOR_CONFIGS`에서 선택합니다.
testnet 빌드는 `macos/Runner/TestnetAppIcon.icon`을 사용합니다.

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
- `RELEASE_BUILD_NUMBER`

태그 기반 워크플로우가 아니면 아래도 필요합니다.

- `RELEASE_TAG`

stable release 태그(`release/v1.2.3`)에서는 아래도 필요합니다. prerelease 태그
(`release/v1.2.3-rc.0`, `release/v1.2.3-internal.1`)에서는 Sparkle을
건너뛰므로 필요하지 않습니다.

- `SPARKLE_PUBLIC_ED_KEY_MAINNET`
- `SPARKLE_PUBLIC_ED_KEY_TESTNET`
- `SPARKLE_PRIVATE_ED_KEY_MAINNET`
- `SPARKLE_PRIVATE_ED_KEY_TESTNET`

## Optional environment variables

- `MACOS_KEYCHAIN_NAME`
- `MATCH_GIT_BRANCH`
- `MATCH_READONLY`
- `MATCH_APP_IDENTIFIER`
- `RELEASE_NAME`
- `VIZOR_MACOS_FLAVOR`
- `VIZOR_MACOS_FLAVORS`
- `GITHUB_RELEASE_PRERELEASE`

## Notes

- `APP_STORE_CONNECT_API_KEY_JSON`은 fastlane `notarize` 액션이 읽을 수 있는 App Store Connect API key JSON 전체 문자열을 기대합니다.
- `MATCH_GIT_BASIC_AUTHORIZATION`은 GitHub private repo 접근용 Basic auth Base64 문자열입니다. 예: `echo -n "github_user:pat" | base64`
- CI는 `MATCH_READONLY=true`로 두고, `match` 저장소는 로컬에서 한 번 시드해 둔 상태를 전제로 합니다.
- `MATCH_READONLY=false`로 돌리면 fastlane은 `match` write 모드로 동작합니다. 이때는 `APP_STORE_CONNECT_API_KEY_JSON`이 준비돼 있어야 하며, git commit identity는 deployment workflow가 설정합니다.
- `MATCH_READONLY=false`일 때 testnet Bundle ID(`com.keplr.vizor.testnet`)가 없으면 fastlane이 App Store Connect API로 먼저 생성한 뒤 Developer ID provisioning profile을 생성합니다.
- release display version은 `RELEASE_TAG`에서 파싱하고, build number는 `RELEASE_BUILD_NUMBER`만 사용합니다. `pubspec.yaml`의 `version`은 macOS release 산출물 버전으로 사용하지 않습니다.
- GitHub Release asset 파일명에는 버전을 넣지 않습니다. mainnet은 `Vizor-macos.dmg`, testnet은 `Vizor-Testnet-macos.dmg`를 사용합니다.
- 랜딩 페이지의 최신 macOS 다운로드 링크는 `https://github.com/chainapsis/vizor-wallet/releases/latest/download/Vizor-macos.dmg`처럼 고정 asset 이름을 가리킵니다.
- `release/v1.2.3-rc.0` 또는 `release/v1.2.3-internal.1` 같은 prerelease 태그는 release DMG를 만들지만 Sparkle appcast/delta 업로드는 건너뜁니다.
- `release/v1.2.3-internal.1`은 내부 테스트용 public GitHub prerelease입니다. DMG asset은 업로드되지만 `appcast.xml`, `appcast-testnet.xml`, `.delta` asset은 업로드되지 않아 기존 앱의 Sparkle 자동 업데이트 대상이 되지 않습니다.
- `GITHUB_RELEASE_PRERELEASE`가 설정된 경우 태그에서 계산한 prerelease 여부와 일치해야 합니다.
- `SPARKLE_PUBLIC_ED_KEY_MAINNET` / `SPARKLE_PUBLIC_ED_KEY_TESTNET`은 stable release에서 flavor별 앱 `Info.plist`에 주입되는 공개 Ed25519 키입니다. stable 앱은 `SUVerifyUpdateBeforeExtraction`과 `SURequireSignedFeed`도 켜서 update archive를 extraction 전에 검증하고 appcast/release notes signing을 요구합니다.
- `SPARKLE_PRIVATE_ED_KEY_MAINNET` / `SPARKLE_PRIVATE_ED_KEY_TESTNET`은 stable release에서 flavor별 appcast/delta, signed feed, release notes 서명에 쓰는 비밀 Ed25519 키입니다.
- mainnet Sparkle feed asset은 `appcast.xml`, testnet Sparkle feed asset은 `appcast-testnet.xml`입니다.
- `release_notes/v1.2.3.md`가 있으면 stable `release/v1.2.3`의 Sparkle release notes로 사용합니다. 없으면 GitHub Release 링크만 포함한 기본 notes를 생성합니다.
- Sparkle delta 입력으로 쓰는 이전 release는 같은 flavor의 고정 DMG(`Vizor-macos.dmg` 또는 `Vizor-Testnet-macos.dmg`)와 같은 flavor의 appcast asset을 둘 다 가진 stable release여야 합니다. fastlane은 이전 appcast XML이 그 release의 고정 DMG enclosure를 가리키는지도 확인하며, 조건을 만족하지 않으면 delta만 생략하고 현재 full DMG update는 계속 생성합니다.
- 현재 stable release의 appcast는 업로드 전에 현재 태그의 고정 DMG URL과 같은 basename의 release notes markdown(`Vizor-macos.md` 또는 `Vizor-Testnet-macos.md`) URL을 가리키고, appcast와 release notes가 Sparkle EdDSA로 검증되는지 확인합니다.
- Sparkle이 앱 이름에서 생성하는 delta 파일명은 GitHub Release asset 규칙에 맞게 정규화합니다. 예를 들어 testnet 앱 이름 `Vizor Testnet`에서 나온 `Vizor Testnet46-45.delta`는 업로드 전에 `Vizor.Testnet46-45.delta`로 바꾸고 appcast URL도 같이 갱신합니다. 이 후 appcast XML을 다시 서명하므로 서명 이후에는 appcast나 release notes를 수정하지 않아야 합니다.
- 산출물은 repo root의 `dist/macos` 아래에 생성됩니다.
