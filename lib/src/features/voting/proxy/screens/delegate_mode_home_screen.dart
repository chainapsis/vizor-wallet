import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/config/proxy_delegation_feature_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../delegate_mode_models.dart';
import '../delegate_mode_presentation.dart';
import '../delegate_mode_providers.dart';
import '../proxy_delegation_copy.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/delegate_mode_widgets.dart';
import '../widgets/delegate_reauth_gate.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// Delegate mode's home on desktop.
class DelegateModeHomeScreen extends StatelessWidget {
  /// Creates the screen.
  const DelegateModeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppDesktopShell(
      sidebar: AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: DelegateModeHomeView(showDesktopToolbar: true),
      ),
    );
  }
}

/// Delegate mode's home: the DG-1 intro, a key awaiting registration, the
/// DG-8 dashboard or the retired state. The key's export shows here only
/// after re-auth, and only while the pane is open.
class DelegateModeHomeView extends ConsumerStatefulWidget {
  /// Creates the view.
  const DelegateModeHomeView({required this.showDesktopToolbar, super.key});

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<DelegateModeHomeView> createState() =>
      _DelegateModeHomeViewState();
}

class _DelegateModeHomeViewState extends ConsumerState<DelegateModeHomeView>
    with DelegateDeadlineTicker {
  String? _exported;
  String? _keyError;
  bool _busy = false;
  Timer? _refresh;
  late final SensitivePrivacyOverlayController _privacy;

  @override
  void initState() {
    super.initState();
    _privacy = ref.read(delegatePrivacyControllerFactoryProvider)();
    // The count is live: refresh it while the dashboard is open.
    _refresh = Timer.periodic(kDelegateDashboardRefresh, (_) {
      if (mounted) ref.invalidate(delegateRoundsProvider);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _exported = null;
    _privacy.dispose();
    super.dispose();
  }

  /// Opens [route] above the home, hiding a shown export first.
  void _push(String route) {
    if (_exported != null) setState(() => _exported = null);
    context.push(route);
  }

  /// Creates the device's key and opens its registration.
  Future<void> _create() async {
    setState(() {
      _busy = true;
      _keyError = null;
    });
    try {
      await ref.read(delegateModeRepositoryProvider).createKey();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _keyError = context.l10n.delegateCreateKeyError;
      });
      return;
    }
    if (!mounted) return;
    invalidateDelegateMode(ref);
    setState(() => _busy = false);
    _push(kDelegateRegistrationPath);
  }

  /// Shows the key's export after re-auth.
  Future<void> _export() async {
    setState(() => _keyError = null);
    final confirmed = await ref.read(delegateReauthProvider)(
      context,
      DelegateReauthPurpose.exportKey,
    );
    if (!confirmed || !mounted) return;
    try {
      final secret = await ref.read(delegateModeRepositoryProvider).exportKey();
      if (!mounted) return;
      setState(() => _exported = secret);
    } catch (_) {
      if (!mounted) return;
      setState(() => _keyError = context.l10n.delegateExportError);
    }
  }

  /// Asks, then removes the device's unregistered or [retired] key. An
  /// unregistered key's confirmation shows its export, after re-auth, and
  /// removes it only once the user says it is saved.
  Future<void> _startOver({required bool retired}) async {
    setState(() => _keyError = null);
    String? secret;
    if (!retired) {
      final confirmed = await ref.read(delegateReauthProvider)(
        context,
        DelegateReauthPurpose.exportKey,
      );
      if (!confirmed || !mounted) return;
      try {
        secret = await ref.read(delegateModeRepositoryProvider).exportKey();
      } catch (_) {
        if (!mounted) return;
        setState(() => _keyError = context.l10n.delegateExportError);
        return;
      }
      if (!mounted) return;
      // Guards the export while the confirmation shows it.
      setState(() => _exported = secret);
    }
    final remove = await showDelegateModal<bool>(
      context: context,
      title: context.l10n.delegateStartOverTitle,
      builder: (context) => DelegateStartOverContent(exported: secret),
    );
    if (!mounted) return;
    if (remove != true) {
      setState(() => _exported = null);
      return;
    }
    setState(() {
      _busy = true;
      _exported = null;
    });
    final l10n = context.l10n;
    String? error;
    try {
      await ref.read(delegateModeRepositoryProvider).startOver();
    } catch (_) {
      error = l10n.delegateStartOverError;
    }
    if (!mounted) return;
    invalidateDelegateMode(ref);
    setState(() {
      _busy = false;
      _keyError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(delegateModeStatusProvider);
    final now = ref.watch(proxyClockProvider)();
    final keyError = _keyError;

    Widget? action;
    final Widget body;
    if (status.hasError) {
      body = ProxyNotice(
        message: delegateModeErrorCopy(context.l10n, status.error!),
        tone: ProxyNoticeTone.error,
        actionLabel: context.l10n.commonTryAgain,
        onAction: () => ref.invalidate(delegateModeStatusProvider),
      );
    } else if (!status.hasValue) {
      body = const VotingPaneLoading();
    } else {
      final value = status.requireValue;
      final key = value.key;
      final keyCard = key == null
          ? const SizedBox.shrink()
          : DelegateKeyCard(
              keyInfo: key,
              delegateIndex: value.entry?.delegateIndex,
              exported: _exported,
              error: keyError,
              onExport: _export,
              onHide: () => setState(() => _exported = null),
            );
      final startOver = AppButton(
        key: const ValueKey('delegate_start_over'),
        onPressed: _busy ? null : () => _startOver(retired: value.retired),
        variant: value.retired
            ? AppButtonVariant.primary
            : AppButtonVariant.secondary,
        expand: true,
        growWithContent: true,
        constrainContent: true,
        child: Text(
          value.retired
              ? context.l10n.delegateStartOverLabel
              : context.l10n.delegateUseDifferentKeyLabel,
        ),
      );
      switch (delegateHomeStage(value)) {
        case DelegateHomeStage.intro:
          body = DelegateModeIntroContent(error: keyError);
          action = DelegateActionStack(
            children: [
              AppButton(
                key: const ValueKey('delegate_intro_create'),
                onPressed: _busy ? null : _create,
                expand: true,
                growWithContent: true,
                constrainContent: true,
                child: Text(context.l10n.delegateCreateKeyLabel),
              ),
              AppButton(
                key: const ValueKey('delegate_intro_import'),
                onPressed: _busy ? null : () => _push(kDelegateKeyImportPath),
                variant: AppButtonVariant.secondary,
                expand: true,
                growWithContent: true,
                constrainContent: true,
                child: Text(context.l10n.delegateImportKeyLabel),
              ),
            ],
          );
        case DelegateHomeStage.finishRegistering:
          body = DelegateFinishRegisteringContent(
            keyCard: keyCard,
            registrationPending: value.registrationPending,
          );
          action = DelegateActionStack(
            children: [
              AppButton(
                key: const ValueKey('delegate_continue_registration'),
                onPressed: _busy
                    ? null
                    : () => _push(kDelegateRegistrationPath),
                expand: true,
                growWithContent: true,
                constrainContent: true,
                child: Text(context.l10n.delegateContinueRegistrationLabel),
              ),
              startOver,
            ],
          );
        case DelegateHomeStage.dashboard:
          final rounds = ref.watch(delegateRoundsProvider);
          final roundList = rounds.value ?? const <DelegateRound>[];
          armDeadlineTicker(now, [
            for (final round in roundList) round.voteEndTime,
          ]);
          // Includes a listed ballot that conflicts with this device's.
          final rejections = <String, ApiBallotSubmitResult>{
            for (final round in roundList)
              round.view.roundId: ?ref.watch(
                delegateBallotResenderProvider(round.view.roundId),
              ),
          };
          for (final round in roundList) {
            if (rejections.containsKey(round.view.roundId) ||
                !delegateBallotPending(round, now)) {
              continue;
            }
            ref
                .read(
                  delegateBallotResenderProvider(round.view.roundId).notifier,
                )
                .keepSending();
          }
          body = DelegateDashboardContent(
            status: value,
            rounds: rounds,
            ballotRejections: rejections,
            now: now,
            keyCard: keyCard,
            onOpenRound: (round) =>
                _push(delegateBallotRoute(round.view.roundId)),
            onRetryRounds: () => ref.invalidate(delegateRoundsProvider),
            onRetire: () => _push(kDelegateRetirePath),
          );
        case DelegateHomeStage.retired:
          body = DelegateRetiredContent(keyCard: keyCard);
          action = startOver;
      }
    }
    return SensitivePrivacyOverlay(
      sensitiveContentVisible: _exported != null,
      controller: _privacy,
      child: ProxyPaneLayout(
        showDesktopToolbar: widget.showDesktopToolbar,
        title: context.l10n.delegateModeTitle,
        action: action,
        child: body,
      ),
    );
  }
}

/// DG-1: what being a delegate means, before any key exists.
class DelegateModeIntroContent extends StatelessWidget {
  /// Creates the intro.
  const DelegateModeIntroContent({this.error, super.key});

  /// Why creating the key failed.
  final String? error;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.xs);
    final error = this.error;
    return Column(
      key: const ValueKey('delegate_intro'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.delegateIntroTitle,
          style: AppTypography.headlineSmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        ProxyNotice(
          key: const ValueKey('delegate_intro_ballot_rules'),
          message: context.l10n.proxyBallotRules,
        ),
        const SizedBox(height: AppSpacing.s),
        ProxyBodyText(context.l10n.proxyDelegateIntroPublicVotes),
        gap,
        ProxyBodyText(context.l10n.proxyDelegateIntroCount),
        gap,
        ProxyBodyText(context.l10n.proxyDelegateIntroPrivateVotes),
        gap,
        ProxyBodyText(context.l10n.delegateHowPeopleFindYou),
        gap,
        ProxyBodyText(
          context.l10n.delegateIntroLostKey,
          key: const ValueKey('delegate_intro_lost_key'),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.s),
          ProxyNotice(
            key: const ValueKey('delegate_key_error'),
            message: error,
            tone: ProxyNoticeTone.error,
          ),
        ],
      ],
    );
  }
}

