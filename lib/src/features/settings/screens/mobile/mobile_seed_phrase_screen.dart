import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/platform/screenshot_observer.dart';
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
  const MobileSeedPhraseScreen({this.screenshotStream, super.key});

  /// Test seam — production listens to the platform screenshot events.
  @visibleForTesting
  final Stream<void>? screenshotStream;

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

  @override
  void initState() {
    super.initState();
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
    _mnemonic = null;
    super.dispose();
  }

  // ── Confirm access gate ────────────────────────────────────────────

  Future<void> _tryBiometricGate() async {
    if (_checking || _stage != _SeedStage.confirmAccess) return;
    final biometric = await ref.read(biometricUnlockProvider.future);
    if (!mounted || !biometric.usable) return;
    final passcode = await ref
        .read(biometricUnlockProvider.notifier)
        .readPasscode(reason: 'Confirm access to your secret passphrase');
    if (!mounted || passcode == null) return;
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
    if (mnemonic != null && account != null) {
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
        builder: (_) => const _ScreenshotWarningSheet(),
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
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: _stage == _SeedStage.confirmAccess
                    ? 'Confirm Access'
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
    );
  }

  Widget _buildGate(AppColors colors) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.s),
        Text(
          'Enter your passcode',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        // Dots + error centred in the space above the keypad.
        Expanded(
          child: PasscodePromptField(
            length: kMobilePasscodeLength,
            filled: _entry.length,
            error: _gateError,
          ),
        ),
        PasscodeNumpad(
          onDigit: _onDigit,
          onBackspace: _onBackspace,
          canDelete: _entry.isNotEmpty,
          enabled: !_checking,
        ),
        const SizedBox(height: AppSpacing.md),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Secret Passphrase',
                        style: AppTypography.headlineSmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    _CopyChip(
                      key: const ValueKey('mobile_seed_copy'),
                      label: 'Copy',
                      onTap: () => _copy(_mnemonic, 'Secret passphrase copied'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _LightWordGrid(words: words),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MobileSurfaceCard(
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
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xxs,
          ),
          decoration: ShapeDecoration(
            color: colors.background.inverse,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
    );
  }
}

/// 3-column numbered word grid on the light surface card (unlike the
/// onboarding SeedCard's dark treatment).
class _LightWordGrid extends StatelessWidget {
  const _LightWordGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = (words.length / 3).ceil();
    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: row * 3 + col < words.length
                      ? Row(
                          children: [
                            Text(
                              (row * 3 + col + 1).toString().padLeft(2, '0'),
                              style: AppTypography.codeSmall.copyWith(
                                color: colors.text.muted,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Text(
                                words[row * 3 + col],
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ],
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
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Semantics(
              button: true,
              label: 'Copy $label',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCopy,
                child: SizedBox(
                  width: 28,
                  height: 44,
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

/// Screenshot warning — Figma `If they try to screenshot` (4494:91643).
class _ScreenshotWarningSheet extends StatelessWidget {
  const _ScreenshotWarningSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppIcon(AppIcons.eyeClosed, size: 28, color: colors.text.destructive),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "Don't take screenshots of\nyour Secret Passphrase",
            textAlign: TextAlign.center,
            style: AppTypography.displaySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text.rich(
            TextSpan(
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
              children: const [
                TextSpan(
                  text: 'Screenshots are not reliable. ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text:
                      'Anyone who has access to your phone or your photo '
                      'library will be able to see your Secret Passphrase. '
                      'Write down your Phrase on a piece of paper instead.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_seed_screenshot_ack'),
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }
}
