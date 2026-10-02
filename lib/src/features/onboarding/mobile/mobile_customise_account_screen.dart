import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../payment_links/services/gift_claim_setup_coordinator.dart';
import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../accounts/widgets/mobile/account_edit_sheets.dart'
    show showProfilePictureSheet;
import '../create/account_persona_generator.dart';
import '../ledger/ledger_setup_args.dart';
import '../shared/customise_account_mutation.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import 'mobile_onboarding_scaffold.dart';
import '../../payment_links/providers/gift_claim_flow_provider.dart';

typedef MobileCustomiseAccountFinishCallback =
    Future<void> Function(String accountName, String profilePictureId);

/// Mobile account personalisation shared by create, import, Keystone, and Ledger.
/// The original create design is captured by Figma light/dark default frames
/// 6125:117635 / 6132:117807 and keyboard/error frames 6125:117233 /
/// 6132:117773.
class MobileCustomiseAccountScreen extends ConsumerStatefulWidget {
  const MobileCustomiseAccountScreen({
    this.args,
    this.onFinish,
    this.position,
    this.onBack,
    this.random,
    this.actionsEnabled = true,
    this.setupCommitted = false,
    super.key,
  }) : assert(
         args != null || (onFinish != null && position != null),
         'Custom setup args or an alternate completion presentation is required.',
       );

  final CustomiseAccountArgs? args;

  /// Alternate completion seam used by previews, tests, and hardware flows.
  final MobileCustomiseAccountFinishCallback? onFinish;

  final OnboardingProgressPosition? position;
  final VoidCallback? onBack;

  /// Optional entropy source for deterministic previews and tests.
  final Random? random;

  /// A terminal setup failure can require reopening instead of creating again.
  final bool actionsEnabled;

  /// The account exists; retry only its unfinished storage, keeping its persona.
  final bool setupCommitted;

  @override
  ConsumerState<MobileCustomiseAccountScreen> createState() =>
      _MobileCustomiseAccountScreenState();
}

enum _SubmitPhase { idle, stoppingSync, creatingWallet }