/// The device's key while it still awaits its registration.
class DelegateFinishRegisteringContent extends StatelessWidget {
  /// Creates the content.
  const DelegateFinishRegisteringContent({
    required this.keyCard,
    this.registrationPending = false,
    super.key,
  });

  /// The key with its export controls.
  final Widget keyCard;

  /// A signed registration was sent and has not landed yet.
  final bool registrationPending;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('delegate_finish_registering'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(
          context.l10n.delegateFinishRegisteringTitle,
          strong: true,
        ),
        const SizedBox(height: AppSpacing.xxs),
        ProxyBodyText(context.l10n.delegateFinishRegistering),
        if (registrationPending) ...[
          const SizedBox(height: AppSpacing.s),
          ProxyNotice(
            key: const ValueKey('delegate_registration_pending'),
            message: context.l10n.delegateRegistrationPending,
          ),
        ],
        const SizedBox(height: AppSpacing.s),
        keyCard,
      ],
    );
  }
}

/// DG-8: the delegate's identity from its proven entry, each round's
/// approximate count and ballot state, and the key on the device. No ZEC
/// totals.
class DelegateDashboardContent extends StatelessWidget {
  /// Creates the dashboard body.
  const DelegateDashboardContent({
    required this.status,
    required this.rounds,
    required this.now,
    required this.keyCard,
    this.ballotRejections = const {},
    this.onOpenRound,
    this.onRetryRounds,
    this.onRetire,
    super.key,
  });

