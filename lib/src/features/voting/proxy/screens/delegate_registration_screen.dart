import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../delegate_mode_models.dart';
import '../delegate_mode_presentation.dart';
import '../delegate_mode_providers.dart';
import '../proxy_delegation_copy.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/delegate_mode_widgets.dart';
import '../widgets/delegate_reauth_gate.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// Registration on desktop.
class DelegateRegistrationScreen extends StatelessWidget {
  /// Creates the screen.
  const DelegateRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppDesktopShell(
      sidebar: AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: DelegateRegistrationView(showDesktopToolbar: true),
      ),
    );
  }
}

/// Where a registration attempt stands.
enum DelegateRegistrationStep {
  /// Waiting for the proof link.
  idle,

  /// The verifier is checking the post.
  checking,

  /// REGISTER is on its way to the chain.
  registering,

  /// The chain assigned or kept the index.
  done,
}

/// Registration: the exact marker to post, the post or gist link, the
/// attester's answer and then the on-chain REGISTER, ending with the
/// entry's index. The marker names only the key, and the handle comes from
/// the attester's reading of the post.
class DelegateRegistrationView extends ConsumerStatefulWidget {
  /// Creates the view.
  const DelegateRegistrationView({required this.showDesktopToolbar, super.key});

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<DelegateRegistrationView> createState() =>
      _DelegateRegistrationViewState();
}

