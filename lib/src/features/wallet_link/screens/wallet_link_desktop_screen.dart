import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, LinearProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/app_security_provider.dart';
import '../../settings/widgets/confirm_access_card.dart';
import '../../settings/widgets/settings_pane_backdrop.dart';
import '../../../core/widgets/dot_qr_shape.dart';
import '../models/wallet_link_models.dart';
import '../providers/wallet_link_provider.dart';

const _walletLinkContentWidth = 420.0;
const _walletLinkHorizontalInset = AppSpacing.s;
const _walletLinkBodyWidth = 258.0;
const _walletLinkResultWidth = 300.0;
const _walletLinkExpiredBodyWidth = 270.0;
const _walletLinkActionSlotHeight = 73.0;

class WalletLinkDesktopScreen extends ConsumerStatefulWidget {
  const WalletLinkDesktopScreen({this.previewState, super.key});

  final WalletLinkState? previewState;

  @override
  ConsumerState<WalletLinkDesktopScreen> createState() =>
      _WalletLinkDesktopScreenState();
}

class _WalletLinkDesktopScreenState
    extends ConsumerState<WalletLinkDesktopScreen> {
  final _passwordController = TextEditingController();
  bool _accessConfirmed = false;
  bool _isSubmittingPassword = false;
  String? _passwordError;

  String? get _passwordPolicyMessage =>
      validateWalletPassword(_passwordController.text);

  bool get _canSubmitPassword =>
      !_isSubmittingPassword && isWalletPasswordValid(_passwordController.text);

  bool get _requiresAccessConfirmation =>
      widget.previewState == null && !_accessConfirmed;

  @override
  void dispose() {
    _clearPasswordGate();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearPasswordGate() {
    _passwordController.clear();
    _isSubmittingPassword = false;
    _passwordError = null;
  }

  void _handlePasswordChanged() {
    if (_passwordError == null) {
      setState(() {});
      return;
    }
    setState(() {
      _passwordError = null;
    });
  }

  Future<void> _submitPassword() async {
    final policyError = _passwordPolicyMessage;
    if (_isSubmittingPassword) return;
    if (!isWalletPasswordValid(_passwordController.text)) {
      if (policyError == null) return;
      setState(() {
        _passwordError = policyError;
      });
      return;
    }

    setState(() {
      _isSubmittingPassword = true;
      _passwordError = null;
    });

    try {
      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_passwordController.text);
      if (!mounted) return;
      if (!isValid) {
        setState(() {
          _passwordError = 'Incorrect password. Please try again.';
          _isSubmittingPassword = false;
        });
        return;
      }

      setState(() {
        _accessConfirmed = true;
        _clearPasswordGate();
      });
    } catch (e, st) {
      log('WalletLinkDesktopScreen._submitPassword: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _passwordError = "Couldn't check your password. Please try again.";
        _isSubmittingPassword = false;
      });
    }
  }

  void _handleGateBack() {
    _clearPasswordGate();
    context.go('/settings');
  }

  @override
  Widget build(BuildContext context) {
    if (_requiresAccessConfirmation) {
      return _WalletLinkConfirmAccessScreen(
        controller: _passwordController,
        errorText: _passwordError,
        isSubmitting: _isSubmittingPassword,
        canSubmit: _canSubmitPassword,
        onChanged: _handlePasswordChanged,
        onSubmit: _submitPassword,
        onBack: _handleGateBack,
      );
    }

    final preview = widget.previewState;
    final WalletLinkState state;
    final WalletLinkController? controller;
    if (preview == null) {
      state = ref.watch(walletLinkControllerProvider);
      controller = ref.read(walletLinkControllerProvider.notifier);
    } else {
      state = preview;
      controller = null;
    }
    final VoidCallback? onStart;
    final VoidCallback? onRegenerate;
    if (controller == null) {
      onStart = preview == null ? null : () {};
      onRegenerate = preview == null ? null : () {};
    } else {
      final activeController = controller;
      onStart = () => unawaited(activeController.start());
      onRegenerate = () => unawaited(activeController.regenerate());
    }

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneScrollScaffold(
          toolbar: AppPaneToolbar(
            leading: AppBackLink(
              label: 'Settings',
              minWidth: 60,
              onTap: () => context.go('/settings'),
            ),
          ),
          child: _WalletLinkPane(
            state: state,
            onStart: onStart,
            onRegenerate: onRegenerate,
            onContinue: () => context.go('/settings'),
          ),
        ),
      ),
    );
  }
}

