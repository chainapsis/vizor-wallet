import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/privacy/sensitive_privacy_overlay.dart';
import '../src/core/security/software_wallet_secret.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/features/settings/screens/settings_seed_phrase_screen.dart';
import '../src/features/settings/widgets/confirm_access_card.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/sync_provider.dart';

Widget buildDesktopBackupIntroCapture(BuildContext _) => const _BackupCapture();
Widget buildDesktopBackupGateCapture(BuildContext _) =>
    const _BackupCapture(stage: _CaptureStage.password);
Widget buildDesktopBackupRevealCapture(BuildContext _) =>
    const _BackupCapture(stage: _CaptureStage.reveal);
Widget buildDesktopBackupRevealBip39Capture(BuildContext _) =>
    const _BackupCapture(stage: _CaptureStage.reveal, includeBip39: true);
Widget buildDesktopBackupSaveErrorBip39Capture(BuildContext _) =>
    const _BackupCapture(
      stage: _CaptureStage.reveal,
      includeBip39: true,
      saveError: true,
    );
Widget buildDesktopBackupSaveErrorCapture(BuildContext _) =>
    const _BackupCapture(stage: _CaptureStage.reveal, saveError: true);
Widget buildDesktopBackupSavePendingCapture(BuildContext _) =>
    const _BackupCapture(stage: _CaptureStage.reveal, savePending: true);
Widget buildDesktopBackupDeferErrorCapture(BuildContext _) =>
    const _BackupCapture(saveError: true);
Widget buildDesktopBackupDeferPendingCapture(BuildContext _) =>
    const _BackupCapture(savePending: true);
Widget buildDesktopSettingsPhraseCapture(BuildContext _) =>
    const _BackupCapture(stage: _CaptureStage.reveal, backupPending: false);

enum _CaptureStage { intro, password, reveal }

/// Drives the production screen with local credentials, secrets and saves.
/// Words are deliberately masked fixture content, never a usable wallet seed.
class _BackupCapture extends StatefulWidget {
  const _BackupCapture({
    this.stage = _CaptureStage.intro,
    this.backupPending = true,
    this.saveError = false,
    this.savePending = false,
    this.includeBip39 = false,
  });

  final _CaptureStage stage;
  final bool backupPending;
  final bool saveError;
  final bool savePending;
  final bool includeBip39;

  @override
  State<_BackupCapture> createState() => _BackupCaptureState();
}

class _BackupCaptureState extends State<_BackupCapture> {
  final _save = Completer<void>();
  final _privacy = SensitivePrivacyOverlayController(initiallySafe: true);
  late final _accounts = _CaptureAccounts(
    backupPending: widget.backupPending,
    includeBip39: widget.includeBip39,
    save: () {
      if (widget.saveError) throw StateError('Capture storage write');
      return _save.future;
    },
  );
  late final _router = GoRouter(
    initialLocation: widget.backupPending
        ? '/setup/backup'
        : '/settings/secret-passphrase',
    routes: [
      GoRoute(
        path: widget.backupPending
            ? '/setup/backup'
            : '/settings/secret-passphrase',
        builder: (_, _) => SettingsSeedPhraseScreen(
          accountUuid: 'capture-account',
          showBackupIntro:
              widget.backupPending && widget.stage == _CaptureStage.intro,
          privacyOverlayController: _privacy,
          birthdayHeightLoader: (_) async => 3428019,
          birthdayBlockTimeLoader: (_) async => 1785196800,
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );

  @override
  void initState() {
    super.initState();
    if (widget.stage == _CaptureStage.reveal) {
      _afterFrame(() {
        final gate = _find<ConfirmAccessCard>();
        assert(gate != null);
        gate!.controller.text = 'PreviewPassword1!';
        gate.onSubmit();
        if (widget.saveError || widget.savePending) {
          _pressWhenReady(const ValueKey('desktop_seed_backed_up'));
        }
      });
    } else if (widget.stage == _CaptureStage.intro &&
        (widget.saveError || widget.savePending)) {
      _pressWhenReady(const ValueKey('desktop_seed_backup_remind_later'));
    }
  }

  T? _find<T extends Widget>({Key? key}) {
    T? result;
    void visit(Element element) {
      final child = element.widget;
      if (child is T && (key == null || child.key == key)) result = child;
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return result;
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  void _pressWhenReady(Key key) => _afterFrame(() {
    final button = _find<AppButton>(key: key);
    if (button == null) {
      _pressWhenReady(key);
      return;
    }
    assert(button.onPressed != null);
    button.onPressed?.call();
  });

  @override
  void dispose() {
    if (!_save.isCompleted) _save.complete();
    _router.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.macosUtility.window,
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(() => _accounts),
        appSecurityProvider.overrideWith(_CaptureSecurity.new),
        syncProvider.overrideWith(_CaptureSync.new),
      ],
      child: Router.withConfig(config: _router),
    ),
  );
}

class _CaptureAccounts extends AccountNotifier {
  _CaptureAccounts({
    required this.backupPending,
    required this.includeBip39,
    required this.save,
  });
  final bool backupPending;
  final bool includeBip39;
  final Future<void> Function() save;

  @override
  FutureOr<AccountState> build() => AccountState(
    accounts: [
      AccountInfo(
        uuid: 'capture-account',
        name: 'Stormy Kestrel',
        order: 0,
        setupPending: backupPending,
      ),
    ],
    activeAccountUuid: 'capture-account',
  );

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String _,
  ) async => SoftwareWalletSecret(
    mnemonic: List.filled(24, '••••••').join(' '),
    bip39Passphrase: includeBip39 ? 'preview-only extra passphrase' : '',
  );

  @override
  Future<void> markBackedUp(String _) => save();

  @override
  Future<void> snoozeBackupReminder(String _, {DateTime? now}) => save();
}

class _CaptureSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  Future<bool> confirmPassword(String _) async => true;
}

class _CaptureSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'capture-account',
    hasAccountScopedData: true,
    totalBalance: BigInt.zero,
  );
}
