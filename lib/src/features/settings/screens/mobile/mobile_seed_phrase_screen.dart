import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icon, Icons, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/platform/screenshot_observer.dart';
import '../../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../../services/biometric_unlock.dart';
import '../../../onboarding/mobile/forgot_passcode_sheet.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';

enum _SeedStage { confirmAccess, reveal }

/// Settings → Secret Passphrase — Figma `Confirm Access` / `Secret` /
/// `If they try to screenshot` (4494:87180 / 4494:88388 / 4494:91643).
/// Mirrors the desktop seed-phrase screen's logic: passcode
/// re-confirmation gates the reveal, the mnemonic stays only in screen
/// state, and the wallet birthday loads best-effort alongside it.
class MobileSeedPhraseScreen extends ConsumerStatefulWidget {
  const MobileSeedPhraseScreen({
    this.screenshotStream,
    this.privacyOverlayController,
    this.loadBirthday = true,
    super.key,
  });

  /// Test seam — production listens to the platform screenshot events.
  @visibleForTesting
  final Stream<void>? screenshotStream;

  @visibleForTesting
  final SensitivePrivacyOverlayController? privacyOverlayController;

  @visibleForTesting
  final bool loadBirthday;

  @override
  ConsumerState<MobileSeedPhraseScreen> createState() =>
      _MobileSeedPhraseScreenState();
}

