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
4. flavor별 embedded GPG signature, detached `.asc`, `.sha256` 생성
5. 산출물을 `dist/linux` 아래에 준비

GitHub Release 생성, asset 업로드, multi-arch update feed 생성, draft
publish는 deployment repo의 `Release` workflow가 담당합니다.

기본 release flavor는 `mainnet,testnet`입니다. 단일 flavor만 빌드하려면:

```bash
VIZOR_LINUX_FLAVOR=mainnet bundle exec fastlane linux package
VIZOR_LINUX_FLAVOR=testnet bundle exec fastlane linux package
VIZOR_LINUX_FLAVORS=mainnet,testnet bundle exec fastlane linux release
```

## Required environment variables

- `RELEASE_REPOSITORY`
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
- `Vizor-linux-aarch64.AppImage`
- `Vizor-linux-aarch64.AppImage.zsync`
- `Vizor-linux-aarch64.AppImage.sha256`
- `Vizor-linux-aarch64.AppImage.asc`

testnet:

- `Vizor-Testnet-linux-x86_64.AppImage`
- `Vizor-Testnet-linux-x86_64.AppImage.zsync`
- `Vizor-Testnet-linux-x86_64.AppImage.sha256`
- `Vizor-Testnet-linux-x86_64.AppImage.asc`
- `Vizor-Testnet-linux-aarch64.AppImage`
- `Vizor-Testnet-linux-aarch64.AppImage.zsync`
- `Vizor-Testnet-linux-aarch64.AppImage.sha256`
- `Vizor-Testnet-linux-aarch64.AppImage.asc`

Stable AppImage update information uses GitHub Releases `latest` zsync entries
so stable AppImages can be updated by external AppImage update tools. Each
Linux CI job builds one native architecture by setting `VIZOR_LINUX_ARCH` to
`x86_64` or `aarch64`. Prerelease builds do not embed update information and do
not generate zsync assets.