  /// The device's delegate state.
  final DelegateModeView status;

  /// Proxy rounds.
  final AsyncValue<List<DelegateRound>> rounds;

  /// The chain's rejection of a round's submitted ballot, by round id.
  final Map<String, ApiBallotSubmitResult> ballotRejections;

  /// Current time.
  final DateTime now;

  /// The key with its export controls.
  final Widget keyCard;

  /// Opens DG-9 for a round.
  final ValueChanged<DelegateRound>? onOpenRound;

  /// Loads the rounds again.
  final VoidCallback? onRetryRounds;

  /// Opens DG-11.
  final VoidCallback? onRetire;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.s);
    final titleStyle = AppTypography.bodyMediumStrong.copyWith(
      color: context.colors.text.accent,
    );
    final key = status.key;
    final handle = status.entry?.handle;
    return Column(
      key: const ValueKey('delegate_dashboard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyCard(
          key: const ValueKey('delegate_identity'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (handle != null) Text('@$handle', style: titleStyle),
              if (status.entry?.provider case final provider?)
                ProxyBodyText(switch (provider) {
                  ProxyDelegateProvider.x => context.l10n.proxyProviderXLabel,
                  ProxyDelegateProvider.gitHub =>
                    context.l10n.proxyProviderGitHubLabel,
                }),
              if (key != null) ...[
                const SizedBox(height: AppSpacing.xs),
                DelegateKeyLine(
                  keyInfo: key,
                  delegateIndex: status.entry?.delegateIndex,
                  picture: status.picture,
                ),
              ],
            ],
          ),
        ),
        if (status.suspended) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_suspended'),
            message: context.l10n.delegateSuspended,
            tone: ProxyNoticeTone.error,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(context.l10n.delegateRoundsTitle, style: titleStyle),
        const SizedBox(height: AppSpacing.xs),
        ...rounds.when(
          skipLoadingOnRefresh: true,
          loading: () => const [VotingPaneLoading()],
          error: (error, _) => [
            ProxyNotice(
              message: delegateModeErrorCopy(context.l10n, error),
              tone: ProxyNoticeTone.error,
              actionLabel: context.l10n.commonTryAgain,
              onAction: onRetryRounds,
            ),
          ],
          data: (rounds) => rounds.isEmpty
              ? [ProxyBodyText(context.l10n.delegateNoRounds)]
              : [
                  for (final (i, round) in rounds.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    DelegateRoundCard(
                      round: round,
                      now: now,
                      rejection: ballotRejections[round.view.roundId],
                      onOpen: onOpenRound == null
                          ? null
                          : () => onOpenRound!(round),
                    ),
                  ],
                ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(context.l10n.delegateKeyTitle, style: titleStyle),
        const SizedBox(height: AppSpacing.xs),
        keyCard,
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('delegate_retire'),
          onPressed: onRetire,
          variant: AppButtonVariant.ghost,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateRetireLabel),
        ),
      ],
    );
  }
}