class _DelegateRegistrationViewState
    extends ConsumerState<DelegateRegistrationView> {
  final _link = TextEditingController();
  ProxyDelegateProvider? _provider;
  DelegateRegistrationStep _step = DelegateRegistrationStep.idle;
  String? _error;
  bool _verifyAgain = false;
  DelegateRegistered? _registered;
  DelegateKeyInfo? _registeredKey;
  String? _handle;
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    _link.dispose();
    super.dispose();
  }

  /// Copies the public marker text.
  Future<void> _copyMarker(String marker) async {
    try {
      await Clipboard.setData(ClipboardData(text: marker));
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _copiedReset?.cancel();
    setState(() => _copied = true);
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Verifies the post, then registers [key] on chain.
  Future<void> _submit(
    DelegateKeyInfo key,
    ProxyDelegateProvider provider,
  ) async {
    final url = _link.text.trim();
    if (!delegateProofUrlLooksRight(provider, url)) {
      setState(
        () => _error = provider == ProxyDelegateProvider.x
            ? context.l10n.delegateProofLinkXInvalid
            : context.l10n.delegateProofLinkGitHubInvalid,
      );
      return;
    }
    final repository = ref.read(delegateModeRepositoryProvider);
    setState(() {
      _step = DelegateRegistrationStep.checking;
      _error = null;
      _verifyAgain = false;
    });
    final DelegateAttestation attestation;
    try {
      attestation = await repository.attest(
        provider: provider,
        proofUrl: url,
        key: key,
      );
    } on DelegateVerifierRefusal catch (error) {
      if (!mounted) return;
      setState(() {
        _step = DelegateRegistrationStep.idle;
        _error = delegateVerifierErrorText(context.l10n, error);
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = DelegateRegistrationStep.idle;
        _error = delegateVerifierErrorCopy(context.l10n, null);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _step = DelegateRegistrationStep.registering);
    final DelegateRegisterResult result;
    try {
      result = await repository.register(
        attestation,
        reauth: delegateSigningReauth(
          context,
          ref,
          DelegateReauthPurpose.register,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (delegateSigningCancelled(error)) {
        setState(() => _step = DelegateRegistrationStep.idle);
        return;
      }
      setState(() {
        _step = DelegateRegistrationStep.idle;
        _error = delegateModeErrorCopy(
          context.l10n,
          error,
          fallback: context.l10n.delegateRegisterFailed,
        );
      });
      return;
    }
    if (!mounted) return;
    switch (result) {
      case final DelegateRegisterRejected rejected:
        setState(() {
          _step = DelegateRegistrationStep.idle;
          _error = delegateRegisterRejectionCopy(
            context.l10n,
            rejected.codespace,
            rejected.code,
          );
          _verifyAgain = delegateRegisterNeedsNewAttestation(rejected);
        });
      case final DelegateRegistered registered:
        _link.clear();
        invalidateDelegateMode(ref);
        setState(() {
          _step = DelegateRegistrationStep.done;
          _registered = registered;
          _registeredKey = key;
          _handle = attestation.handle;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final registered = _registered;
    final registeredKey = _registeredKey;
    if (registered != null && registeredKey != null) {
      return ProxyPaneLayout(
        showDesktopToolbar: widget.showDesktopToolbar,
        title: context.l10n.delegateRegisterTitle,
        action: AppButton(
          key: const ValueKey('delegate_registered_open'),
          onPressed: () => context.go(kDelegateModePath),
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateOpenDashboardLabel),
        ),
        child: DelegateRegisteredContent(
          result: registered,
          keyInfo: registeredKey,
          handle: _handle,
        ),
      );
    }
    final status = ref.watch(delegateModeStatusProvider);
    final value = status.value;
    final pending = value == null || value.registered ? null : value.key;
    final Widget body;
    Widget? action;
    if (status.hasError) {
      body = ProxyNotice(
        message: delegateModeErrorCopy(context.l10n, status.error!),
        tone: ProxyNoticeTone.error,
        actionLabel: context.l10n.commonTryAgain,
        onAction: () => ref.invalidate(delegateModeStatusProvider),
      );
    } else if (value == null) {
      body = const VotingPaneLoading();
    } else if (pending == null) {
      body = ProxyNotice(
        key: const ValueKey('delegate_nothing_to_register'),
        message: context.l10n.delegateNothingToRegister,
      );
    } else {
      final provider = _provider ?? ProxyDelegateProvider.x;
      final marker = ref.watch(delegateMarkerProvider(pending));
      final busy =
          _step == DelegateRegistrationStep.checking ||
          _step == DelegateRegistrationStep.registering;
      body = DelegateRegistrationContent(
        keyInfo: pending,
        provider: provider,
        marker: marker,
        link: _link,
        step: _step,
        error: _error,
        copied: _copied,
        onProviderChanged: busy
            ? null
            : (choice) => setState(() {
                _provider = choice;
                _error = null;
              }),
        onCopyMarker: _copyMarker,
        onRetryMarker: () => ref.invalidate(delegateMarkerProvider(pending)),
        onLinkChanged: () => setState(() => _error = null),
      );
      action = AppButton(
        key: const ValueKey('delegate_register_submit'),
        onPressed: busy || !marker.hasValue || _link.text.trim().isEmpty
            ? null
            : () => _submit(pending, provider),
        expand: true,
        growWithContent: true,
        constrainContent: true,
        child: Text(
          _verifyAgain
              ? context.l10n.delegateVerifyAgainLabel
              : context.l10n.delegateVerifyAndRegisterLabel,
        ),
      );
    }
    return ProxyPaneLayout(
      showDesktopToolbar: widget.showDesktopToolbar,
      title: context.l10n.delegateRegisterTitle,
      action: action,
      child: body,
    );
  }
}

/// Session-free registration body shared by the live view and tests.
class DelegateRegistrationContent extends StatelessWidget {
  /// Creates the body.
  const DelegateRegistrationContent({
    required this.keyInfo,
    required this.provider,
    required this.marker,
    required this.link,
    required this.step,
    this.error,
    this.copied = false,
    this.onProviderChanged,
    this.onCopyMarker,
    this.onRetryMarker,
    this.onLinkChanged,
    super.key,
  });

  /// The key being registered.
  final DelegateKeyInfo keyInfo;

  /// The account provider to prove.
  final ProxyDelegateProvider provider;

  /// The marker text to post.
  final AsyncValue<String> marker;

  /// The proof link field.
  final TextEditingController link;

  /// Where the attempt stands.
  final DelegateRegistrationStep step;

  /// An attester or chain answer to show.
  final String? error;

  /// The marker was just copied.
  final bool copied;

  /// Chooses the provider; null while busy.
  final ValueChanged<ProxyDelegateProvider>? onProviderChanged;

  /// Copies the marker.
  final ValueChanged<String>? onCopyMarker;

  /// Loads the marker again.
  final VoidCallback? onRetryMarker;

  /// The link changed.
  final VoidCallback? onLinkChanged;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.s);
    final titleStyle = AppTypography.bodyMediumStrong.copyWith(
      color: context.colors.text.accent,
    );
    final error = this.error;
    final x = provider == ProxyDelegateProvider.x;
    final running =
        step == DelegateRegistrationStep.checking ||
        step == DelegateRegistrationStep.registering;
    return Column(
      key: const ValueKey('delegate_registration'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DelegateKeyLine(
          key: const ValueKey('delegate_registration_key'),
          keyInfo: keyInfo,
          label: context.l10n.delegateKeyLabel,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(context.l10n.delegateProviderTitle, style: titleStyle),
        for (final option in ProxyDelegateProvider.values)
          DelegateRadioOption(
            key: ValueKey('delegate_provider_${option.name.toLowerCase()}'),
            label: switch (option) {
              ProxyDelegateProvider.x => context.l10n.proxyProviderXLabel,
              ProxyDelegateProvider.gitHub =>
                context.l10n.proxyProviderGitHubLabel,
            },
            selected: option == provider,
            onTap: onProviderChanged == null
                ? null
                : () => onProviderChanged!(option),
          ),
        const SizedBox(height: AppSpacing.s),
        Text(context.l10n.delegateMarkerTitle, style: titleStyle),
        const SizedBox(height: AppSpacing.xxs),
        ProxyBodyText(
          x ? context.l10n.delegateMarkerX : context.l10n.delegateMarkerGitHub,
        ),
        gap,
        ...marker.when(
          loading: () => const [VotingPaneLoading()],
          error: (error, _) => [
            ProxyNotice(
              message: delegateModeErrorCopy(context.l10n, error),
              tone: ProxyNoticeTone.error,
              actionLabel: context.l10n.commonTryAgain,
              onAction: onRetryMarker,
            ),
          ],
          data: (text) => [
            ProxyCard(
              key: const ValueKey('delegate_marker'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    text,
                    key: const ValueKey('delegate_marker_text'),
                    style: AppTypography.codeSmall.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      key: const ValueKey('delegate_marker_copy'),
                      onPressed: onCopyMarker == null
                          ? null
                          : () => onCopyMarker!(text),
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      leading: AppIcon(copied ? AppIcons.check : AppIcons.copy),
                      child: Text(
                        copied
                            ? context.l10n.commonCopied
                            : context.l10n.delegateCopyMarkerLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ProxyBodyText(context.l10n.delegateKeepPost),
        gap,
        AppTextField(
          key: const ValueKey('delegate_proof_link'),
          label: x
              ? context.l10n.delegateProofLinkXLabel
              : context.l10n.delegateProofLinkGitHubLabel,
          hintText: x
              ? context.l10n.delegateProofLinkXHint
              : context.l10n.delegateProofLinkGitHubHint,
          controller: link,
          enabled: !running,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => onLinkChanged?.call(),
        ),
        if (running) ...[
          gap,
          DelegateStepRow(
            label: context.l10n.delegateStepCheckingPost,
            active: step == DelegateRegistrationStep.checking,
            complete: step == DelegateRegistrationStep.registering,
          ),
          DelegateStepRow(
            label: context.l10n.delegateStepRegistering,
            active: step == DelegateRegistrationStep.registering,
            complete: false,
          ),
        ],
        if (error != null) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_register_error'),
            message: error,
            tone: ProxyNoticeTone.error,
          ),
        ],
      ],
    );
  }
}

/// The landed registration: the entry's index and the verified handle.
class DelegateRegisteredContent extends StatelessWidget {
  /// Creates the content.
  const DelegateRegisteredContent({
    required this.result,
    required this.keyInfo,
    this.handle,
    super.key,
  });

  /// The chain's answer.
  final DelegateRegistered result;

  /// The registered key.
  final DelegateKeyInfo keyInfo;

  /// The verified handle, without `@`.
  final String? handle;

  @override
  Widget build(BuildContext context) {
    final handle = this.handle;
    return Column(
      key: const ValueKey('delegate_registered'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(context.l10n.delegateRegisteredTitle, strong: true),
        const SizedBox(height: AppSpacing.s),
        DelegateKeyLine(
          key: const ValueKey('delegate_registered_key'),
          keyInfo: keyInfo,
          delegateIndex: result.delegateIndex,
          label: context.l10n.delegateKeyLabel,
        ),
        if (handle != null) ...[
          const SizedBox(height: AppSpacing.s),
          ProxyBodyText(context.l10n.delegateRegistered(handle)),
        ],
        const SizedBox(height: AppSpacing.s),
        ProxyNotice(
          key: const ValueKey('delegate_how_people_find_you'),
          message: context.l10n.delegateHowPeopleFindYou,
        ),
      ],
    );
  }
}
