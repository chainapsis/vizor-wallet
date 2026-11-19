import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/storage/account_visibility_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/mobile_account_visibility_provider.dart';
import '../../../../providers/mobile_passcode_auth_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../onboarding/mobile/adaptive_passcode_layout.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart';
import '../../../onboarding/mobile/passcode_widgets.dart';

const mobileAccountPasscodePath = '/accounts/account-passcode';

enum MobileAccountPasscodeAction { create, change, unlink }

class MobileAccountPasscodeEntry {
  const MobileAccountPasscodeEntry(this.accountUuid, this.action);

  final String accountUuid;
  final MobileAccountPasscodeAction action;
}

/// Static help from Settings. It does not read a wallet or code assignment.
class MobileAccountVisibilityGuideScreen extends StatelessWidget {
  const MobileAccountVisibilityGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: l10n.accountVisibilityTitle,
              titleMaxLines: 2,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(kMobilePageMargin),
                children: [
                  Text(
                    l10n.accountVisibilityDescription,
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Step {
  intro,
  wallet,
  unavailable,
  newPasscode,
  confirmPasscode,
  unlink,
  done,
}

class MobileAccountVisibilityScreen extends ConsumerStatefulWidget {
  const MobileAccountVisibilityScreen({
    required MobileAccountPasscodeEntry this.entry,
    super.key,
  });

  const MobileAccountVisibilityScreen.confirmBiometricChange({super.key})
    : entry = null;

  final MobileAccountPasscodeEntry? entry;

  @override
  ConsumerState<MobileAccountVisibilityScreen> createState() =>
      _MobileAccountVisibilityScreenState();
}

class _MobileAccountVisibilityScreenState
    extends ConsumerState<MobileAccountVisibilityScreen> {
  late final AppSecurityState _session;
  late final String? _scope;
  late final MobileAccountVisibilityRule? _originalRule;
  late final MobileAccountManagementSession _management;
  final _managementOwner = Object();
  late final AppLifecycleListener _lifecycle;
  late _Step _step = switch (widget.entry?.action) {
    MobileAccountPasscodeAction.create => _Step.intro,
    MobileAccountPasscodeAction.change => _Step.newPasscode,
    MobileAccountPasscodeAction.unlink => _Step.unlink,
    null => _Step.wallet,
  };
  String _entry = '';
  String? _firstCode;
  String Function(AppLocalizations)? _error;
  bool _busy = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    // Bind navigation to the scope and rule that actually opened this route.
    // Retained routes must never inherit authentication from a later unlock.
    _session = ref.read(appSecurityProvider);
    _scope = ref.read(mobileAccountScopeProvider);
    _originalRule = ref.read(mobileAccountVisibilityProvider).rule(_scope);
    _management = ref.read(mobileAccountManagementOpenProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _revision++;
        if (!_protectedStep) {
          setState(() {
            _busy = false;
            _entry = '';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _revision++;
    _lifecycle.dispose();
    _entry = '';
    _firstCode = null;
    scheduleMicrotask(() => _management.setOpen(_managementOwner, false));
    super.dispose();
  }

  bool get _protectedStep => switch (_step) {
    _Step.unavailable ||
    _Step.newPasscode ||
    _Step.confirmPasscode ||
    _Step.unlink ||
    _Step.done => true,
    _ => false,
  };

  bool get _usesKeypad => switch (_step) {
    _Step.wallet || _Step.newPasscode || _Step.confirmPasscode => true,
    _ => false,
  };

  AccountInfo? get _visibleAccount => ref
      .read(visibleAccountsProvider)
      .where((account) => account.uuid == widget.entry?.accountUuid)
      .firstOrNull;

  bool _hasAccess() {
    if (!_session.isUnlocked ||
        !identical(_session, ref.read(appSecurityProvider)) ||
        ref.read(mobileAccountScopeProvider) != _scope) {
      return false;
    }
    final entry = widget.entry;
    if (entry == null || _step == _Step.done) return true;
    if (_visibleAccount == null) return false;
    if (entry.action == MobileAccountPasscodeAction.create) {
      return _scope == null;
    }

    final rule = _originalRule;
    return rule != null &&
        identical(
          rule,
          ref.read(mobileAccountVisibilityProvider).rule(_scope),
        ) &&
        rule.accountIds.contains(entry.accountUuid) &&
        (entry.action == MobileAccountPasscodeAction.unlink ||
            rule.accountIds.length == 1);
  }

  void _show(_Step next) {
    setState(() {
      _step = next;
      _entry = '';
      _error = null;
      _busy = false;
    });
    _management.setOpen(_managementOwner, _protectedStep);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accounts');
    }
  }

  void _back() {
    if (_busy) return;
    _firstCode = null;
    if (!_hasAccess()) {
      _close();
      return;
    }
    switch (_step) {
      case _Step.wallet when widget.entry != null:
      case _Step.newPasscode
          when widget.entry?.action == MobileAccountPasscodeAction.create:
        _show(_Step.intro);
      case _Step.confirmPasscode:
        _show(_Step.newPasscode);
      default:
        _close();
    }
  }

  void _onDigit(int digit) {
    if (_busy || _entry.length == kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) unawaited(_submitCode());
  }

  void _backspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submitCode() async {
    if (!_hasAccess()) return;
    final code = _entry;
    if (_step == _Step.newPasscode) {
      _firstCode = code;
      _show(_Step.confirmPasscode);
      return;
    }
    if (_step == _Step.confirmPasscode) {
      final matches = code == _firstCode;
      _firstCode = null;
      if (matches) {
        await _save(code: code);
      } else {
        _show(_Step.newPasscode);
        _fail((l10n) => l10n.passcodesDidNotMatch);
      }
      return;
    }

    final revision = ++_revision;
    bool current() => mounted && revision == _revision && _hasAccess();
    setState(() => _busy = true);
    try {
      await ref
          .read(mobilePasscodeAuthProvider)
          .check(
            code: code,
            biometricReason: context.l10n.onboardingUnlockBiometricReason,
            isCurrent: current,
            walletOnly: true,
          );
      if (!mounted || !current()) return;
      if (widget.entry == null) {
        context.pop(true);
        return;
      }
      _show(
        ref.read(visibleAccountsProvider).length > 1
            ? _Step.newPasscode
            : _Step.unavailable,
      );
    } on MobilePasscodeRejected catch (error) {
      if (!current()) return;
      _fail(
        error.failure == MobilePasscodeFailure.biometric
            ? (l10n) => l10n.accountVisibilityBiometricRequired
            : (l10n) => l10n.passcodeIncorrect,
      );
    } catch (_) {
      if (current()) _fail((l10n) => l10n.settingsPasscodeCheckFailed);
    }
  }

  void _fail(String Function(AppLocalizations) message) {
    setState(() {
      _error = message;
      _entry = '';
      _busy = false;
    });
  }

  Future<void> _save({String? code}) async {
    if (_busy || !_hasAccess()) return;
    final entry = widget.entry!;
    final creating = entry.action == MobileAccountPasscodeAction.create;
    final removing = entry.action == MobileAccountPasscodeAction.unlink;
    final revision = ++_revision;
    bool current() => mounted && revision == _revision;
    final before = ref.read(accountProvider).value?.activeAccountUuid;
    // Unlink clears the linked scope before this route finishes closing.
    if (removing) _management.setOpen(_managementOwner, true);
    setState(() => _busy = true);
    try {
      await ref
          .read(mobileAccountVisibilityProvider.notifier)
          .change(
            isCurrent: () => current() && _hasAccess(),
            ruleId: _scope,
            accountId: creating ? entry.accountUuid : null,
            newPasscode: code,
            remove: removing,
          );
      if (!current()) return;
      final active = ref.read(accountProvider).value?.activeAccountUuid;
      if (active != null && before != active) {
        unawaited(_refreshSelection());
      }
      if (removing) {
        _close();
      } else {
        _show(_Step.done);
      }
    } on MobileAccountVisibilityEditException catch (error) {
      if (!current()) return;
      if (error.failure == MobileAccountVisibilityEditFailure.keepOrdinary &&
          creating) {
        _show(_Step.unavailable);
        return;
      }
      if (!removing) _show(_Step.newPasscode);
      _fail(
        error.failure == MobileAccountVisibilityEditFailure.differentPasscode
            ? (l10n) => l10n.accountVisibilityDifferentPasscode
            : (l10n) => l10n.accountVisibilityUpdateFailed,
      );
    } catch (_) {
      if (!current()) return;
      if (!removing) _show(_Step.newPasscode);
      _fail((l10n) => l10n.accountVisibilityUpdateFailed);
    }
  }

  Future<void> _refreshSelection() async {
    try {
      await ref.read(accountProvider.notifier).restoreAfterUnlock();
      if (mounted && identical(_session, ref.read(appSecurityProvider))) {
        await ref.read(syncProvider.notifier).refreshAfterAccountSwitch();
      }
    } catch (_) {
      // The assignment has committed. Normal sync rehydrates the display.
    }
  }

  Widget _keypad() {
    final l10n = context.l10n;
    final title = switch (_step) {
      _Step.newPasscode => l10n.accountVisibilityNewPasscode,
      _Step.confirmPasscode => l10n.accountVisibilityConfirmPasscode,
      _ => l10n.accountVisibilityEnterWalletPasscode,
    };
    final prompt = PasscodePromptField(
      length: kMobilePasscodeLength,
      filled: _entry.length,
      error: _error?.call(l10n),
    );
    final keypad = PasscodeNumpad(
      onDigit: _onDigit,
      onBackspace: _backspace,
      canDelete: _entry.isNotEmpty,
      enabled: !_busy,
    );
    const padding = EdgeInsets.symmetric(horizontal: kMobilePageMargin);
    return AdaptivePasscodeLayout(
      title: title,
      subtitle: l10n.accountVisibilitySixDigits,
      prompt: prompt,
      keypad: keypad,
      legacyPadding: padding,
      scaleLegacyKeypadToWidth: true,
      legacy: Padding(
        padding: padding,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      l10n.accountVisibilitySixDigits,
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: kPasscodePromptDigitsHeight,
                      child: prompt,
                    ),
                  ],
                ),
              ),
            ),
            FittedBox(fit: BoxFit.scaleDown, child: keypad),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    final l10n = context.l10n;
    final messages = switch (_step) {
      _Step.intro => [
        l10n.accountVisibilityUsualCode(_visibleAccount!.name),
        l10n.accountVisibilityDedicatedCode(_visibleAccount!.name),
      ],
      _Step.unavailable => [l10n.accountVisibilityKeepOrdinary],
      _Step.unlink => [
        (_originalRule?.accountIds.length ?? 0) > 1
            ? l10n.accountVisibilityLegacyUnlink
            : l10n.accountVisibilityDeleteBody(_visibleAccount!.name),
      ],
      _Step.done => [l10n.accountVisibilityCreatedBody],
      _ => const <String>[],
    };
    return [
      for (final message in messages)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(message, style: AppTypography.bodyMedium),
        ),
      if (_error case final error?)
        Text(error(l10n), style: AppTypography.bodyMedium),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSecurityProvider);
    ref.watch(mobileAccountScopeProvider);
    if (widget.entry != null) {
      ref.watch(visibleAccountsProvider);
      ref.watch(mobileAccountVisibilityProvider);
    }
    final l10n = context.l10n;
    final allowed = _hasAccess();
    final title = !allowed
        ? l10n.accountVisibilityTitle
        : switch (_step) {
            _Step.intro => l10n.accountVisibilityViewSeparately,
            _Step.unlink => l10n.accountVisibilityUnlinkTitle,
            _Step.done => l10n.accountVisibilityCreatedTitle,
            _ =>
              widget.entry == null
                  ? l10n.settingsSectionSystem
                  : l10n.accountVisibilityTitle,
          };
    final (String? label, VoidCallback? action) = allowed
        ? switch (_step) {
            _Step.intro => (
              l10n.accountVisibilityCreate,
              () => _show(_Step.wallet),
            ),
            _Step.unlink => (
              l10n.accountVisibilityDelete,
              () => unawaited(_save()),
            ),
            _Step.unavailable || _Step.done => (l10n.commonDone, _close),
            _ => (null, null),
          }
        : (null, null);
    return PopScope(
      canPop:
          !_busy &&
          (!allowed ||
              switch (_step) {
                _Step.intro ||
                _Step.unlink ||
                _Step.done ||
                _Step.unavailable => true,
                _Step.wallet => widget.entry == null,
                _Step.newPasscode =>
                  widget.entry?.action == MobileAccountPasscodeAction.change,
                _Step.confirmPasscode => false,
              }),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(title: title, titleMaxLines: 2, onBack: _back),
              Expanded(
                child: !allowed
                    ? const SizedBox.shrink()
                    : _usesKeypad
                    ? _keypad()
                    : ListView(
                        padding: const EdgeInsets.all(kMobilePageMargin),
                        children: _body(),
                      ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kMobilePageMargin,
                    AppSpacing.s,
                    kMobilePageMargin,
                    AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        expand: true,
                        constrainContent: true,
                        growWithContent: true,
                        onPressed: _busy ? null : action,
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                      if (_step == _Step.unlink) ...[
                        const SizedBox(height: AppSpacing.s),
                        AppButton(
                          variant: AppButtonVariant.secondary,
                          expand: true,
                          constrainContent: true,
                          growWithContent: true,
                          onPressed: _busy ? null : _close,
                          child: Text(
                            l10n.commonCancel,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
