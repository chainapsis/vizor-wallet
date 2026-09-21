import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/linux_keyring_coordinator.dart';
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

    return MaterialApp(
      title: 'Vizor',
      debugShowCheckedModeBanner: false,
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
                    _failed ? 'Unable to open Vizor' : 'Opening Vizor',
                    style: AppTypography.headlineLarge.copyWith(
                      color: context.colors.text.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_failed) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Quit and restart Vizor to try again.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      onPressed: () => unawaited(SystemNavigator.pop()),
                      variant: AppButtonVariant.ghost,
                      child: const Text('Quit'),
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
    final title = switch (phase) {
      LinuxKeyringPhase.outcomeUnknown => 'Unable to confirm the save',
      LinuxKeyringPhase.serviceUnavailable => 'Secure storage is unavailable',
      LinuxKeyringPhase.storageCorrupt => 'Unable to read secure storage',
      LinuxKeyringPhase.retrying => 'Trying secure storage',
      _ => 'Unlock your keyring',
    };
    final body = switch (phase) {
      LinuxKeyringPhase.outcomeUnknown =>
        'Vizor could not confirm whether your changes were saved. '
            'Quit and restart Vizor before continuing.',
      LinuxKeyringPhase.serviceUnavailable =>
        'Vizor cannot connect to the system keyring. '
            'Try again, or quit and restart Vizor.',
      LinuxKeyringPhase.storageCorrupt =>
        'Vizor could not read the data in your system keyring. '
            'Retry after restoring access, or quit Vizor.',
      LinuxKeyringPhase.keyringLocked =>
        'Vizor cannot access your system keyring. '
            'Unlock the keyring, then choose Retry. '
            'A system prompt may ask for your keyring password.',
      _ => 'Complete any system keyring prompt to continue in Vizor.',
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
                          'The keyring did not respond. Try again.',
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
                          child: const Text('Retry'),
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
                          child: const Text('Cancel'),
                        ),
                      ],
                      if (!retrying) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppButton(
                          onPressed: () => unawaited(SystemNavigator.pop()),
                          variant: AppButtonVariant.ghost,
                          child: const Text('Quit'),
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
