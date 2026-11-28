import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_form_factor.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../address_scan/widgets/address_qr_scan_modal.dart';
import '../../voting_flow_models.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// How long typing pauses before the field is looked up.
const _findDelay = Duration(milliseconds: 250);

/// Opens the add-a-delegate dialog for [key]'s draft, a sheet on mobile,
/// and clears its lookup once it closes.
Future<void> showProxyAddDelegateDialog(
  BuildContext context,
  VotingSessionKey key,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    if (kAppFormFactor == AppFormFactor.mobile) {
      await showAppMobileSheet<void>(
        context: context,
        builder: (context) => MobileModalScaffold(
          title: context.l10n.proxyAddDialogTitle,
          onClose: () => Navigator.of(context).pop(),
          child: ProxyAddDelegateForm(sessionKey: key),
        ),
      );
      return;
    }
    final theme = context.appTheme;
    await showDialog<void>(
      context: context,
      barrierColor: theme.colors.background.neutralScrim,
      builder: (context) => UncontrolledProviderScope(
        container: container,
        child: AppTheme(
          data: theme,
          child: Dialog(
            backgroundColor: const Color(0x00000000),
            elevation: 0,
            insetPadding: const EdgeInsets.all(AppSpacing.md),
            child: _DesktopPanel(sessionKey: key),
          ),
        ),
      ),
    );
  } finally {
    if (container.exists(proxyDirectoryProvider(key))) {
      container.read(proxyDirectoryProvider(key).notifier).clearFind();
    }
  }
}

/// The desktop dialog's surface around [ProxyAddDelegateForm].
class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({required this.sessionKey});

  final VotingSessionKey sessionKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: const ValueKey('proxy_add_dialog'),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height - AppSpacing.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.proxyAddDialogTitle,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AppIconHoverButton(
                    icon: AppIcons.cross,
                    semanticLabel: context.l10n.commonClose,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: SingleChildScrollView(
                  child: ProxyAddDelegateForm(sessionKey: sessionKey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One field that finds a delegate who isn't on Vizor's list, by handle or
/// by a pasted or scanned key, number, fingerprint or marker post. Results
/// carry their number and fingerprint and the warnings a delegate Vizor
/// hasn't reviewed needs, and their checks add them to the draft.
class ProxyAddDelegateForm extends ConsumerStatefulWidget {
  /// Creates the form for [sessionKey]'s draft.
  const ProxyAddDelegateForm({required this.sessionKey, super.key});

  /// Round and account being delegated.
  final VotingSessionKey sessionKey;

  @override
  ConsumerState<ProxyAddDelegateForm> createState() =>
      _ProxyAddDelegateFormState();
}

class _ProxyAddDelegateFormState extends ConsumerState<ProxyAddDelegateForm> {
  final _field = TextEditingController();
  Timer? _pending;

  ProxyDirectoryNotifier get _directory =>
      ref.read(proxyDirectoryProvider(widget.sessionKey).notifier);

  @override
  void dispose() {
    _pending?.cancel();
    _field.dispose();
    super.dispose();
  }

  /// Looks the field up once typing pauses.
  void _changed(String text) {
    setState(() {});
    _pending?.cancel();
    _pending = Timer(_findDelay, () => _find(text));
  }

  /// Looks [text] up now.
  void _find(String text) {
    _pending?.cancel();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _directory.clearFind();
    } else {
      unawaited(_directory.find(trimmed));
    }
  }

  /// Opens the QR scanner and looks up what it reads.
  Future<void> _scan() async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Center(
        child: AddressQrScanModal(
          resolve: proxyScanResolver,
          title: context.l10n.proxyScanTitle,
          onAddressScanned: (value) => Navigator.of(dialogContext).pop(value),
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
    if (scanned == null || !mounted) return;
    _field.text = scanned;
    setState(() {});
    _find(scanned);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final key = widget.sessionKey;
    final state = ref.watch(proxyDirectoryProvider(key)).value;
    final draft = ref.watch(proxyAllocationDraftProvider(key));
    final draftNotifier = ref.read(proxyAllocationDraftProvider(key).notifier);
    final found = _found(l10n, state, _field.text.trim());
    final entries = found.entries;
    const gap = SizedBox(height: AppSpacing.xs);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(l10n.proxyAddDialogBody),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          key: const ValueKey('proxy_add_field'),
          label: l10n.proxyManualFieldLabel,
          showLabel: false,
          hintText: l10n.proxyManualFieldHint,
          controller: _field,
          autofocus: kAppFormFactor != AppFormFactor.mobile,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onSubmitted: _find,
          trailing: AppIconHoverButton(
            key: const ValueKey('proxy_add_scan'),
            icon: AppIcons.qr,
            semanticLabel: l10n.proxyScanTitle,
            size: 28,
            onTap: () => unawaited(_scan()),
          ),
          trailingSlotWidth: 40,
        ),
        if (found.loading) ...[
          const SizedBox(height: AppSpacing.s),
          const VotingPaneLoading(),
        ],
        if (found.message case final message?) ...[
          const SizedBox(height: AppSpacing.s),
          ProxyBodyText(message, key: const ValueKey('proxy_add_message')),
        ],
        if (entries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          ProxyDelegateGroup(
            rows: [
              for (final entry in entries)
                ProxyDelegateListRow(
                  entry: entry,
                  selected: draft.contains(entry.index),
                  showKey: true,
                  onToggle:
                      draft.contains(entry.index) ||
                          (!draft.isFull && !entry.blocked)
                      ? () => draftNotifier.toggle(entry)
                      : null,
                ),
            ],
          ),
          for (final entry in entries) ...[
            for (final notice in proxyDelegateNotices(l10n, entry)) ...[
              gap,
              notice,
            ],
            if (entry.newThisRound) ...[
              gap,
              ProxyNotice(message: l10n.proxyNewThisRound),
            ],
          ],
          if (draft.isFull &&
              entries.any((entry) => !draft.contains(entry.index))) ...[
            gap,
            ProxyNotice(message: l10n.proxyPickerFull),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const ValueKey('proxy_add_done'),
            onPressed: () => Navigator.of(context).pop(),
            expand: kAppFormFactor == AppFormFactor.mobile,
            minWidth: kAppFormFactor == AppFormFactor.mobile ? null : 120,
            child: Text(l10n.commonDone),
          ),
        ),
      ],
    );
  }
}

