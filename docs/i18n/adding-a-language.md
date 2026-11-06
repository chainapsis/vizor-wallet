# Adding a language

1. Add an entry to `AppLanguage` in `lib/src/core/l10n/app_language.dart`
   with `released: false`, its tag and its name in its own script.
2. Add `lib/l10n/app_<tag>.arb` with `"@@locale": "<tag>"` and translations.
   Keys stay sorted.
3. Add the language to `lib/l10n/glossary.yaml` (a column per term) and write
   `docs/i18n/style-<tag>.md`.
4. Add the language to `nativeLanguageSources` in
   `tool/l10n/native_strings.dart` and run
   `fvm dart run tool/l10n/native_strings.dart`. iOS, Android and macOS then
   show their own copy (notifications, background-task captions, system
   prompts, the macOS update alerts) in it. See [Native copy](#native-copy).
5. Check fonts: the language's script needs a system font on every platform.
   A CJK language also gets its own list in `fontFamilyFallbackFor`
   (`lib/src/core/l10n/locale_typography.dart`).
6. Review it on screen with `--dart-define=VIZOR_I18N_PREVIEW=true`.
7. Set `released: true` once every message is translated and a native
   reviewer approved the `[security]` strings. The gate test then requires
   complete coverage.
8. Add the [native resources at release](#native-resources-at-release).

Right-to-left languages also need a layout audit first: most layouts use
left/right geometry (`EdgeInsets.fromLTRB`, `left:`) instead of directional
variants.

## Native copy

Text that Swift or Kotlin draws outside Flutter lives in the ARB files under
`native*` keys, translated like every other key.
`tool/l10n/native_strings.dart` copies them into
`ios/Runner/NativeStrings.swift` and
`android/app/src/main/kotlin/com/keplr/vizor/NativeStrings.kt`. The macOS
target compiles the iOS Swift file too, for its Tor update alerts. The gate
test fails when those files are stale. Native strings take plain `{name}`
placeholders only, no ICU plurals or selects.

Native code follows the app language, not the device language: Dart sends the
language the UI shows over `com.zcash.wallet/native_strings`, and native code
stores it for background work. Until Dart sends one, native code uses English.
A build without `VIZOR_I18N_PREVIEW` shows English only, so it sends `en`.

The OS still draws its own buttons (Cancel, the passcode fallback) in the
device language, so a system prompt can mix the two.

## Native resources at release

Resources that the OS reads before the app runs follow the device language and
change what the stores list, so they are added only when a language ships.
Adding them earlier would show Korean or Chinese permission prompts and store
listings in an English-only build.
`test/l10n/native_locale_declarations_test.dart` fails when `knownRegions`, the
`lproj` folders or Android `localeConfig` disagree with `released`.

### iOS (`ios/Runner`)

1. Add `ko` and `zh-Hans` to `knownRegions` in
   `ios/Runner.xcodeproj/project.pbxproj`.
2. Create `ko.lproj/InfoPlist.strings` and `zh-Hans.lproj/InfoPlist.strings`
   and add them to the Runner target as a variant group. The App Store lists
   the languages from these folders, and iOS then shows a per-app Language
   setting whose choice Flutter receives as the device locale.
3. Translate the usage descriptions in `ios/Runner/Info.plist`. Drafts:

| Key | English | Korean | Simplified Chinese |
| --- | --- | --- | --- |
| `NSCameraUsageDescription` | Vizor uses the camera to scan addresses, gift cards, and Keystone QR codes. | Vizor는 주소, 기프트 카드, Keystone QR 코드를 스캔하는 데 카메라를 사용해요. | Vizor 使用相机扫描地址、礼品卡和 Keystone 二维码。 |
| `NSBluetoothAlwaysUsageDescription` | Vizor uses Bluetooth to connect to your Ledger device. | Vizor는 Ledger 기기에 연결하는 데 Bluetooth를 사용해요. | Vizor 使用蓝牙连接你的 Ledger 设备。 |
| `NSFaceIDUsageDescription` | Vizor uses Face ID to unlock your wallet and confirm sensitive actions. | Vizor는 지갑 잠금을 해제하고 중요한 작업을 확인하는 데 Face ID를 사용해요. | Vizor 使用面容 ID 解锁钱包并确认敏感操作。 |

`CFBundleDisplayName` and `CFBundleName` stay `Vizor`. Notification
permission has no usage string on iOS.

### macOS (`macos/Runner`)

Same steps for the macOS target. Its usage descriptions differ from iOS:

| Key | English | Korean | Simplified Chinese |
| --- | --- | --- | --- |
| `NSCameraUsageDescription` | Vizor uses the camera to scan Keystone QR codes. | Vizor는 Keystone QR 코드를 스캔하는 데 카메라를 사용해요. | Vizor 使用相机扫描 Keystone 二维码。 |
| `NSBluetoothAlwaysUsageDescription` | Vizor uses Bluetooth to connect to your Ledger hardware wallet. | Vizor는 Ledger 하드웨어 지갑에 연결하는 데 Bluetooth를 사용해요. | Vizor 使用蓝牙连接你的 Ledger 硬件钱包。 |

### Android (`android/app`)

1. Add `res/xml/locales_config.xml` listing `en`, `ko` and `zh-CN`, and set
   `android:localeConfig="@xml/locales_config"` on `<application>`. Android
   13 and later then offer a per-app language in system settings.
2. `res/values` holds no strings today: the app label stays `Vizor`, Android
   draws permission dialogs with its own text, and native copy comes from
   `NativeStrings.kt`. Add `values-ko` and `values-zh-rCN` only when a
   translatable resource string appears.
3. Play Console lists store languages from the store listing translations,
   not from the APK.
