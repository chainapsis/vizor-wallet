import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/l10n/untranslated_text_log.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_radio_card.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/widgets/untranslated_details.dart';
import '../../../../providers/voting/voting_config_provider.dart';
import '../../../../providers/voting/voting_config_source_provider.dart';
import '../../../../providers/voting/voting_round_visibility_provider.dart';
import '../../../../providers/voting/voting_rounds_provider.dart';
import '../../../../providers/voting/voting_service_providers.dart';
import '../../../../providers/voting/voting_submission_guard_provider.dart';
import '../../../../services/voting/voting_config_loader.dart';
import '../voting_config_error_text.dart';

Future<void> showMobileVotingConfigSettingsSheet(BuildContext context) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (_) => const MobileVotingConfigSettingsSheet(),
  );
}

/// Mobile presentation for the shared voting-config providers. Desktop keeps
/// its pane modal; this sheet follows the app's floating mobile modal system.
///
/// Three levels, so each sheet holds one decision: this one names the active
/// source in a Settings-style row and keeps the test-round switch; the source
/// row opens [MobileVotingSourceSheet], whose choice applies with one Update;
/// a custom source is added or edited in [MobileVotingCustomSourceSheet].
class MobileVotingConfigSettingsSheet extends ConsumerStatefulWidget {
  const MobileVotingConfigSettingsSheet({super.key});

  @override
  ConsumerState<MobileVotingConfigSettingsSheet> createState() =>
      _MobileVotingConfigSettingsSheetState();
}

