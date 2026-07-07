import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, LinearProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_qr_shape.dart';
import '../models/wallet_link_models.dart';
import '../providers/wallet_link_provider.dart';

class WalletLinkDesktopScreen extends ConsumerWidget {
  const WalletLinkDesktopScreen({this.previewState, super.key});

  final WalletLinkState? previewState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewState;
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

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: DefaultTextStyle(
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
            child: content,
          ),
        ),
      ),
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
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
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
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 340, child: Center(child: visual)),
        const SizedBox(height: AppSpacing.md),
        action,
        const SizedBox(height: AppSpacing.lg),
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
        const SizedBox(height: AppSpacing.xs),
        visual,
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        action,
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _EncryptedPlaceholder extends StatelessWidget {
  const _EncryptedPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CustomPaint(
      painter: _DashedRoundRectPainter(
        color: colors.text.muted.withValues(alpha: 0.45),
        radius: 16,
      ),
      child: SizedBox(
        width: 260,
        height: 340,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatusIcon(
                iconName: AppIcons.lock,
                backgroundColor: colors.background.base,
                foregroundColor: colors.icon.accent,
                size: 48,
                iconSize: 20,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The code is encrypted with a one-time key and expires after a minute. Only your phone can decode it.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
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
        color: colors.background.inverse,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 22),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 204,
            child: PrettyQrView(
              qrImage: _qrImage(qrPayload),
              decoration: PrettyQrDecoration(
                quietZone: PrettyQrQuietZone.zero,
                shape: DotQrShape(color: colors.text.inverse),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '1/1 Ready to scan...',
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.inverse.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              width: 128,
              height: 6,
              child: LinearProgressIndicator(
                value: _progress(remaining),
                backgroundColor: colors.text.inverse.withValues(alpha: 0.16),
                color: colors.text.inverse,
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
  const _StatusIcon({
    required this.iconName,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 64,
    this.iconSize = 28,
  });

  final String iconName;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.background.base,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: AppIcon(
        iconName,
        size: iconSize,
        color: foregroundColor ?? colors.icon.accent,
      ),
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
