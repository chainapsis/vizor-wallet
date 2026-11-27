import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../address_scan/widgets/address_qr_scan_modal.dart';
import '../delegate_mode_models.dart';
import '../delegate_mode_presentation.dart';
import '../delegate_mode_providers.dart';
import '../delegate_mode_repository.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/delegate_mode_widgets.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// Key import on desktop.
class DelegateKeyImportScreen extends StatelessWidget {
  /// Creates the screen.
  const DelegateKeyImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppDesktopShell(
      sidebar: AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: DelegateKeyImportView(showDesktopToolbar: true),
      ),
    );
  }
}

/// Import: a pasted, typed or scanned `zvdsk1…` export becomes the
/// device's key (contracts-v1 section 11.2). It is how a key moves to
/// another device or is recovered. Anything that is not an export is
/// refused without a network request.
class DelegateKeyImportView extends ConsumerStatefulWidget {
  /// Creates the view.
  const DelegateKeyImportView({required this.showDesktopToolbar, super.key});

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<DelegateKeyImportView> createState() =>
      _DelegateKeyImportViewState();
}

class _DelegateKeyImportViewState extends ConsumerState<DelegateKeyImportView> {
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;
  DelegateKeyInfo? _imported;
  late final SensitivePrivacyOverlayController _privacy;

  @override
  void initState() {
    super.initState();
    _privacy = ref.read(delegatePrivacyControllerFactoryProvider)();
  }

  @override
  void dispose() {
    _secret.dispose();
    _privacy.dispose();
    super.dispose();
  }

  /// Opens the QR scanner and imports what it reads.
  Future<void> _scan() async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Center(
        child: AddressQrScanModal(
          resolve: proxyScanResolver,
          title: context.l10n.delegateImportScanTitle,
          onAddressScanned: (value) => Navigator.of(dialogContext).pop(value),
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
    if (scanned == null || !mounted) return;
    _secret.text = scanned;
    await _import();
  }

  /// Imports the entered export.
  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final DelegateKeyInfo key;
    try {
      key = await ref
          .read(delegateModeRepositoryProvider)
          .importKey(_secret.text);
    } on DelegateKeyImportException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.delegateImportInvalid;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = delegateModeErrorCopy(context.l10n, error);
      });
      return;
    }
    if (!mounted) return;
    _secret.clear();
    invalidateDelegateMode(ref);
    setState(() {
      _busy = false;
      _imported = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final imported = _imported;
    if (imported != null) {
      final status = ref.watch(delegateModeStatusProvider).value;
      final registered = status?.registered ?? false;
      return ProxyPaneLayout(
        showDesktopToolbar: widget.showDesktopToolbar,
        title: context.l10n.delegateImportTitle,
        action: AppButton(
          key: const ValueKey('delegate_import_continue'),
          onPressed: status == null
              ? null
              : () => registered
                    ? context.go(kDelegateModePath)
                    : context.pushReplacement(kDelegateRegistrationPath),
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.commonContinue),
        ),
        child: Column(
          key: const ValueKey('delegate_imported'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProxyBodyText(context.l10n.delegateImportedTitle, strong: true),
            const SizedBox(height: AppSpacing.s),
            DelegateKeyLine(
              key: const ValueKey('delegate_imported_key'),
              keyInfo: imported,
              delegateIndex: status?.entry?.delegateIndex,
              label: context.l10n.delegateKeyLabel,
            ),
            if (status != null && !registered) ...[
              const SizedBox(height: AppSpacing.s),
              ProxyBodyText(context.l10n.delegateImportedUnregistered),
            ],
          ],
        ),
      );
    }
    final error = _error;
    return SensitivePrivacyOverlay(
      sensitiveContentVisible: _secret.text.isNotEmpty,
      controller: _privacy,
      child: ProxyPaneLayout(
        showDesktopToolbar: widget.showDesktopToolbar,
        title: context.l10n.delegateImportTitle,
        action: DelegateActionStack(
          children: [
            AppButton(
              key: const ValueKey('delegate_import_submit'),
              onPressed: _busy || _secret.text.trim().isEmpty ? null : _import,
              expand: true,
              growWithContent: true,
              constrainContent: true,
              child: Text(context.l10n.delegateImportLabel),
            ),
            AppButton(
              key: const ValueKey('delegate_import_scan'),
              onPressed: _busy ? null : _scan,
              variant: AppButtonVariant.secondary,
              expand: true,
              growWithContent: true,
              constrainContent: true,
              leading: const AppIcon(AppIcons.qr),
              child: Text(context.l10n.proxyScanLabel),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProxyBodyText(context.l10n.delegateImport),
            const SizedBox(height: AppSpacing.s),
            AppTextField(
              key: const ValueKey('delegate_import_key'),
              label: context.l10n.delegateImportFieldLabel,
              hintText: context.l10n.delegateImportHint,
              controller: _secret,
              minLines: 2,
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _error = null),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.s),
              ProxyNotice(
                key: const ValueKey('delegate_import_error'),
                message: error,
                tone: ProxyNoticeTone.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
