import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/linux_keyring_coordinator.dart';
import '../l10n/app_language.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_icon.dart';

bool _needsKeyringNotice(LinuxKeyringCoordinator coordinator) {
  if (!coordinator.isEnabled) return false;
  return switch (coordinator.state.phase) {
    LinuxKeyringPhase.ready || LinuxKeyringPhase.working => false,
    LinuxKeyringPhase.retrying ||
    LinuxKeyringPhase.keyringLocked ||
    LinuxKeyringPhase.serviceUnavailable ||
    LinuxKeyringPhase.storageCorrupt ||
    LinuxKeyringPhase.outcomeUnknown => true,
  };
}

/// Blocks wallet interaction while Linux secure storage needs user attention.
///
/// Place below [AppTheme] in the app builder, above the router. The child stays
/// mounted so retrying a failed storage call resumes the current operation.
class LinuxKeyringGate extends StatefulWidget {
  const LinuxKeyringGate({required this.child, this.coordinator, super.key});

  final Widget child;
  final LinuxKeyringCoordinator? coordinator;

  @override
  State<LinuxKeyringGate> createState() => _LinuxKeyringGateState();
}

class _LinuxKeyringGateState extends State<LinuxKeyringGate>
    with WidgetsBindingObserver {
  LinuxKeyringCoordinator get _coordinator =>
      widget.coordinator ?? LinuxKeyringCoordinator.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The gate sits above the router, where a PopScope has no enclosing route.
  // Register before the child router so system back cannot bypass the blocker.
  @override
  Future<bool> didPopRoute() async => _needsKeyringNotice(_coordinator);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _coordinator,
      child: widget.child,
      builder: (context, child) {
        final blocked = _needsKeyringNotice(_coordinator);
        return PopScope<void>(
          canPop: !blocked,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                excluding: blocked,
                child: ExcludeFocus(
                  excluding: blocked,
                  child: IgnorePointer(ignoring: blocked, child: child),
                ),
              ),
              if (blocked) ...[
                ModalBarrier(
                  dismissible: false,
                  color: context.colors.background.neutralScrim,
                ),
                Material(
                  type: MaterialType.transparency,
                  child: _LinuxKeyringNotice(coordinator: _coordinator),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Paints a neutral first frame before starting wallet bootstrap on Linux.
///
/// [loadApp] runs once, after that frame. It owns bootstrap error routing and
/// returns the complete app, including its provider scope and keyring gate.
class LinuxKeyringStartupHost extends StatefulWidget {
  const LinuxKeyringStartupHost({
    required this.loadApp,
    this.coordinator,
    super.key,
  });

  final Future<Widget> Function() loadApp;
  final LinuxKeyringCoordinator? coordinator;

  @override
  State<LinuxKeyringStartupHost> createState() =>
      _LinuxKeyringStartupHostState();
}

class _LinuxKeyringStartupHostState extends State<LinuxKeyringStartupHost> {
  Widget? _app;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadApp());
    });
  }

  Future<void> _loadApp() async {
    try {
      final app = await widget.loadApp();
      if (mounted) setState(() => _app = app);
    } catch (_) {
      // Bootstrap normally returns its own recovery app. Keep an unexpected
      // startup failure visible without constructing wallet providers here.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_app case final app?) return app;

    // Shown before storage is readable, so there is no saved language yet:
    // follow the device.
    return MaterialApp(
      title: 'Vizor', // l10n-ignore: product name
      debugShowCheckedModeBanner: false,
      supportedLocales: appSupportedLocales(),
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, child) => AppTheme(
        data: MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? AppThemeData.dark
            : AppThemeData.light,
        child: LinuxKeyringGate(coordinator: widget.coordinator, child: child!),
      ),
      home: Builder(
        builder: (context) => Material(
          color: context.colors.background.window,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    _failed ? AppIcons.lock : AppIcons.loader,
                    animated: !_failed,
                    size: AppIconSize.large,
                    color: context.colors.icon.accent,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _failed
                        ? context.l10n.appOpenFailedTitle
                        : context.l10n.keyringOpeningTitle,
                    style: AppTypography.headlineLarge.copyWith(
                      color: context.colors.text.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_failed) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l10n.keyringRestartHint,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      onPressed: () => unawaited(SystemNavigator.pop()),
                      variant: AppButtonVariant.ghost,
                      child: Text(context.l10n.commonQuit),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinuxKeyringNotice extends StatefulWidget {
  const _LinuxKeyringNotice({required this.coordinator});

  final LinuxKeyringCoordinator coordinator;

  @override
  State<_LinuxKeyringNotice> createState() => _LinuxKeyringNoticeState();
}

class _LinuxKeyringNoticeState extends State<_LinuxKeyringNotice> {
  bool _requesting = false;
  bool _actionFailed = false;

  Future<void> _request(Future<void> Function() action) async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _actionFailed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _actionFailed = true);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = widget.coordinator;
    final phase = coordinator.state.phase;
    final retrying = phase == LinuxKeyringPhase.retrying;
    final unknown = phase == LinuxKeyringPhase.outcomeUnknown;
    final requestId = coordinator.state.requestId;
    final canCancel =
        coordinator.state.canCancel &&
        requestId != null &&
        !coordinator.hasPendingMutation &&
        !unknown;
    final colors = context.colors;
    final l10n = context.l10n;
    final title = switch (phase) {
      LinuxKeyringPhase.outcomeUnknown => l10n.keyringSaveUnconfirmedTitle,
      LinuxKeyringPhase.serviceUnavailable => l10n.keyringUnavailableTitle,
      LinuxKeyringPhase.storageCorrupt => l10n.keyringUnreadableTitle,
      LinuxKeyringPhase.retrying => l10n.keyringTryingTitle,
      _ => l10n.keyringUnlockTitle,
    };
    final body = switch (phase) {
      LinuxKeyringPhase.outcomeUnknown => l10n.keyringSaveUnconfirmedBody,
      LinuxKeyringPhase.serviceUnavailable => l10n.keyringUnavailableBody,
      LinuxKeyringPhase.storageCorrupt => l10n.keyringUnreadableBody,
      LinuxKeyringPhase.keyringLocked => l10n.keyringLockedBody,
      _ => l10n.keyringPromptBody,
    };

    return FocusScope(
      autofocus: true,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) =>
            event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 424),
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.lock,
                        size: AppIconSize.large,
                        color: colors.icon.accent,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        namesRoute: true,
                        liveRegion: true,
                        child: Text(
                          title,
                          style: AppTypography.headlineLarge.copyWith(
                            color: colors.text.accent,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        body,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_actionFailed) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.keyringNoResponse,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.secondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      if (retrying)
                        AppIcon(
                          AppIcons.loader,
                          animated: true,
                          color: colors.icon.accent,
                        )
                      else if (coordinator.state.canRetry)
                        AppButton(
                          onPressed: _requesting
                              ? null
                              : () => unawaited(
                                  _request(
                                    () => coordinator.retry(
                                      requestId: requestId!,
                                    ),
                                  ),
                                ),
                          autofocus: true,
                          minWidth: 172,
                          child: Text(l10n.commonRetry),
                        ),
                      if (canCancel) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppButton(
                          onPressed: _requesting
                              ? null
                              : () => unawaited(
                                  _request(
                                    () => coordinator.cancel(
                                      requestId: requestId,
                                    ),
                                  ),
                                ),
                          variant: AppButtonVariant.ghost,
                          child: Text(l10n.commonCancel),
                        ),
                      ],
                      if (!retrying) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppButton(
                          onPressed: () => unawaited(SystemNavigator.pop()),
                          variant: AppButtonVariant.ghost,
                          child: Text(l10n.commonQuit),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