class _WalletLinkConfirmAccessScreen extends StatelessWidget {
  const _WalletLinkConfirmAccessScreen({
    required this.controller,
    required this.errorText,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: const SettingsPaneBackdrop(art: SettingsBackdropArt.castle),
      sidebar: const AppMainSidebar(),
      pane: _WalletLinkConfirmAccessPane(
        onBack: onBack,
        child: Center(
          child: ConfirmAccessCard(
            subtitle: 'To link Vizor Mobile.',
            controller: controller,
            errorText: errorText,
            isSubmitting: isSubmitting,
            canSubmit: canSubmit,
            onChanged: onChanged,
            onSubmit: onSubmit,
          ),
        ),
      ),
    );
  }
}

class _WalletLinkConfirmAccessPane extends StatelessWidget {
  const _WalletLinkConfirmAccessPane({
    required this.onBack,
    required this.child,
  });

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPaneToolbar(
            leading: AppBackLink(
              label: 'Settings',
              minWidth: 60,
              onTap: onBack,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletLinkPane extends StatelessWidget {
  const _WalletLinkPane({
    required this.state,
    required this.onStart,
    required this.onRegenerate,
    required this.onContinue,
  });

  final WalletLinkState state;
  final VoidCallback? onStart;
  final VoidCallback? onRegenerate;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = switch (state.phase) {
      WalletLinkPhase.ready => _ReadyContent(
        state: state,
        onRegenerate: onRegenerate,
      ),
      WalletLinkPhase.linked => _LinkedContent(
        state: state,
        onContinue: onContinue,
      ),
      WalletLinkPhase.expired => _ExpiredContent(onRegenerate: onRegenerate),
      WalletLinkPhase.error => _ErrorContent(
        message: state.errorMessage ?? 'Could not prepare the mobile link.',
        onRetry: onRegenerate ?? onStart,
      ),
      WalletLinkPhase.preparing || WalletLinkPhase.idle => _InitialContent(
        preparing: state.isPreparing,
        onStart: onStart,
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = math.max(0.0, constraints.minHeight);
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _walletLinkContentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _walletLinkHorizontalInset,
                ),
                child: DefaultTextStyle(
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.primary,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InitialContent extends StatelessWidget {
  const _InitialContent({required this.preparing, required this.onStart});

  final bool preparing;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return _ContentColumn(
      title: 'Link Vizor Mobile',
      body:
          'Connect this wallet to your Vizor mobile app by scanning a one-time QR code.',
      visual: const _EncryptedPlaceholder(),
      action: AppButton(
        onPressed: preparing ? null : onStart,
        size: AppButtonSize.mediumLarge,
        leading: preparing
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : null,
        child: Text(preparing ? 'Preparing' : 'Start linking'),
      ),
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent({required this.state, required this.onRegenerate});

  final WalletLinkState state;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return _ContentColumn(
      title: 'Scan with Vizor mobile',
      body: 'Open Vizor on your phone → Add a wallet → Import from desktop',
      visual: _QrTransferCard(
        qrPayload: state.qrPayload ?? '',
        remaining: state.remaining,
      ),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            onPressed: onRegenerate,
            size: AppButtonSize.mediumLarge,
            leading: const AppIcon(AppIcons.renew),
            child: const Text('Regenerate'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Expires in ${_formatRemaining(state.remaining)}',
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedContent extends StatelessWidget {
  const _LinkedContent({required this.state, required this.onContinue});

  final WalletLinkState state;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _ResultContentColumn(
      title: 'Vizor Mobile linked successfully',
      body: _linkedBody(state),
      titleMaxWidth: 264,
      bodyMaxWidth: 212,
      visual: const SizedBox(
        width: 300,
        height: 200,
        child: _Illustration(
          asset: 'assets/illustrations/wallet_link_success.png',
          width: 158,
          height: 200,
        ),
      ),
      action: AppButton(
        onPressed: onContinue,
        size: AppButtonSize.mediumLarge,
        variant: AppButtonVariant.secondary,
        child: const Text('Continue'),
      ),
    );
  }

  String _linkedBody(WalletLinkState state) {
    if (!state.actualImportCounts) {
      return 'Vizor Mobile was linked to this wallet.';
    }
    final accountLabel = state.accountCount == 1 ? 'account' : 'accounts';
    final contactLabel = state.contactCount == 1 ? 'contact' : 'contacts';
    return '${state.accountCount} $accountLabel and '
        '${state.contactCount} $contactLabel were imported on mobile.';
  }
}

class _ExpiredContent extends StatelessWidget {
  const _ExpiredContent({required this.onRegenerate});

  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return _ResultContentColumn(
      title: 'Time’s up',
      body:
          'For your security the link is only valid for a minute. Generate a fresh code and scan it again.',
      bodyMaxWidth: _walletLinkExpiredBodyWidth,
      visual: const SizedBox(
        width: 300,
        height: 200,
        child: _Illustration(
          asset: 'assets/illustrations/wallet_link_expired.png',
          width: 160,
          height: 200,
        ),
      ),
      action: AppButton(
        onPressed: onRegenerate,
        size: AppButtonSize.mediumLarge,
        leading: const AppIcon(AppIcons.renew),
        child: const Text('Generate new code'),
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _ContentColumn(
      title: 'Link unavailable',
      body: message,
      visual: const _StatusIcon(iconName: AppIcons.warning),
      action: AppButton(
        onPressed: onRetry,
        size: AppButtonSize.mediumLarge,
        child: const Text('Try again'),
      ),
    );
  }
}

class _ContentColumn extends StatelessWidget {
  const _ContentColumn({
    required this.title,
    required this.body,
    required this.visual,
    required this.action,
  });

  final String title;
  final String body;
  final Widget visual;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _walletLinkBodyWidth),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        visual,
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _walletLinkActionSlotHeight,
          child: Align(alignment: Alignment.topCenter, child: action),
        ),
      ],
    );
  }
}

class _ResultContentColumn extends StatelessWidget {
  const _ResultContentColumn({
    required this.title,
    required this.body,
    required this.visual,
    required this.action,
    this.titleMaxWidth = _walletLinkResultWidth,
    this.bodyMaxWidth = _walletLinkResultWidth,
  });

  final String title;
  final String body;
  final Widget visual;
  final Widget action;
  final double titleMaxWidth;
  final double bodyMaxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        visual,
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          width: _walletLinkResultWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: titleMaxWidth),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bodyMaxWidth),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        action,
      ],
    );
  }
}

