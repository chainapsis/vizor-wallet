import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../delegate_mode_models.dart';
import '../delegate_mode_presentation.dart';
import '../delegate_mode_providers.dart';
import '../proxy_delegation_copy.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/delegate_mode_widgets.dart';
import '../widgets/delegate_reauth_gate.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// DG-11 on desktop.
class DelegateRetireScreen extends StatelessWidget {
  /// Creates the screen.
  const DelegateRetireScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppDesktopShell(
      sidebar: AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: DelegateRetireView(showDesktopToolbar: true),
      ),
    );
  }
}

/// DG-11: the Retire copy and the entry it retires. Pressing "Retire" is
/// the confirm; the app's re-auth follows, then the entry's key signs
/// RETIRE.
class DelegateRetireView extends ConsumerStatefulWidget {
  /// Creates the view.
  const DelegateRetireView({required this.showDesktopToolbar, super.key});

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<DelegateRetireView> createState() => _DelegateRetireViewState();
}

class _DelegateRetireViewState extends ConsumerState<DelegateRetireView> {
  bool _busy = false;
  DelegateRetireResult? _done;
  String? _error;

  /// Retires the entry, after the app's re-auth.
  Future<void> _retire() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final DelegateRetireResult result;
    try {
      result = await ref
          .read(delegateModeRepositoryProvider)
          .retire(
            reauth: delegateSigningReauth(
              context,
              ref,
              DelegateReauthPurpose.retire,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      if (delegateSigningCancelled(error)) {
        setState(() => _busy = false);
        return;
      }
      invalidateDelegateMode(ref);
      setState(() {
        _busy = false;
        _error = delegateModeErrorCopy(
          context.l10n,
          error,
          fallback: context.l10n.delegateRetireFailed,
        );
      });
      return;
    }
    if (!mounted) return;
    invalidateDelegateMode(ref);
    setState(() {
      _busy = false;
      switch (result) {
        case DelegateRetired():
          _done = result;
        case DelegateRetireRejected(:final codespace, :final code):
          _error = delegateRetireRejectionCopy(context.l10n, codespace, code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    if (done != null) {
      return ProxyPaneLayout(
        showDesktopToolbar: widget.showDesktopToolbar,
        title: context.l10n.delegateRetireLabel,
        action: AppButton(
          key: const ValueKey('delegate_retired_back'),
          onPressed: () => context.go(kDelegateModePath),
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateBackToDelegateModeLabel),
        ),
        child: Column(
          key: const ValueKey('delegate_retire_done'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProxyBodyText(context.l10n.delegateRetiredTitle, strong: true),
            const SizedBox(height: AppSpacing.xxs),
            ProxyBodyText(context.l10n.delegateRetiredDone),
          ],
        ),
      );
    }
    final status = ref.watch(delegateModeStatusProvider);
    final value = status.value;
    final Widget body;
    var canRetire = false;
    if (status.hasError) {
      body = ProxyNotice(
        message: delegateModeErrorCopy(context.l10n, status.error!),
        tone: ProxyNoticeTone.error,
        actionLabel: context.l10n.commonTryAgain,
        onAction: () => ref.invalidate(delegateModeStatusProvider),
      );
    } else if (value == null) {
      body = const VotingPaneLoading();
    } else {
      canRetire = value.registered && !value.retired;
      body = DelegateRetireContent(
        keyInfo: canRetire ? value.key : null,
        delegateIndex: value.entry?.delegateIndex,
        error: _error,
      );
    }
    return ProxyPaneLayout(
      showDesktopToolbar: widget.showDesktopToolbar,
      title: context.l10n.delegateRetireLabel,
      action: AppButton(
        key: const ValueKey('delegate_retire_confirm'),
        onPressed: canRetire && !_busy ? _retire : null,
        variant: AppButtonVariant.destructive,
        expand: true,
        growWithContent: true,
        constrainContent: true,
        child: Text(context.l10n.delegateRetireLabel),
      ),
      child: body,
    );
  }
}

/// Session-free DG-11 body shared by the live view and tests.
class DelegateRetireContent extends StatelessWidget {
  /// Creates the body.
  const DelegateRetireContent({
    required this.keyInfo,
    this.delegateIndex,
    this.error,
    super.key,
  });

  /// The key of the entry Retire retires; null when there is none.
  final DelegateKeyInfo? keyInfo;

  /// The entry's index.
  final int? delegateIndex;

  /// A rejected Retire to explain.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final keyInfo = this.keyInfo;
    return Column(
      key: const ValueKey('delegate_retire'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyNotice(
          key: const ValueKey('delegate_retire_copy'),
          message: context.l10n.proxyRetire,
          tone: ProxyNoticeTone.warning,
        ),
        const SizedBox(height: AppSpacing.s),
        if (keyInfo == null)
          ProxyBodyText(context.l10n.delegateNothingToRetire)
        else ...[
          ProxyBodyText(context.l10n.delegateRetireEntryTitle, strong: true),
          const SizedBox(height: AppSpacing.xs),
          DelegateKeyLine(keyInfo: keyInfo, delegateIndex: delegateIndex),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.s),
          ProxyNotice(
            key: const ValueKey('delegate_retire_error'),
            message: error,
            tone: ProxyNoticeTone.error,
          ),
        ],
      ],
    );
  }
}