class _MobileVotingConfigSettingsSheetState
    extends ConsumerState<MobileVotingConfigSettingsSheet>
    with _VotingConfigMutations {
  Future<void> _toggleTestRounds(bool enabled) {
    // The switch ticks as it flips, before the rounds reload.
    unawaited(AppHaptics.selection());
    return _runMutation(() async {
      await ref
          .read(showTestVotingRoundsProvider.notifier)
          .setShowTestRounds(!enabled);
      await ref.read(votingRoundsProvider.notifier).reload();
    });
  }

  Future<void> _openSources() => showAppMobileSheet<void>(
    context: context,
    builder: (_) => const MobileVotingSourceSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(votingConfigSourceProvider);
    final testRounds = ref.watch(showTestVotingRoundsProvider);
    final colors = context.colors;
    return _VotingConfigSheetFrame(
      child: MobileModalScaffold(
        key: const ValueKey('mobile_voting_config_sheet'),
        title: context.l10n.votingConfigMobileTitle,
        bodyGap: AppSpacing.xxs,
        onClose: () => Navigator.of(context).pop(),
        child: source.when(
          loading: () => const _VotingConfigLoading(),
          error: (error, _) {
            logUntranslatedText(error.toString());
            return _LoadError(
              message: context.l10n.votingConfigSettingsLoadFailed,
              details: error.toString(),
            );
          },
          data: (state) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.votingConfigMobileIntro,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // A Settings row: the label left, the active source and a
              // chevron right; the choice lives one sheet down.
              MobileSurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: MobileListRow(
                  key: const ValueKey('mobile_voting_config_source_row'),
                  label: context.l10n.votingConfigSource,
                  value: _sourceLabel(context, state),
                  minRowHeight: _settingsRowHeight,
                  textStyle: AppTypography.labelLarge,
                  valueTextStyle: AppTypography.labelLarge,
                  valueColor: colors.text.accent,
                  chevronColor: colors.icon.muted,
                  chevronSize: _settingsChevronSize,
                  showChevron: true,
                  enabled: !_busy,
                  onTap: _busy ? null : () => unawaited(_openSources()),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _TestRoundsRow(
                enabled: testRounds.value ?? false,
                busy: _busy || testRounds.isLoading,
                onTap: () => _toggleTestRounds(testRounds.value ?? false),
              ),
              ..._errorLines(context),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('mobile_voting_config_close'),
                expand: true,
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.commonClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The active source's name: Default, a saved source's title, or Custom
/// source for an unsaved URL.
String _sourceLabel(BuildContext context, VotingConfigSourceState state) {
  if (state.isDefault) return context.l10n.commonDefault;
  for (final saved in state.savedSources) {
    if (saved.sourceUrl == state.sourceUrl) return saved.name;
  }
  return context.l10n.votingConfigCustomSource;
}

/// Second level of Vote config: where Vizor gets its rounds. A tap marks a
/// source and Update applies it, as on the private query server sheet. Custom
/// sources are added and edited one level down.
class MobileVotingSourceSheet extends ConsumerStatefulWidget {
  const MobileVotingSourceSheet({super.key});

  @override
  ConsumerState<MobileVotingSourceSheet> createState() =>
      _MobileVotingSourceSheetState();
}

class _MobileVotingSourceSheetState
    extends ConsumerState<MobileVotingSourceSheet>
    with _VotingConfigMutations {
  /// The marked source until Update applies it; null shows the active one.
  ({String url, bool isDefault})? _pending;

  bool _isSelected(
    VotingConfigSourceState state, {
    required String url,
    required bool isDefault,
  }) {
    final pending = _pending;
    if (pending != null) {
      return pending.isDefault == isDefault &&
          (isDefault || pending.url == url);
    }
    return state.isDefault == isDefault &&
        (isDefault || state.sourceUrl == url);
  }

  void _mark({required String url, required bool isDefault}) => setState(() {
    _pending = (url: url, isDefault: isDefault);
    _error = null;
  });

  /// Applies the marked source, or just closes when nothing changed.
  Future<void> _update(VotingConfigSourceState state) async {
    final pending = _pending;
    if (pending == null ||
        (pending.isDefault
            ? state.isDefault
            : !state.isDefault && pending.url == state.sourceUrl)) {
      Navigator.of(context).pop();
      return;
    }
    await _runMutation(() async {
      if (pending.isDefault) {
        await ref.read(votingConfigSourceProvider.notifier).resetDefault();
      } else {
        await _validateSource(pending.url);
        await ref
            .read(votingConfigSourceProvider.notifier)
            .setCustom(pending.url);
      }
      await _refreshVoting();
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _openCustom([SavedVotingConfigSource? source]) async {
    await showAppMobileSheet<void>(
      context: context,
      builder: (_) => MobileVotingCustomSourceSheet(source: source),
    );
    // A saved source becomes the active one, so show that again.
    if (mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(votingConfigSourceProvider);
    return _VotingConfigSheetFrame(
      child: MobileModalScaffold(
        key: const ValueKey('mobile_voting_source_sheet'),
        title: context.l10n.votingConfigSource,
        onClose: () => Navigator.of(context).pop(),
        child: source.when(
          loading: () => const _VotingConfigLoading(),
          error: (error, _) {
            logUntranslatedText(error.toString());
            return _LoadError(
              message: context.l10n.votingConfigSettingsLoadFailed,
              details: error.toString(),
            );
          },
          data: (state) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MobileSourceRow(
                key: const ValueKey('mobile_voting_source_default'),
                title: context.l10n.votingTokenHolderTitle,
                subtitle: context.l10n.commonDefault,
                selected: _isSelected(
                  state,
                  url: kDefaultStaticVotingConfigSource,
                  isDefault: true,
                ),
                onTap: _busy
                    ? null
                    : () => _mark(
                        url: kDefaultStaticVotingConfigSource,
                        isDefault: true,
                      ),
              ),
              for (final saved in state.savedSources) ...[
                const SizedBox(height: AppSpacing.s),
                _MobileSourceRow(
                  key: ValueKey('mobile_voting_source_${saved.id}'),
                  title: saved.name,
                  subtitle: _compactUrl(saved.sourceUrl),
                  selected: _isSelected(
                    state,
                    url: saved.sourceUrl,
                    isDefault: false,
                  ),
                  onTap: _busy
                      ? null
                      : () => _mark(url: saved.sourceUrl, isDefault: false),
                  onEdit: _busy ? null : () => unawaited(_openCustom(saved)),
                ),
              ],
              if (!state.isDefault &&
                  !state.savedSources.any(
                    (saved) => saved.sourceUrl == state.sourceUrl,
                  )) ...[
                const SizedBox(height: AppSpacing.s),
                _MobileSourceRow(
                  title: context.l10n.votingConfigCustomSource,
                  subtitle: _compactUrl(state.sourceUrl),
                  selected: _isSelected(
                    state,
                    url: state.sourceUrl,
                    isDefault: false,
                  ),
                  onTap: _busy
                      ? null
                      : () => _mark(url: state.sourceUrl, isDefault: false),
                ),
              ],
              ..._errorLines(context),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('mobile_voting_source_update'),
                expand: true,
                constrainContent: true,
                onPressed: _busy ? null : () => unawaited(_update(state)),
                child: Text(
                  _busy
                      ? context.l10n.commonUpdating
                      : context.l10n.commonUpdate,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              AppButton(
                key: const ValueKey('mobile_voting_add_source'),
                expand: true,
                constrainContent: true,
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : () => unawaited(_openCustom()),
                leading: const AppIcon(AppIcons.addNew),
                child: Text(context.l10n.votingConfigAddCustomSource),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Third level of Vote config: a custom source's title and URL. Saving
/// checks the source, then makes it the active one.
class MobileVotingCustomSourceSheet extends ConsumerStatefulWidget {
  const MobileVotingCustomSourceSheet({this.source, super.key});

  /// The saved source to edit; null adds a new one.
  final SavedVotingConfigSource? source;

  @override
  ConsumerState<MobileVotingCustomSourceSheet> createState() =>
      _MobileVotingCustomSourceSheetState();
}

class _MobileVotingCustomSourceSheetState
    extends ConsumerState<MobileVotingCustomSourceSheet>
    with _VotingConfigMutations {
  static const _maxSourceNameLength = 15;

  late final _nameController = TextEditingController(
    text: widget.source?.name ?? '',
  );
  late final _urlController = TextEditingController(
    text: widget.source?.sourceUrl ?? '',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || name.length > _maxSourceNameLength || url.isEmpty) {
      setState(() {
        _error = name.length > _maxSourceNameLength
            ? context.l10n.votingConfigTitleTooLong(_maxSourceNameLength)
            : context.l10n.votingConfigEnterTitleAndUrl;
      });
      return;
    }
    await _runMutation(() async {
      await _validateSource(url);
      await ref
          .read(votingConfigSourceProvider.notifier)
          .saveSource(id: widget.source?.id, name: name, sourceUrl: url);
      await _refreshVoting();
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _delete(SavedVotingConfigSource source) {
    return _runMutation(() async {
      await ref
          .read(votingConfigSourceProvider.notifier)
          .deleteSavedSource(source.id);
      await _refreshVoting();
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return _VotingConfigSheetFrame(
      child: MobileModalScaffold(
        key: const ValueKey('mobile_voting_custom_source_sheet'),
        title: source == null
            ? context.l10n.votingConfigCustomSource
            : context.l10n.votingConfigEditCustomSource,
        onClose: () => Navigator.of(context).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const ValueKey('mobile_voting_source_name'),
              label: context.l10n.votingConfigFieldTitle,
              controller: _nameController,
              enabled: !_busy,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.s),
            AppTextField(
              key: const ValueKey('mobile_voting_source_url'),
              label: context.l10n.votingConfigMobileFieldUrl,
              controller: _urlController,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _error = null),
            ),
            ..._errorLines(context),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('mobile_voting_source_save'),
              expand: true,
              constrainContent: true,
              onPressed: _busy ? null : _save,
              child: Text(
                _busy
                    ? context.l10n.votingConfigSaving
                    : context.l10n.votingConfigMobileSave,
              ),
            ),
            if (source != null) ...[
              const SizedBox(height: AppSpacing.s),
              AppButton(
                key: const ValueKey('mobile_voting_source_delete'),
                expand: true,
                constrainContent: true,
                variant: AppButtonVariant.ghost,
                enabledLabelColor: context.colors.text.destructive,
                onPressed: _busy ? null : () => unawaited(_delete(source)),
                leading: const AppIcon(AppIcons.trash),
                child: Text(context.l10n.votingConfigDeleteSaved),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the three Vote config sheets share: one change at a time, none
/// while a vote is being submitted, and the error shown in the sheet that
/// made the change.
mixin _VotingConfigMutations<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _busy = false;
  String? _errorText;

  /// Untranslated text behind [_error]; any new error clears it.
  String? _errorDetails;
  String? get _error => _errorText;
  set _error(String? value) {
    _errorText = value;
    _errorDetails = null;
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    if (_busy) return;
    final guards = ref.read(votingSubmissionGuardProvider);
    if (guards.isNotEmpty) {
      setState(() => _error = guards.first.message.text(context.l10n));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _errorDetails = votingConfigSourceErrorDetails(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _validateSource(String input) async {
    final parsed = parseStaticVotingConfigSource(input);
    await VotingConfigLoader(
      httpClient: ref.read(votingHttpClientProvider),
      sourceUrl: parsed.raw,
    ).load();
  }

  Future<void> _refreshVoting() async {
    await ref.read(votingConfigProvider.notifier).refresh();
    await ref.read(votingRoundsProvider.notifier).reload();
  }

  String _friendlyError(Object error) => votingConfigSourceErrorText(
    context.l10n,
    error,
    fallback: context.l10n.votingConfigMobileUpdateFailed,
  );

  List<Widget> _errorLines(BuildContext context) {
    final error = _error;
    if (error == null) return const [];
    return [
      const SizedBox(height: AppSpacing.s),
      Text(
        error,
        key: const ValueKey('mobile_voting_config_error'),
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.destructive,
        ),
      ),
      ...untranslatedDetailsButton(
        _errorDetails,
        alignment: AlignmentDirectional.centerStart,
      ),
    ];
  }
}

/// The content can scroll when a keyboard, large text or saved sources take
/// the sheet's height; the parent constraints include the modal's keyboard
/// and safe-area margins.
class _VotingConfigSheetFrame extends StatelessWidget {
  const _VotingConfigSheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    child: child,
  );
}

class _VotingConfigLoading extends StatelessWidget {
  const _VotingConfigLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 220,
    child: Center(child: AppIcon(AppIcons.loader)),
  );
}

// The Settings rows' metrics, for the source row.
const _settingsRowHeight = 60.0;
const _settingsChevronSize = 20.0;

class _MobileSourceRow extends StatelessWidget {
  const _MobileSourceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.onEdit,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  /// Opens the source in the custom source sheet, where it can also be
  /// deleted.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget action(String label, String icon, VoidCallback onPressed) =>
        Semantics(
          label: label,
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s),
              child: AppIcon(icon, size: 18, color: colors.icon.regular),
            ),
          ),
        );
    final onEdit = this.onEdit;
    return MobileRadioCard(
      title: title,
      details: [subtitle],
      selected: selected,
      onTap: onTap,
      actions: [
        if (onEdit != null)
          action(
            context.l10n.votingConfigEditNamed(title),
            AppIcons.edit,
            onEdit,
          ),
      ],
    );
  }
}

class _TestRoundsRow extends StatelessWidget {
  const _TestRoundsRow({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: context.l10n.votingConfigShowTestRounds,
      toggled: enabled,
      enabled: !busy,
      onTap: busy ? null : onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('mobile_voting_show_test_rounds'),
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.votingConfigShowTestRounds,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                      letterSpacing: -0.04,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.votingConfigMobileTestRoundsHint,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              key: const ValueKey('mobile_voting_test_rounds_toggle'),
              duration: const Duration(milliseconds: 140),
              width: 64,
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: enabled
                    ? colors.background.brandCrimsonStrong
                    : colors.background.overlay,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment: enabled
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.full),
                    ),
                  ),
                  child: SizedBox(width: 40, height: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            ...untranslatedDetailsButton(details),
          ],
        ),
      ),
    );
  }
}

String _compactUrl(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.host.isEmpty) return source;
  return '${uri.host}${uri.path}';
}
