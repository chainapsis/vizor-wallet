import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show log;
import '../../app_bootstrap.dart';
import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import 'shared/onboarding_welcome_art.dart';

class StorageUnavailableScreen extends ConsumerStatefulWidget {
  const StorageUnavailableScreen({super.key});

  @override
  ConsumerState<StorageUnavailableScreen> createState() =>
      _StorageUnavailableScreenState();
}

class _StorageUnavailableScreenState
    extends ConsumerState<StorageUnavailableScreen> {
  bool _isRetrying = false;
  String? _retryError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
      _retryError = null;
    });
    try {
      await ref.read(appBootstrapRetryProvider)();
    } catch (error, stackTrace) {
      log('storage unavailable retry failed: $error\n$stackTrace');
      if (mounted) {
        final failureKind = ref.read(appBootstrapProvider).failureKind;
        setState(() {
          _retryError =
              failureKind == AppBootstrapFailureKind.walletDbMigrationFailed
              ? AppLocalizations.of(context).storageDbUpdateStillFailed
              : AppLocalizations.of(context).storageStillUnavailable;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: _StorageUnavailablePane(
            child: _StorageUnavailableContent(
              isRetrying: _isRetrying,
              retryError: _retryError,
              onRetry: () {
                unawaited(_retry());
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageUnavailablePane extends StatelessWidget {
  const _StorageUnavailablePane({required this.child});

  final Widget child;

  static const double _canvasWidth = 1064;
  static const double _canvasHeight = 672;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: OnboardingWelcomeBackdrop(
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final alignment = constraints.maxHeight < _canvasHeight
                    ? Alignment.bottomCenter
                    : Alignment.center;
                return OverflowBox(
                  alignment: alignment,
                  minWidth: _canvasWidth,
                  maxWidth: _canvasWidth,
                  minHeight: _canvasHeight,
                  maxHeight: _canvasHeight,
                  child: SizedBox(
                    width: _canvasWidth,
                    height: _canvasHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Center(child: child),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageUnavailableContent extends ConsumerWidget {
  const _StorageUnavailableContent({
    required this.isRetrying,
    required this.retryError,
    required this.onRetry,
  });

  final bool isRetrying;
  final String? retryError;
  final VoidCallback onRetry;

  static const double _contentWidth = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final bootstrap = ref.watch(appBootstrapProvider);
    final failureKind = bootstrap.failureKind;
    final details =
        retryError ??
        (failureKind == AppBootstrapFailureKind.startupFailure
            ? bootstrap.failureMessage
            : null);
    return SizedBox(
      width: _contentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VizorWordmark(),
          const SizedBox(height: AppSpacing.lg),
          AppIcon(
            AppIcons.lock,
            size: AppIconSize.large,
            color: colors.icon.accent,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _title(context, failureKind),
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _body(context, failureKind),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (details != null && details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              details,
              style: AppTypography.bodySmall.copyWith(color: colors.text.muted),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            onPressed: isRetrying ? null : onRetry,
            minWidth: 172,
            leading: AppIcon(
              isRetrying ? AppIcons.loader : AppIcons.renew,
              animated: isRetrying,
            ),
            child: Text(isRetrying ? AppLocalizations.of(context).storageRetrying : AppLocalizations.of(context).commonRetry),
          ),
          if (isDesktopLayoutPlatform) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              onPressed: () {
                unawaited(SystemNavigator.pop());
              },
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              minWidth: 96,
              child: Text(AppLocalizations.of(context).storageQuit),
            ),
          ],
        ],
      ),
    );
  }

  String _title(BuildContext context, AppBootstrapFailureKind? failureKind) {
    if (failureKind == AppBootstrapFailureKind.walletDbMigrationFailed) {
      return AppLocalizations.of(context).storageDbUpdateTitle;
    }
    if (failureKind == AppBootstrapFailureKind.startupFailure) {
      return AppLocalizations.of(context).storageOpenFailedTitle;
    }
    return _isLinux ? AppLocalizations.of(context).storageUnlockKeyring : AppLocalizations.of(context).storageLockedTitle;
  }

  String _body(BuildContext context, AppBootstrapFailureKind? failureKind) {
    if (failureKind == AppBootstrapFailureKind.walletDbMigrationFailed) {
      return AppLocalizations.of(context).storageDbUpdateBody;
    }
    if (failureKind == AppBootstrapFailureKind.startupFailure) {
      return AppLocalizations.of(context).storageStartupBody;
    }
    return _isLinux
        ? AppLocalizations.of(context).storageKeyringBody
        : AppLocalizations.of(context).storageSecureBody;
  }

  bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
}
