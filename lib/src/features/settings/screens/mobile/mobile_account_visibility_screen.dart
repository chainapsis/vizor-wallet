import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/mobile_account_visibility_provider.dart';
import '../../../../providers/mobile_passcode_auth_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../onboarding/mobile/adaptive_passcode_layout.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart';
import '../../../onboarding/mobile/passcode_widgets.dart';

enum _Step {
  overview,
  createAuth,
  manageAuth,
  manageWallet,
  selectAccounts,
  newPasscode,
  confirmPasscode,
  manage,
  editAccounts,
  remove,
  confirmBiometricChange,
}

class MobileAccountVisibilityScreen extends ConsumerStatefulWidget {
  const MobileAccountVisibilityScreen({
    this.confirmBiometricChange = false,
    super.key,
  });

  final bool confirmBiometricChange;

  @override
  ConsumerState<MobileAccountVisibilityScreen> createState() =>
      _MobileAccountVisibilityScreenState();
}

class _MobileAccountVisibilityScreenState
    extends ConsumerState<MobileAccountVisibilityScreen> {
  late _Step _step = widget.confirmBiometricChange
      ? _Step.confirmBiometricChange
      : _Step.overview;
  late final MobileAccountManagementSession _management;
  final _managementOwner = Object();
  late final AppLifecycleListener _lifecycle;
  final _selected = <String>{};
  String _entry = '';
  String? _firstCode;
  String? _ruleId;
  String Function(AppLocalizations)? _error;
  bool _busy = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _management = ref.read(mobileAccountManagementOpenProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        // The root host handles authenticated settings pages. Clear in-flight
        // verification here so a late biometric result cannot open one.
        _revision++;
        if (!_isAuthenticatedStep) {
          setState(() {
            _busy = false;
            _entry = '';
            _ruleId = null;
            if (_step == _Step.manageWallet) _step = _Step.manageAuth;
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
    // A route replacement may dispose the page without running its Back
    // callback. Release its lease after the widget tree finishes updating.
    scheduleMicrotask(() => _management.setOpen(_managementOwner, false));
    super.dispose();
  }

  bool get _isAuthenticatedStep => switch (_step) {
    _Step.selectAccounts ||
    _Step.newPasscode ||
    _Step.confirmPasscode ||
    _Step.manage ||
    _Step.editAccounts ||
    _Step.remove => true,
    _ => false,
  };

  bool get _usesKeypad => switch (_step) {
    _Step.createAuth ||
    _Step.manageAuth ||
    _Step.manageWallet ||
    _Step.newPasscode ||
    _Step.confirmPasscode ||
    _Step.confirmBiometricChange => true,
    _ => false,
  };

  void _show(_Step step) {
    setState(() {
      _step = step;
      _entry = '';
      _error = null;
      _busy = false;
    });
    _management.setOpen(_managementOwner, _isAuthenticatedStep);
  }

  void _back() {
    if (_busy) return;
    switch (_step) {
      case _Step.overview:
      case _Step.confirmBiometricChange:
        context.pop();
      case _Step.manageWallet:
        _ruleId = null;
        _show(_Step.manageAuth);
      case _Step.newPasscode:
      case _Step.confirmPasscode:
        _firstCode = null;
        _show(_ruleId == null ? _Step.selectAccounts : _Step.manage);
      case _Step.editAccounts:
      case _Step.remove:
        _show(_Step.manage);
      default:
        _ruleId = null;
        _firstCode = null;
        _selected.clear();
        _show(_Step.overview);
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
    final code = _entry;
    if (_step == _Step.newPasscode) {
      _firstCode = code;
      _show(_Step.confirmPasscode);
      return;
    }
    if (_step == _Step.confirmPasscode) {
      if (code != _firstCode) {
        _firstCode = null;
        _show(_Step.newPasscode);
        _fail((l10n) => l10n.passcodesDidNotMatch);
        return;
      }
      _firstCode = null;
      await _save(
        newPasscode: code,
        accountIds: _ruleId == null ? _selected : null,
      );
      return;
    }

    final step = _step;
    final revision = ++_revision;
    bool current() => mounted && revision == _revision;
    final session = ref.read(appSecurityProvider);
    if (!session.isUnlocked) return;
    setState(() => _busy = true);
    try {
      final proof = await ref
          .read(mobilePasscodeAuthProvider)
          .check(
            code: code,
            biometricReason: context.l10n.onboardingUnlockBiometricReason,
            isCurrent: current,
            management: step == _Step.manageAuth,
            walletOnly: step != _Step.manageAuth,
            selectedRule: step == _Step.manageWallet ? _ruleId : null,
          );
      if (!mounted ||
          !current() ||
          !identical(session, ref.read(appSecurityProvider))) {
        return;
      }
      if (step == _Step.confirmBiometricChange) {
        context.pop(true);
        return;
      }
      if (step == _Step.createAuth) {
        _ruleId = null;
        _selected.clear();
        _show(_Step.selectAccounts);
        return;
      }
      _ruleId = proof.ruleId;
      _show(proof.needsWalletPasscode ? _Step.manageWallet : _Step.manage);
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

  Future<void> _save({
    String? newPasscode,
    Set<String>? accountIds,
    bool remove = false,
  }) async {
    final revision = ++_revision;
    bool current() => mounted && revision == _revision;
    final before = ref.read(accountProvider).value?.activeAccountUuid;
    setState(() => _busy = true);
    try {
      final rule = await ref
          .read(mobileAccountVisibilityProvider.notifier)
          .change(
            isCurrent: current,
            ruleId: _ruleId,
            accountIds: accountIds == null ? null : Set.of(accountIds),
            newPasscode: newPasscode,
            remove: remove,
          );
      if (!current()) return;
      final active = ref.read(accountProvider).value?.activeAccountUuid;
      if (active != null && before != active) {
        unawaited(_refreshSelection());
      }
      _ruleId = rule?.id;
      _show(remove ? _Step.overview : _Step.manage);
    } on MobileAccountVisibilityEditException catch (error) {
      if (!current()) return;
      if (newPasscode != null) _show(_Step.newPasscode);
      _fail(switch (error.failure) {
        MobileAccountVisibilityEditFailure.differentPasscode =>
          (l10n) => l10n.accountVisibilityDifferentPasscode,
        MobileAccountVisibilityEditFailure.keepOrdinary =>
          (l10n) => l10n.accountVisibilityKeepOrdinary,
        MobileAccountVisibilityEditFailure.selectAccounts =>
          (l10n) => l10n.accountVisibilitySelectAccount,
      });
    } catch (_) {
      if (!current()) return;
      if (newPasscode != null) _show(_Step.newPasscode);
      _fail((l10n) => l10n.accountVisibilityUpdateFailed);
    }
  }

  Future<void> _refreshSelection() async {
    try {
      await ref.read(accountProvider.notifier).restoreAfterUnlock();
      if (mounted && ref.read(appSecurityProvider).isUnlocked) {
        await ref.read(syncProvider.notifier).refreshAfterAccountSwitch();
      }
    } catch (_) {
      // The assignment has committed. Normal sync rehydrates the display.
    }
  }

  Widget _keypad() {
    final l10n = context.l10n;
    final title = switch (_step) {
      _Step.manageAuth => l10n.accountVisibilityEnterSeparatePasscode,
      _Step.newPasscode => l10n.accountVisibilityNewPasscode,
      _Step.confirmPasscode => l10n.passcodeConfirmTitle,
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
      subtitle: l10n.passcodeSixDigits,
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
                      l10n.passcodeSixDigits,
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

  Widget _row(String label, String icon, VoidCallback action) => MobileListRow(
    leading: AppIcon(icon, size: AppIconSize.large),
    label: label,
    showChevron: true,
    onTap: _busy ? null : action,
  );

  Widget _content() {
    final l10n = context.l10n;
    final config = ref.watch(mobileAccountVisibilityProvider);
    final accounts =
        ref.watch(accountProvider).value?.accounts ?? const <AccountInfo>[];
    final rule = config.rule(_ruleId);
    return switch (_step) {
      _Step.overview => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.accountVisibilityDescription,
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          _row(
            l10n.accountVisibilityCreate,
            AppIcons.plus,
            () => _show(_Step.createAuth),
          ),
          _row(
            l10n.accountVisibilityManage,
            AppIcons.lock,
            () => _show(_Step.manageAuth),
          ),
        ],
      ),
      _Step.manage when rule != null => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.accountVisibilityAccounts, style: AppTypography.labelLarge),
          for (final account in accounts)
            if (rule.accountIds.contains(account.uuid))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Text(account.name, style: AppTypography.bodyLarge),
              ),
          const SizedBox(height: AppSpacing.md),
          _row(l10n.accountVisibilityEditAccounts, AppIcons.users, () {
            _selected
              ..clear()
              ..addAll(rule.accountIds);
            _show(_Step.editAccounts);
          }),
          _row(
            l10n.accountVisibilityChange,
            AppIcons.lock,
            () => _show(_Step.newPasscode),
          ),
          _row(
            l10n.accountVisibilityDelete,
            AppIcons.trash,
            () => _show(_Step.remove),
          ),
        ],
      ),
      _Step.selectAccounts || _Step.editAccounts => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.accountVisibilityAccountChoice,
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.s),
          for (final account in accounts)
            if (config.allows(account.uuid, null) ||
                (rule?.accountIds.contains(account.uuid) ?? false))
              CheckboxListTile(
                key: ValueKey('account_visibility_choice_${account.uuid}'),
                contentPadding: EdgeInsets.zero,
                title: Text(account.name, style: AppTypography.labelLarge),
                value: _selected.contains(account.uuid),
                onChanged: _busy
                    ? null
                    : (selected) {
                        setState(() {
                          if (selected == true) {
                            _selected.add(account.uuid);
                          } else {
                            _selected.remove(account.uuid);
                          }
                          _error = null;
                        });
                      },
              ),
        ],
      ),
      _Step.remove => Text(
        l10n.accountVisibilityDeleteBody,
        style: AppTypography.bodyMedium,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  VoidCallback? _footerAction() => switch (_step) {
    _Step.selectAccounts => () {
      final ordinaryCount = ref
          .read(accountProvider)
          .requireValue
          .accounts
          .where(
            (account) => ref
                .read(mobileAccountVisibilityProvider)
                .allows(account.uuid, null),
          )
          .length;
      if (_selected.isEmpty) {
        _fail((l10n) => l10n.accountVisibilitySelectAccount);
      } else if (_selected.length == ordinaryCount) {
        _fail((l10n) => l10n.accountVisibilityKeepOrdinary);
      } else {
        _show(_Step.newPasscode);
      }
    },
    _Step.editAccounts => () => unawaited(_save(accountIds: _selected)),
    _Step.remove => () => unawaited(_save(remove: true)),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final action = _footerAction();
    final title = switch (_step) {
      _Step.selectAccounts => l10n.accountVisibilityCreate,
      _Step.manage => l10n.accountVisibilityManageTitle,
      _Step.editAccounts => l10n.accountVisibilityEditAccounts,
      _Step.remove => l10n.accountVisibilityDelete,
      _Step.confirmBiometricChange => l10n.settingsSectionSystem,
      _ => l10n.accountVisibilityTitle,
    };
    return PopScope(
      canPop:
          _step == _Step.overview ||
          (!_busy && _step == _Step.confirmBiometricChange),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(title: title, titleMaxLines: 2, onBack: _back),
              Expanded(
                child: _usesKeypad
                    ? _keypad()
                    : ListView(
                        padding: const EdgeInsets.all(kMobilePageMargin),
                        children: [
                          _content(),
                          if (_error case final error?)
                            Text(error(l10n), style: AppTypography.bodyMedium),
                        ],
                      ),
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kMobilePageMargin,
                    AppSpacing.s,
                    kMobilePageMargin,
                    AppSpacing.md,
                  ),
                  child: AppButton(
                    expand: true,
                    onPressed: _busy ? null : action,
                    child: Text(switch (_step) {
                      _Step.selectAccounts => l10n.commonContinue,
                      _Step.remove => l10n.accountVisibilityDelete,
                      _ => l10n.commonSave,
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
