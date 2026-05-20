# Linux AppImage fastlane

GitHub Actions 기준 Linux AppImage 외부 배포용 fastlane 설정입니다.

실행:

```bash
bundle exec fastlane linux build
bundle exec fastlane linux package
bundle exec fastlane linux release
```

`release` lane 순서:

1. mainnet/testnet flavor별 Linux Flutter bundle 생성
2. flavor별 AppDir 생성
3. flavor별 AppImage 생성
4. flavor별 embedded GPG signature, detached `.asc`, `.sha256`, `.zsync` 생성
5. GitHub Release에 모든 flavor asset 업로드

기본 release flavor는 `mainnet,testnet`입니다. 단일 flavor만 빌드하려면:

```bash
VIZOR_LINUX_FLAVOR=mainnet bundle exec fastlane linux package
VIZOR_LINUX_FLAVOR=testnet bundle exec fastlane linux package
VIZOR_LINUX_FLAVORS=mainnet,testnet bundle exec fastlane linux release
```

## Required environment variables

- `GITHUB_TOKEN`
- `RELEASE_REPOSITORY`
- `RELEASE_COMMITISH`
- `RELEASE_BUILD_NUMBER`
- `LINUX_APPIMAGE_GPG_PRIVATE_KEY`
- `LINUX_APPIMAGE_GPG_KEY_ID`

태그 기반 워크플로우가 아니면 아래도 필요합니다.

- `RELEASE_TAG`

## Optional environment variables

- `RELEASE_NAME`
- `GITHUB_RELEASE_PRERELEASE`
- `VIZOR_LINUX_FLAVOR`
- `VIZOR_LINUX_FLAVORS`
- `VIZOR_LINUX_ARCH`
- `FVM_BIN`
- `LINUXDEPLOY_BIN`
- `APPIMAGETOOL_BIN`
- `LINUX_APPIMAGE_GPG_PASSPHRASE`

## Asset names

mainnet:

- `Vizor-linux-x86_64.AppImage`
- `Vizor-linux-x86_64.AppImage.zsync`
- `Vizor-linux-x86_64.AppImage.sha256`
- `Vizor-linux-x86_64.AppImage.asc`

testnet:

- `Vizor-Testnet-linux-x86_64.AppImage`
- `Vizor-Testnet-linux-x86_64.AppImage.zsync`
- `Vizor-Testnet-linux-x86_64.AppImage.sha256`
- `Vizor-Testnet-linux-x86_64.AppImage.asc`

The AppImage update information uses GitHub Releases `latest` zsync entries so
stable AppImages can be updated by external AppImage update tools. App-internal
update prompts are intentionally out of scope for this lane.