/// What the field found for [text]: delegates, a message, or a lookup still
/// running. Answers for older text are ignored.
({List<ProxyDelegateListing> entries, String? message, bool loading}) _found(
  AppLocalizations l10n,
  ProxyDirectoryState? state,
  String text,
) {
  const nothing = (
    entries: <ProxyDelegateListing>[],
    message: null,
    loading: false,
  );
  if (state == null || text.isEmpty) return nothing;
  const loading = (
    entries: <ProxyDelegateListing>[],
    message: null,
    loading: true,
  );
  ({List<ProxyDelegateListing> entries, String? message, bool loading}) say(
    String message,
  ) => (entries: const [], message: message, loading: false);
  final handle = proxyHandleQuery(text);
  return switch (state.lookup) {
    ProxyLookupRunning(text: final t) when t == text => loading,
    ProxyLookupFailed(text: final t, :final error) when t == text => say(
      proxyErrorCopy(l10n, error),
    ),
    ProxyLookupDone(text: final t, :final answer) when t == text =>
      switch (answer) {
        ApiDelegateLookup(:final listing?) => (
          entries: [listing],
          message: null,
          loading: false,
        ),
        ApiDelegateLookup(kind: ApiDelegateLookupKind.unrecognized) =>
          switch (state.search) {
            ProxySearchResults(:final query, :final entries)
                when query == handle =>
              entries.isEmpty
                  ? say(l10n.proxyNoSearchResults(handle))
                  : (entries: entries, message: null, loading: false),
            _ => loading,
          },
        _ => say(l10n.proxyLookupNotFound),
      },
    _ => nothing,
  };
}