/// One round on DG-8: its deadline, the approximate count, the ballot state
/// and the reminder or warning. A submitted ballot reads as confirming on
/// chain until the round's list shows it, see [delegateBallotPending].
class DelegateRoundCard extends StatelessWidget {
  /// Creates the card.
  const DelegateRoundCard({
    required this.round,
    required this.now,
    this.rejection,
    this.onOpen,
    super.key,
  });

  /// The round.
  final DelegateRound round;

  /// Current time.
  final DateTime now;

  /// The chain's rejection of the submitted ballot.
  final ApiBallotSubmitResult? rejection;

  /// Opens DG-9.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final id = round.view.roundId;
    final rejection = this.rejection;
    final pending = rejection == null && delegateBallotPending(round, now);
    final submitted =
        round.onChainOptions != null || pending || rejection != null;
    final urgency = delegateBallotUrgency(
      now: now,
      voteEnd: round.voteEndTime,
      ballotOnChain: submitted,
    );
    final endTime = formatProxyVoteEnd(context.l10n, round.voteEndTime);
    final notice = switch (urgency) {
      _ when rejection != null => ProxyNotice(
        key: ValueKey('delegate_round_rejected_$id'),
        message: delegateBallotRejectionCopy(
          context.l10n,
          rejection.codespace,
          rejection.code,
        ),
        tone: ProxyNoticeTone.error,
      ),
      DelegateBallotUrgency.done => null,
      DelegateBallotUrgency.reminder => ProxyNotice(
        key: ValueKey('delegate_round_reminder_$id'),
        message: context.l10n.delegateBallotReminder(endTime),
      ),
      DelegateBallotUrgency.finalMinutes ||
      DelegateBallotUrgency.finalSeconds => ProxyNotice(
        key: ValueKey('delegate_round_final_minutes_$id'),
        message: context.l10n.delegateFinalMinutes(
          delegateMinutesLeft(now: now, voteEnd: round.voteEndTime),
        ),
        tone: ProxyNoticeTone.warning,
      ),
      DelegateBallotUrgency.closed =>
        round.view.ballot.kind == ApiDelegateBallotKind.notCounted
            ? null
            : ProxyNotice(
                key: ValueKey('delegate_round_closed_$id'),
                message: context.l10n.delegateVotingEnded,
                tone: ProxyNoticeTone.error,
              ),
    };
    return ProxyCard(
      key: ValueKey('delegate_round_$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            round.title,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
          ProxyBodyText(context.l10n.delegateVotingEnds(endTime)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            delegateCountText(context.l10n, round.view.revealedShares),
            key: ValueKey('delegate_round_count_$id'),
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
          ProxyBodyText(context.l10n.proxyDelegateIntroCount),
          const SizedBox(height: AppSpacing.xs),
          Text(
            pending
                ? context.l10n.delegateBallotPendingLabel
                : delegateBallotStatusLabel(context.l10n, round.view.ballot),
            key: ValueKey('delegate_round_ballot_$id'),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          if (notice != null) ...[
            const SizedBox(height: AppSpacing.xs),
            notice,
          ],
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: ValueKey('delegate_round_open_$id'),
            onPressed: onOpen,
            variant: submitted
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            expand: true,
            growWithContent: true,
            constrainContent: true,
            child: Text(
              submitted
                  ? context.l10n.delegateViewBallotLabel
                  : context.l10n.delegateOpenBallotLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// The device's delegate key, with the way to its export: the `zvdsk1…`
/// string and a QR code of exactly that string (contracts-v1 section 11.2),
/// shown only while [exported] is set. Callers wrap it in a
/// `SensitivePrivacyOverlay` while the export is on screen.
class DelegateKeyCard extends StatelessWidget {
  /// Creates the card.
  const DelegateKeyCard({
    required this.keyInfo,
    this.delegateIndex,
    this.exported,
    this.error,
    this.onExport,
    this.onHide,
    super.key,
  });

  /// The key.
  final DelegateKeyInfo keyInfo;

  /// The entry's index, once registered.
  final int? delegateIndex;

  /// The key's export, shown after re-auth.
  final String? exported;

  /// Why the last export or removal failed.
  final String? error;

  /// Re-authenticates and shows the export.
  final VoidCallback? onExport;

  /// Hides the export.
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final exported = this.exported;
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyCard(
          key: const ValueKey('delegate_key_card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DelegateKeyLine(keyInfo: keyInfo, delegateIndex: delegateIndex),
              const SizedBox(height: AppSpacing.xs),
              ProxyBodyText(context.l10n.delegateKeyBackup),
              if (exported != null) ...[
                const SizedBox(height: AppSpacing.xs),
                DelegateKeyExport(secret: exported),
              ],
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton(
                  key: ValueKey(
                    exported == null
                        ? 'delegate_export_key'
                        : 'delegate_hide_key',
                  ),
                  onPressed: exported == null ? onExport : onHide,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                  leading: AppIcon(
                    exported == null ? AppIcons.eye : AppIcons.eyeClosed,
                  ),
                  child: Text(
                    exported == null
                        ? context.l10n.delegateExportKeyLabel
                        : context.l10n.delegateHideKeyLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          ProxyNotice(
            key: const ValueKey('delegate_key_error'),
            message: error,
            tone: ProxyNoticeTone.error,
          ),
        ],
      ],
    );
  }
}

/// A delegate key's export: the `zvdsk1…` text, a QR code whose content is
/// exactly that text, and a way to copy it.
class DelegateKeyExport extends StatelessWidget {
  /// Creates the export view of [secret].
  const DelegateKeyExport({required this.secret, super.key});

  /// The key's `zvdsk1…` export.
  final String secret;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('delegate_key_export'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyNotice(
          message: context.l10n.delegateExportedKey,
          tone: ProxyNoticeTone.warning,
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Container(
            width: 184,
            height: 184,
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: PrettyQrView.data(
              key: const ValueKey('delegate_key_export_qr'),
              data: secret,
              errorCorrectLevel: QrErrorCorrectLevel.L,
              decoration: const PrettyQrDecoration(
                quietZone: PrettyQrQuietZone.zero,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          secret,
          key: const ValueKey('delegate_key_export_text'),
          style: AppTypography.codeSmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            key: const ValueKey('delegate_key_export_copy'),
            onPressed: () => Clipboard.setData(ClipboardData(text: secret)),
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.small,
            leading: const AppIcon(AppIcons.copy),
            child: Text(context.l10n.delegateCopyKeyLabel),
          ),
        ),
      ],
    );
  }
}

/// The confirmation before a key is removed from the device. With an
/// unregistered key's [exported] secret, it shows the export and enables
/// removal once the user confirms it is saved. Pops true to remove it.
class DelegateStartOverContent extends StatefulWidget {
  /// Creates the content.
  const DelegateStartOverContent({this.exported, super.key});

  /// The unregistered key's export, or null for a retired key.
  final String? exported;

  @override
  State<DelegateStartOverContent> createState() =>
      _DelegateStartOverContentState();
}

class _DelegateStartOverContentState extends State<DelegateStartOverContent> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final exported = widget.exported;
    return Column(
      key: const ValueKey('delegate_start_over_confirm'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (exported == null)
          ProxyBodyText(context.l10n.delegateStartOver)
        else ...[
          ProxyBodyText(context.l10n.delegateStartOverSaveKey, strong: true),
          const SizedBox(height: AppSpacing.xs),
          DelegateKeyExport(secret: exported),
          const SizedBox(height: AppSpacing.xs),
          MergeSemantics(
            child: GestureDetector(
              key: const ValueKey('delegate_start_over_saved'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _saved = !_saved),
              child: Row(
                children: [
                  Material(
                    type: MaterialType.transparency,
                    child: Checkbox(
                      value: _saved,
                      onChanged: (checked) =>
                          setState(() => _saved = checked ?? false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ProxyBodyText(
                      context.l10n.delegateStartOverSavedLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('delegate_start_over_remove'),
          onPressed: exported == null || _saved
              ? () => Navigator.of(context).pop(true)
              : null,
          variant: AppButtonVariant.destructive,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateStartOverConfirmLabel),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('delegate_start_over_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          variant: AppButtonVariant.ghost,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.commonCancel),
        ),
      ],
    );
  }
}

/// The key's entry is retired, so the device can start over.
class DelegateRetiredContent extends StatelessWidget {
  /// Creates the content.
  const DelegateRetiredContent({required this.keyCard, super.key});

  /// The key with its export controls.
  final Widget keyCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('delegate_retired'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyNotice(
          message: context.l10n.delegateRetired,
          tone: ProxyNoticeTone.warning,
        ),
        const SizedBox(height: AppSpacing.s),
        keyCard,
      ],
    );
  }
}

/// The voting list's way into delegate mode. Renders nothing when the
/// dormant flag is off.
class DelegateModeEntryLink extends ConsumerWidget {
  /// Creates the link.
  const DelegateModeEntryLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(proxyDelegationFeatureEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            0,
          ),
          child: Semantics(
            button: true,
            child: GestureDetector(
              key: const ValueKey('delegate_mode_entry'),
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push(kDelegateModePath),
              child: ProxyCard(
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.users,
                      size: AppIconSize.medium,
                      color: colors.icon.regular,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.delegateModeTitle,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          Text(
                            context.l10n.delegateModeEntry,
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIcon(
                      AppIcons.chevronForward,
                      size: AppIconSize.medium,
                      color: colors.icon.regular,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