class _EncryptedPlaceholder extends StatelessWidget {
  const _EncryptedPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    return CustomPaint(
      painter: _DashedRoundRectPainter(
        color: colors.text.muted.withValues(alpha: 0.65),
        radius: 28,
      ),
      child: SizedBox(
        width: 260,
        height: 340,
        child: Center(
          child: SizedBox(
            width: 228,
            height: 111,
            child: Column(
              children: [
                AppIcon(AppIcons.lock, size: 24, color: colors.text.primary),
                const SizedBox(height: AppSpacing.md),
                Text.rich(
                  TextSpan(
                    text:
                        'The code is encrypted with a one-time key and expires after a minute. ',
                    children: [
                      TextSpan(
                        text: 'Only your phone can decode it.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: bodyStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrTransferCard extends StatelessWidget {
  const _QrTransferCard({required this.qrPayload, required this.remaining});

  final String qrPayload;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 260,
      height: 340,
      decoration: BoxDecoration(
        color: colors.background.ground,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(29, 32, 29, 0),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 202,
            child: PrettyQrView(
              qrImage: _qrImage(qrPayload),
              decoration: PrettyQrDecoration(
                quietZone: PrettyQrQuietZone.zero,
                shape: DotQrShape(color: colors.text.accent),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '1/1 Ready to scan...',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.accent.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              width: 128,
              height: 6,
              child: LinearProgressIndicator(
                value: _progress(remaining),
                backgroundColor: colors.text.accent.withValues(alpha: 0.35),
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  QrImage _qrImage(String data) {
    final effectiveData = data.isEmpty ? 'vizor://wallet-link/preview' : data;
    final natural = QrCode.fromData(
      data: effectiveData,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    if (natural.typeNumber >= 7) return QrImage(natural);
    return QrImage(QrCode(7, QrErrorCorrectLevel.M)..addData(effectiveData));
  }

  double _progress(Duration remaining) {
    final fraction =
        remaining.inMilliseconds / const Duration(minutes: 1).inMilliseconds;
    return math.max(0, math.min(1, fraction));
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({
    required this.asset,
    required this.width,
    required this.height,
  });

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.iconName});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colors.background.base,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: AppIcon(iconName, size: 28, color: colors.icon.accent),
    );
  }
}

class _DashedRoundRectPainter extends CustomPainter {
  const _DashedRoundRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double _dash = 8;
  static const double _gap = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

String _formatRemaining(Duration duration) {
  final clamped = duration.isNegative ? Duration.zero : duration;
  final minutes = clamped.inMinutes;
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