class _MobileCustomiseAccountScreenState
    extends ConsumerState<MobileCustomiseAccountScreen> {
  late final TextEditingController _nameController;
  final _nameFocusNode = FocusNode();
  Animation<double>? _routeAnimation;
  var _initialFocusMonitoringScheduled = false;
  var _initialFocusRequested = false;
  late String _profilePictureId;
  var _submitPhase = _SubmitPhase.idle;
  String? _submitError;

  String get _normalizedName => normalizeAccountName(_nameController.text);
  int get _nameLength => accountNameCharacterLength(_nameController.text);
  bool get _nameValid => isAccountNameLengthValid(_nameController.text);
  bool get _isSubmitting => _submitPhase != _SubmitPhase.idle;
  bool get _canContinue =>
      widget.actionsEnabled && !_isSubmitting && _nameValid;

  String? get _nameMessage {
    if (_submitError != null) return _submitError;
    return _nameLength > kAccountNameMaxCharacters
        ? kAccountNameLengthMessage
        : null;
  }

  @override
  void initState() {
    super.initState();
    final suggestion = generateAccountPersona(random: widget.random);
    _nameController = TextEditingController(text: suggestion.name)
      ..selection = TextSelection.collapsed(offset: suggestion.name.length);
    _profilePictureId = suggestion.profilePictureId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialFocusMonitoringScheduled) return;
    _initialFocusMonitoringScheduled = true;
    // iOS can discard a software-keyboard request while the Cupertino route
    // is still entering, so defer the first focus until that transition ends.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialFocusRequested) return;
      final routeAnimation = ModalRoute.of(context)?.animation;
      if (routeAnimation == null ||
          routeAnimation.status == AnimationStatus.completed) {
        _requestInitialFocus();
        return;
      }
      _routeAnimation = routeAnimation
        ..addStatusListener(_handleRouteAnimationStatus);
    });
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _requestInitialFocus();
    }
  }

  void _requestInitialFocus() {
    if (_initialFocusRequested) return;
    _initialFocusRequested = true;
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nameFocusNode.canRequestFocus) {
        _nameFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _handleNameChanged(String _) {
    setState(() => _submitError = null);
  }

  void _randomisePersona() {
    if (_isSubmitting || widget.setupCommitted || !widget.actionsEnabled) {
      return;
    }
    final suggestion = generateAccountPersona(random: widget.random);
    _nameController.value = TextEditingValue(
      text: suggestion.name,
      selection: TextSelection.collapsed(offset: suggestion.name.length),
    );
    setState(() {
      _profilePictureId = suggestion.profilePictureId;
      _submitError = null;
    });
  }

  Future<void> _pickProfilePicture() async {
    if (_isSubmitting || widget.setupCommitted || !widget.actionsEnabled) {
      return;
    }
    _nameFocusNode.unfocus();
    final selected = await showProfilePictureSheet(
      context,
      selectedId: _profilePictureId,
    );
    if (selected != null && mounted) {
      setState(() => _profilePictureId = selected);
    }
  }

  Future<void> _submit() async {
    if (!_canContinue) return;
    _nameFocusNode.unfocus();
    setState(() {
      _submitPhase = _SubmitPhase.creatingWallet;
      _submitError = null;
    });

    try {
      final onFinish = widget.onFinish;
      if (onFinish != null) {
        await onFinish(_normalizedName, _profilePictureId);
        if (mounted) setState(() => _submitPhase = _SubmitPhase.idle);
        return;
      }
      await _finishSetup();
    } catch (e, st) {
      log('MobileCustomiseAccount._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _SubmitPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
    }
  }

  Future<void> _finishSetup() async {
    final args = widget.args!;
    final router = GoRouter.of(context);
    Future<void> createAccount() => runCustomisedAccountMutation(
      ref,
      setupArgs: args.setupArgs,
      accountName: _normalizedName,
      profilePictureId: _profilePictureId,
      onStoppingSync: () {
        if (mounted) {
          setState(() => _submitPhase = _SubmitPhase.stoppingSync);
        }
      },
      onSyncPaused: () {
        if (mounted) {
          setState(() => _submitPhase = _SubmitPhase.creatingWallet);
        }
      },
    );

    final pendingPassword = args.pendingPassword;
    if (pendingPassword == null) {
      await createAccount();
      await completeGiftClaimImportSetup(ref);
      clearCustomisedAccountDraft(ref, args.flow);
      router.go(giftClaimSetupCompletionLocation(ref, otherwise: '/home'));
      return;
    }

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var passwordPrepared = false;
    var passwordCommitted = false;
    try {
      await routerRefresh.pauseWhile(() async {
        await securityNotifier.preparePasswordSetup(pendingPassword);
        passwordPrepared = true;
        await createAccount();
        securityNotifier.commitPasswordSetup();
        passwordCommitted = true;
        await completeGiftClaimImportSetup(ref);
        clearCustomisedAccountDraft(ref, args.flow);
        router.go('/onboarding/biometrics');
      });
    } catch (_) {
      if (passwordPrepared && !passwordCommitted) {
        try {
          await securityNotifier.rollbackPasswordSetup();
        } catch (rollbackError, rollbackStack) {
          log(
            'MobileCustomiseAccount._finishSetup: password rollback failed: '
            '$rollbackError\n$rollbackStack',
          );
        }
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = MobileOnboardingStepScaffold(
      progress:
          widget.position?.value ??
          MobileOnboardingProgressScope.of(context)
              .at(
                onboardingFlowForSetup(widget.args!.flow),
                OnboardingStage.customiseAccount,
              )
              .value,
      onBack: _isSubmitting ? null : widget.onBack,
      showBackButton: widget.onBack != null,
      title: 'Customise Account',
      subtitle:
          'Add personality to your account by setting an account name and '
          'choosing a profile picture.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_customise_account_continue'),
        expand: true,
        constrainContent: true,
        onPressed: _canContinue ? _submit : null,
        trailing: const AppIcon(AppIcons.chevronForward),
        child: Text(switch (_submitPhase) {
          _SubmitPhase.idle => widget.setupCommitted ? 'Try again' : 'Continue',
          _SubmitPhase.stoppingSync => 'Stop syncing...',
          _SubmitPhase.creatingWallet =>
            widget.setupCommitted ? 'Saving wallet...' : 'Creating wallet...',
        }),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          _AccountProfileCard(
            nameController: _nameController,
            nameFocusNode: _nameFocusNode,
            profilePictureId: _profilePictureId,
            message: _nameMessage,
            enabled:
                !_isSubmitting &&
                !widget.setupCommitted &&
                widget.actionsEnabled,
            onNameChanged: _handleNameChanged,
            onEditProfilePicture: _pickProfilePicture,
            onRandomisePersona: _randomisePersona,
            onSubmitted: _submit,
          ),
        ],
      ),
    );
    return PopScope<void>(
      canPop: widget.onBack != null && !_isSubmitting,
      child: content,
    );
  }
}

class MobileLedgerCustomiseAccountScreen extends ConsumerWidget {
  const MobileLedgerCustomiseAccountScreen({required this.args, super.key});

  final LedgerCustomiseAccountArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MobileCustomiseAccountScreen(
      args: CustomiseAccountArgs(
        setupArgs: SetPasswordScreenArgs.importLedger(
          account: args.account,
          birthdayHeight: args.birthdayHeight,
        ),
        pendingPassword: args.pendingPassword,
      ),
    );
  }
}

class _AccountProfileCard extends StatelessWidget {
  const _AccountProfileCard({
    required this.nameController,
    required this.nameFocusNode,
    required this.profilePictureId,
    required this.message,
    required this.enabled,
    required this.onNameChanged,
    required this.onEditProfilePicture,
    required this.onRandomisePersona,
    required this.onSubmitted,
  });

  final TextEditingController nameController;
  final FocusNode nameFocusNode;
  final String profilePictureId;
  final String? message;
  final bool enabled;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onEditProfilePicture;
  final VoidCallback onRandomisePersona;
  final Future<void> Function() onSubmitted;

  static const _randomiseTapSize = 44.0;
  static const _randomiseVisualSize = 28.0;
  static const _randomiseInset = (_randomiseTapSize - _randomiseVisualSize) / 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('mobile_customise_account_card'),
          height: 123,
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            // Keep the card corner concentric with the inset randomise circle.
            borderRadius: BorderRadius.circular(
              _randomiseVisualSize / 2 + _randomiseInset,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.md,
                  end: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    _EditableProfilePicture(
                      profilePictureId: profilePictureId,
                      enabled: enabled,
                      onPressed: onEditProfilePicture,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: _randomiseTapSize,
                            ),
                            child: Text(
                              'Account name',
                              style: AppTypography.labelLarge.copyWith(
                                color: cardTextColor.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 30,
                            child: TextField(
                              key: const ValueKey(
                                'mobile_customise_account_name_field',
                              ),
                              controller: nameController,
                              focusNode: nameFocusNode,
                              enabled: enabled,
                              maxLines: 1,
                              textInputAction: TextInputAction.done,
                              style: AppTypography.headlineSmall.copyWith(
                                color: cardTextColor,
                              ),
                              cursorColor: cardTextColor,
                              cursorWidth: 2,
                              cursorHeight: 22,
                              cursorRadius: const Radius.circular(
                                AppRadii.full,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                              onChanged: onNameChanged,
                              onSubmitted: (_) => onSubmitted(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: 0,
                end: 0,
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  label: 'Randomise account name and profile picture',
                  onTap: enabled ? onRandomisePersona : null,
                  child: ExcludeSemantics(
                    child: AppButton(
                      key: const ValueKey('mobile_customise_account_randomise'),
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      height: _randomiseTapSize,
                      minWidth: _randomiseTapSize,
                      contentPadding: EdgeInsets.zero,
                      enabledBackgroundColor: colors.background.homeCard
                          .withValues(alpha: 0),
                      pressedBackgroundColor: colors.background.homeCard
                          .withValues(alpha: 0),
                      disabledBackgroundColor: colors.background.homeCard
                          .withValues(alpha: 0),
                      onPressed: enabled ? onRandomisePersona : null,
                      child: Container(
                        key: const ValueKey(
                          'mobile_customise_account_randomise_visual',
                        ),
                        width: _randomiseVisualSize,
                        height: _randomiseVisualSize,
                        decoration: BoxDecoration(
                          color: enabled
                              ? colors.button.secondary.bg
                              : colors.button.disabled.bg,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.renew,
                            size: 16,
                            color: enabled
                                ? colors.button.secondary.label
                                : colors.button.disabled.label,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

class _EditableProfilePicture extends StatelessWidget {
  const _EditableProfilePicture({
    required this.profilePictureId,
    required this.enabled,
    required this.onPressed,
  });

  final String profilePictureId;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Change profile picture',
      child: GestureDetector(
        key: const ValueKey('mobile_customise_account_avatar_button'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppProfilePicture(
                profilePictureId: profilePictureId,
                size: AppProfilePictureSize.xLarge,
              ),
              Positioned(
                right: -6,
                bottom: -6,
                child: Container(
                  key: const ValueKey('mobile_customise_account_edit_badge'),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.text.homeCard,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.background.homeCard,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: _CustomiseAccountEditGlyph(
                      color: colors.background.homeCard,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomiseAccountEditGlyph extends StatelessWidget {
  const _CustomiseAccountEditGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Keep the dark-variant 20px edit frame, but leave more breathing room
    // around this icon asset because its filled bounds read larger on-device.
    return SizedBox(
      key: const ValueKey('mobile_customise_account_edit_glyph_frame'),
      width: 20,
      height: 20,
      child: Center(
        child: AppIcon(
          key: const ValueKey('mobile_customise_account_edit_glyph'),
          AppIcons.editFilled,
          size: 12,
          color: color,
        ),
      ),
    );
  }
}
