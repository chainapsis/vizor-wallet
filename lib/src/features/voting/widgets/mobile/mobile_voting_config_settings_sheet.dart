import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../providers/voting/voting_config_provider.dart';
import '../../../../providers/voting/voting_config_source_provider.dart';
import '../../../../providers/voting/voting_round_visibility_provider.dart';
import '../../../../providers/voting/voting_rounds_provider.dart';
import '../../../../providers/voting/voting_service_providers.dart';
import '../../../../providers/voting/voting_submission_guard_provider.dart';
import '../../../../services/voting/voting_config_loader.dart';

Future<void> showMobileVotingConfigSettingsSheet(BuildContext context) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (_) => const MobileVotingConfigSettingsSheet(),
  );
}

/// Mobile presentation for the shared voting-config providers. Desktop keeps
/// its pane modal; this sheet follows the app's floating mobile modal system.
class MobileVotingConfigSettingsSheet extends ConsumerStatefulWidget {
  const MobileVotingConfigSettingsSheet({super.key});

  @override
  ConsumerState<MobileVotingConfigSettingsSheet> createState() =>
      _MobileVotingConfigSettingsSheetState();
}

class _MobileVotingConfigSettingsSheetState
    extends ConsumerState<MobileVotingConfigSettingsSheet> {
  static const _maxSourceNameLength = 15;

  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  bool _showEditor = false;
  String? _editingSourceId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _selectSource({required String url, required bool isDefault}) {
    return _runMutation(() async {
      if (isDefault) {
        await ref.read(votingConfigSourceProvider.notifier).resetDefault();
      } else {
        await _validateSource(url);
        await ref.read(votingConfigSourceProvider.notifier).setCustom(url);
      }
      await _refreshVoting();
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _saveSource() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || name.length > _maxSourceNameLength || url.isEmpty) {
      setState(() {
        _error = name.length > _maxSourceNameLength
            ? 'Title must be $_maxSourceNameLength characters or less.'
            : 'Enter a title and source URL.';
      });
      return;
    }
    await _runMutation(() async {
      await _validateSource(url);
      await ref
          .read(votingConfigSourceProvider.notifier)
          .saveSource(id: _editingSourceId, name: name, sourceUrl: url);
      await _refreshVoting();
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _openEditor([SavedVotingConfigSource? source]) {
    setState(() {
      _editingSourceId = source?.id;
      _nameController.text = source?.name ?? '';
      _urlController.text = source?.sourceUrl ?? '';
      _showEditor = true;
      _error = null;
    });
  }

  void _closeEditor() {
    setState(() {
      _editingSourceId = null;
      _nameController.clear();
      _urlController.clear();
      _showEditor = false;
      _error = null;
    });
  }

  Future<void> _deleteSource(SavedVotingConfigSource source) {
    return _runMutation(() async {
      await ref
          .read(votingConfigSourceProvider.notifier)
          .deleteSavedSource(source.id);
      await _refreshVoting();
    });
  }

  Future<void> _toggleTestRounds(bool enabled) {
    return _runMutation(() async {
      await ref
          .read(showTestVotingRoundsProvider.notifier)
          .setShowTestRounds(!enabled);
      await ref.read(votingRoundsProvider.notifier).reload();
    });
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    if (_busy) return;
    final guards = ref.read(votingSubmissionGuardProvider);
    if (guards.isNotEmpty) {
      setState(() => _error = guards.first.message);
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
      setState(() => _error = _friendlyError(error));
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

  String _friendlyError(Object error) {
    if (error is StaticVotingConfigSourceMalformed ||
        error is DuplicateVotingConfigSource) {
      return error.toString();
    }
    return "Couldn't update voting config. Check the source and try again.";
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(votingConfigSourceProvider);
    final testRounds = ref.watch(showTestVotingRoundsProvider);
    // The entire content can scroll when a keyboard, large text, or saved
    // sources consume the available sheet height. Parent constraints include
    // the modal's keyboard and safe-area margins.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        child: MobileModalScaffold(
          key: const ValueKey('mobile_voting_config_sheet'),
          title: 'Vote config',
          bodyGap: AppSpacing.xxs,
          bottomPadding: AppSpacing.base,
          onClose: () => Navigator.of(context).pop(),
          child: source.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: AppIcon(AppIcons.loader)),
            ),
            error: (error, _) => _LoadError(message: error.toString()),
            data: (state) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose where Vizor gets authenticated voting rounds.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  child: Text(
                    'Sources',
                    style: AppTypography.labelLarge.copyWith(
                      color: context.colors.text.secondary,
                      letterSpacing: -0.04,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                _MobileSourceRow(
                  key: const ValueKey('mobile_voting_source_default'),
                  title: 'Token holder voting',
                  subtitle: 'Default',
                  selected: state.isDefault,
                  onTap: _busy
                      ? null
                      : () => _selectSource(
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
                    selected:
                        !state.isDefault && state.sourceUrl == saved.sourceUrl,
                    onTap: _busy
                        ? null
                        : () => _selectSource(
                            url: saved.sourceUrl,
                            isDefault: false,
                          ),
                    onEdit: _busy ? null : () => _openEditor(saved),
                    onDelete: _busy ? null : () => _deleteSource(saved),
                  ),
                ],
                if (!state.isDefault &&
                    !state.savedSources.any(
                      (saved) => saved.sourceUrl == state.sourceUrl,
                    )) ...[
                  const SizedBox(height: AppSpacing.s),
                  _MobileSourceRow(
                    title: 'Custom source',
                    subtitle: _compactUrl(state.sourceUrl),
                    selected: true,
                  ),
                ],
                if (_showEditor) ...[
                  const SizedBox(height: AppSpacing.s),
                  AppTextField(
                    key: const ValueKey('mobile_voting_source_name'),
                    label: 'Title',
                    controller: _nameController,
                    enabled: !_busy,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppTextField(
                    key: const ValueKey('mobile_voting_source_url'),
                    label: 'Source URL',
                    controller: _urlController,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _error!,
                      key: const ValueKey('mobile_voting_config_error'),
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.destructive,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    key: const ValueKey('mobile_voting_source_save'),
                    expand: true,
                    onPressed: _busy ? null : _saveSource,
                    child: Text(_busy ? 'Saving...' : 'Save source'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    expand: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: _busy ? null : _closeEditor,
                    child: const Text('Cancel'),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.s),
                  _AddSourceCard(onTap: _busy ? null : _openEditor),
                ],
                const SizedBox(height: AppSpacing.base),
                _TestRoundsRow(
                  enabled: testRounds.value ?? false,
                  busy: _busy || testRounds.isLoading,
                  onTap: () => _toggleTestRounds(testRounds.value ?? false),
                ),
                if (_error != null && !_showEditor) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _error!,
                    key: const ValueKey('mobile_voting_config_error'),
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  key: const ValueKey('mobile_voting_config_close'),
                  expand: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSourceRow extends StatelessWidget {
  const _MobileSourceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.s,
            AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.04,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.04,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                Semantics(
                  label: 'Edit $title',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onEdit,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s),
                      child: AppIcon(
                        AppIcons.options,
                        size: 18,
                        color: colors.icon.regular,
                      ),
                    ),
                  ),
                ),
              if (onDelete != null)
                Semantics(
                  label: 'Delete $title',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s),
                      child: AppIcon(
                        AppIcons.trash,
                        size: 18,
                        color: colors.icon.regular,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                key: selected
                    ? const ValueKey('mobile_voting_source_selected')
                    : null,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? colors.background.inverse : null,
                  shape: BoxShape.circle,
                  border: selected
                      ? null
                      : Border.all(color: colors.border.medium, width: 1.5),
                ),
                child: selected
                    ? Center(
                        child: AppIcon(
                          AppIcons.check,
                          size: 16,
                          color: colors.text.inverse,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddSourceCard extends StatelessWidget {
  const _AddSourceCard({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: InkWell(
      key: const ValueKey('mobile_voting_add_source'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: CustomPaint(
        painter: _SourceCardBorder(context.colors.border.medium),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            'Add custom source',
            style: AppTypography.labelLarge.copyWith(
              color: onTap != null
                  ? context.colors.text.accent
                  : context.colors.text.secondary,
              letterSpacing: -0.04,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SourceCardBorder extends CustomPainter {
  const _SourceCardBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          const Radius.circular(AppRadii.medium),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 10) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SourceCardBorder oldDelegate) =>
      oldDelegate.color != color;
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
      label: 'Show test rounds',
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
                    'Show test rounds',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                      letterSpacing: -0.04,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Include authenticated rounds marked [TEST].',
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
  const _LoadError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
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