class _MobileSeedPhraseScreenState
    extends ConsumerState<MobileSeedPhraseScreen> {
  var _stage = _SeedStage.confirmAccess;
  var _entry = '';
  var _checking = false;
  String? _gateError;

  String? _mnemonic;
  String? _revealError;
  int? _birthdayHeight;
  int? _birthdayBlockTime;
  bool _birthdayLoading = false;

  StreamSubscription<void>? _screenshotSub;
  bool _screenshotSheetShowing = false;

  // Owned in production (the test seam injects its own) so the biometric gate
  // can suppress the privacy shield for the duration of the prompt.
  late final bool _ownsPrivacyController;
  late final SensitivePrivacyOverlayController _privacyController;

  @override
  void initState() {
    super.initState();
    _ownsPrivacyController = widget.privacyOverlayController == null;
    _privacyController =
        widget.privacyOverlayController ??
        SensitivePrivacyEnvironmentController();
    _screenshotSub = (widget.screenshotStream ?? screenshotEvents()).listen(
      (_) => _onScreenshot(),
    );
    // Figma `FaceID Overlay`: with biometric unlock on, the gate offers
    // the prompt first; cancel falls back to the passcode numpad.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryBiometricGate());
    });
  }

  @override
  void dispose() {
    _screenshotSub?.cancel();
    if (_ownsPrivacyController) _privacyController.dispose();
    _mnemonic = null;
    super.dispose();
  }

  // ── Confirm access gate ────────────────────────────────────────────

  Future<void> _tryBiometricGate() async {
    if (_checking || _stage != _SeedStage.confirmAccess) return;
    final biometric = await ref.read(biometricUnlockProvider.future);
    if (!mounted || !biometric.usable) return;
    final wasEnabled = biometric.enabled;
    // The biometric sheet pushes the app to `inactive`; suppress the privacy
    // shield for its duration so the phrase revealed on success doesn't flash
    // the blur cover during the inactive→resumed transition. The environment
    // controller releases the suppression on resume.
    _privacyController.beginAuthPrompt();
    String? readResult;
    try {
      readResult = await ref
          .read(biometricUnlockProvider.notifier)
          .readPasscode(reason: 'Confirm access to your secret passphrase');
    } finally {
      _privacyController.endAuthPrompt();
    }
    if (!mounted) return;
    final passcode = readResult;
    if (passcode == null) {
      final now = ref.read(biometricUnlockProvider).value;
      if (wasEnabled && now != null && !now.enabled) {
        setState(() {
          _entry = '';
          _gateError = 'Biometrics changed. Enter your passcode.';
        });
      }
      return;
    }
    setState(() {
      _entry = passcode;
      _gateError = null;
    });
    await _confirmPasscode();
  }

  void _onDigit(int digit) {
    if (_checking || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _gateError = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      unawaited(_confirmPasscode());
    }
  }

  void _onBackspace() {
    if (_checking || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _confirmPasscode() async {
    setState(() => _checking = true);
    try {
      final valid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_entry);
      if (!mounted) return;
      if (!valid) {
        unawaited(AppHaptics.error());
        setState(() {
          _entry = '';
          _checking = false;
          _gateError = 'Incorrect passcode';
        });
        return;
      }
      await _reveal();
    } catch (e, st) {
      log('MobileSeedPhrase: passcode confirm failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _entry = '';
        _checking = false;
        _gateError = "Couldn't verify the passcode. Try again.";
      });
    }
  }

  Future<void> _showForgotPasscodeSheet() async {
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeSheet(),
    );
    if (confirmed != true || !mounted) return;
    final lastWarningConfirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeLastWarningSheet(),
    );
    if (lastWarningConfirmed != true || !mounted) return;
    await _resetWallet();
  }

  Future<void> _resetWallet() async {
    setState(() => _checking = true);
    final router = GoRouter.of(context);
    try {
      await resetWalletForForgottenPasscode(ref);
    } catch (e, st) {
      log('MobileSeedPhrase._resetWallet: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _entry = '';
        _gateError = "Couldn't reset the app. Please try again.";
      });
      return;
    }
    router.go('/welcome');
  }

  // ── Reveal ─────────────────────────────────────────────────────────

  Future<void> _reveal() async {
    final account = ref.read(accountProvider).value?.activeAccount;
    String? revealError;
    String? mnemonic;
    if (account == null) {
      revealError = 'No active account is selected.';
    } else if (account.isHardware) {
      revealError = 'Secret passphrase is not available for hardware accounts.';
    } else {
      mnemonic = await ref
          .read(accountProvider.notifier)
          .getMnemonicForAccount(account.uuid);
      if (mnemonic == null || mnemonic.isEmpty) {
        revealError = 'Secret passphrase is not available for this account.';
      }
    }
    if (!mounted) return;
    setState(() {
      _mnemonic = mnemonic;
      _revealError = revealError;
      _stage = _SeedStage.reveal;
      _checking = false;
      _birthdayLoading = mnemonic != null;
    });
    if (mnemonic != null && account != null && widget.loadBirthday) {
      unawaited(_loadBirthday(account.uuid));
    }
  }

  Future<void> _loadBirthday(String accountUuid) async {
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final height = await rust_sync.getExportBirthdayHeight(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      );
      if (!mounted) return;
      setState(() => _birthdayHeight = height.toInt());

      final blockTime = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'birthday block time',
            action: (endpoint) => rust_sync.getBlockTime(
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              height: height,
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _birthdayBlockTime = blockTime.toInt() > 0 ? blockTime.toInt() : null;
        _birthdayLoading = false;
      });
    } catch (e, st) {
      log('MobileSeedPhrase: birthday load failed: $e\n$st');
      if (!mounted) return;
      setState(() => _birthdayLoading = false);
    }
  }

  Future<void> _copy(String? text, String toast) async {
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppToast(context, toast);
  }

  // ── Screenshot warning ─────────────────────────────────────────────

  Future<void> _onScreenshot() async {
    if (_stage != _SeedStage.reveal ||
        _mnemonic == null ||
        _screenshotSheetShowing ||
        !mounted) {
      return;
    }
    _screenshotSheetShowing = true;
    try {
      await showAppMobileSheet<void>(
        context: context,
        builder: (_) => const MobileSeedScreenshotWarningSheet(),
      );
    } finally {
      _screenshotSheetShowing = false;
    }
  }

  static String _formatBirthdayDate(int blockTimeSeconds) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final date = DateTime.fromMillisecondsSinceEpoch(
      blockTimeSeconds * 1000,
    ).toLocal();
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SensitivePrivacyOverlay(
          sensitiveContentVisible:
              _stage == _SeedStage.reveal && _mnemonic != null,
          controller: _privacyController,
          child: SafeArea(
            child: Column(
              children: [
                MobileTopNav.back(
                  title: _stage == _SeedStage.confirmAccess
                      ? ''
                      : 'Secret Passphrase',
                  onBack: () => context.pop(),
                ),
                Expanded(
                  child: switch (_stage) {
                    _SeedStage.confirmAccess => _buildGate(colors),
                    _SeedStage.reveal => _buildReveal(colors),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGate(AppColors colors) {
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final showBiometric = !_checking && biometric.usable;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter Passcode',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Confirm your access',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: kPasscodePromptDigitsHeight,
                  child: PasscodePromptField(
                    length: kMobilePasscodeLength,
                    filled: _entry.length,
                    error: _gateError,
                    minGap: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
        PasscodeNumpad(
          onDigit: _onDigit,
          onBackspace: _onBackspace,
          canDelete: _entry.isNotEmpty,
          onHelp: _checking ? null : _showForgotPasscodeSheet,
          enabled: !_checking,
        ),
        if (showBiometric) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            key: const ValueKey('mobile_seed_phrase_biometric_footer'),
            height: 36,
            child: Center(
              child: PasscodeBiometricButton(
                label: biometric.availability.kind == BiometricKind.face
                    ? 'Sign in with Face ID'
                    : 'Sign in with biometrics',
                icon: biometric.availability.kind == BiometricKind.face
                    ? const Center(child: AppIcon(AppIcons.faceId, size: 13.5))
                    : const Icon(Icons.fingerprint, size: 16),
                onPressed: () => unawaited(_tryBiometricGate()),
              ),
            ),
          ),
        ],
        if (!showBiometric) const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _buildReveal(AppColors colors) {
    final words = _mnemonic?.split(' ') ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      children: [
        if (_revealError != null)
          MobileSurfaceCard(
            child: Text(
              _revealError!,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.destructive,
              ),
            ),
          )
        else ...[
          MobileSurfaceCard(
            cornerRadius: AppRadii.xLarge,
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.base,
                    AppSpacing.sm,
                    AppSpacing.base,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Secret Passphrase',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _LightWordGrid(words: words),
                    ],
                  ),
                ),
                Positioned(
                  top: AppSpacing.s,
                  right: AppSpacing.s,
                  child: _CopyChip(
                    key: const ValueKey('mobile_seed_copy'),
                    label: 'Copy',
                    onTap: () => _copy(_mnemonic, 'Secret passphrase copied'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MobileSurfaceCard(
            cornerRadius: AppRadii.large,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.base,
              AppSpacing.sm,
              AppSpacing.base,
            ),
            child: Column(
              children: [
                _BirthdayRow(
                  label: 'Birthday date',
                  value: _birthdayBlockTime != null
                      ? _formatBirthdayDate(_birthdayBlockTime!)
                      : _birthdayLoading
                      ? '…'
                      : '—',
                  onCopy: _birthdayBlockTime == null
                      ? null
                      : () => _copy(
                          _formatBirthdayDate(_birthdayBlockTime!),
                          'Birthday date copied',
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _BirthdayRow(
                  label: 'Birthday block height',
                  value:
                      _birthdayHeight?.toString() ??
                      (_birthdayLoading ? '…' : '—'),
                  onCopy: _birthdayHeight == null
                      ? null
                      : () =>
                            _copy('$_birthdayHeight', 'Birthday height copied'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Dark "Copy ⧉" chip in the card header.
class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Copy secret passphrase',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96, minHeight: 36),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: AppSpacing.xs,
            ),
            decoration: ShapeDecoration(
              color: colors.background.inverse,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.inverse,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(
                  AppIcons.copy,
                  size: AppIconSize.medium,
                  color: colors.text.inverse,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed 3-column numbered word grid on the light surface card (unlike the
/// onboarding SeedCard's dark treatment).
class _LightWordGrid extends StatelessWidget {
  const _LightWordGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (var i = 0; i < words.length; i++)
          SizedBox(
            width: 90,
            height: 32,
            child: Row(
              children: [
                Text(
                  (i + 1).toString().padLeft(2, '0'),
                  style: AppTypography.codeSmall.copyWith(
                    color: colors.text.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    words[i],
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BirthdayRow extends StatelessWidget {
  const _BirthdayRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.text.accent,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.accent,
            ),
          ),
          if (onCopy != null) ...[
            Semantics(
              button: true,
              label: 'Copy $label',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCopy,
                child: SizedBox(
                  width: 24,
                  height: 36,
                  child: Center(
                    child: AppIcon(
                      AppIcons.copy,
                      size: AppIconSize.medium,
                      color: colors.icon.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Screenshot warning — Figma `If they try to screenshot` (4494:92098).
class MobileSeedScreenshotWarningSheet extends StatelessWidget {
  const MobileSeedScreenshotWarningSheet({super.key});

  static const _iconSize = 30.0;
  static const _titleMaxWidth = 253.0;
  static const _textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  static const _titleStyle = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontSize: 24,
    height: 28 / 24,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.enable('case')],
  );

  static const _buttonLabelStyle = AppTypography.labelLarge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('mobile_seed_screenshot_sheet'),
      title: '',
      onClose: () => Navigator.of(context).pop(),
      showTitle: false,
      showClose: false,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              AppIcon(
                key: const ValueKey('mobile_seed_screenshot_icon'),
                AppIcons.eyeClosed,
                size: _iconSize,
                color: colors.text.destructive,
              ),
              const SizedBox(height: AppSpacing.s),
              LayoutBuilder(
                builder: (context, constraints) {
                  final titleWidth = constraints.maxWidth.isFinite
                      ? math.min(_titleMaxWidth, constraints.maxWidth)
                      : _titleMaxWidth;
                  return SizedBox(
                    width: titleWidth,
                    child: Text(
                      key: const ValueKey('mobile_seed_screenshot_title'),
                      'Don’t take screenshots of your Secret Passphrase',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      textHeightBehavior: _textHeightBehavior,
                      style: _titleStyle.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            key: const ValueKey('mobile_seed_screenshot_body'),
            TextSpan(
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
              children: const [
                TextSpan(
                  text: 'Screenshots are not reliable',
                  style: AppTypography.bodyMediumStrong,
                ),
                TextSpan(
                  text:
                      '. Anyone who has access to your phone or your photo '
                      'library will be able to see your Secret Passphrase. '
                      'Write down your Phrase on a '
                      'piece of paper instead.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
            softWrap: true,
            textHeightBehavior: _textHeightBehavior,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_seed_screenshot_ack'),
            expand: true,
            height: AppButtonSizing.largeHeight,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I understand', style: _buttonLabelStyle),
          ),
        ],
      ),
    );
  }
}
