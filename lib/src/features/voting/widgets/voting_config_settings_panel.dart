import 'package:flutter/services.dart'
    show SystemMouseCursors, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_config_source_provider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_service_providers.dart';
import '../../../providers/voting/voting_submission_guard_provider.dart';
import '../../../services/voting/voting_config_loader.dart';
import '../../../services/voting/voting_models.dart';

class VotingConfigSettingsPanel extends ConsumerStatefulWidget {
  const VotingConfigSettingsPanel({
    this.onClose,
    this.onUpdated,
    this.width = 560,
    super.key,
  });

  final VoidCallback? onClose;
  final VoidCallback? onUpdated;
  final double width;

  @override
  ConsumerState<VotingConfigSettingsPanel> createState() =>
      _VotingConfigSettingsPanelState();
}

class _VotingConfigSettingsPanelState
    extends ConsumerState<VotingConfigSettingsPanel> {
  static const _maxSourceNameLength = 15;

  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  String? _editingSourceId;
  bool _showEditor = false;
  bool _isSubmitting = false;
  String? _submitError;
  String? _validationField;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  bool get _isEditing => _editingSourceId != null;

  void _startAdd() {
    setState(() {
      _editingSourceId = null;
      _showEditor = true;
      _nameController.clear();
      _urlController.clear();
      _submitError = null;
      _validationField = null;
    });
  }

  void _startEdit(SavedVotingConfigSource source) {
    setState(() {
      _editingSourceId = source.id;
      _showEditor = true;
      _nameController.text = source.name;
      _urlController.text = source.sourceUrl;
      _nameController.selection = TextSelection.collapsed(
        offset: _nameController.text.length,
      );
      _urlController.selection = TextSelection.collapsed(
        offset: _urlController.text.length,
      );
      _submitError = null;
      _validationField = null;
    });
  }

  void _cancelEditor() {
    setState(() {
      _editingSourceId = null;
      _showEditor = false;
      _nameController.clear();
      _urlController.clear();
      _submitError = null;
      _validationField = null;
    });
  }

  String? _nameMessage() {
    final name = _nameController.text.trim();
    if (_validationField == 'name' && _submitError != null) {
      return _submitError;
    }
    if (name.length > _maxSourceNameLength) {
      return 'Title must be $_maxSourceNameLength characters or less.';
    }
    return null;
  }

  String? _urlMessage(VotingConfigSourceState source) {
    if (_validationField == 'url' && _submitError != null) {
      return _submitError;
    }
    final trimmed = _urlController.text.trim();
    if (trimmed.isEmpty) return null;
    try {
      parseStaticVotingConfigSource(trimmed);
    } on StaticVotingConfigSourceMalformed catch (error) {
      return error.message;
    }
    return _duplicateMessage(trimmed, source, excludingId: _editingSourceId);
  }

  bool _canSaveEditor(VotingConfigSourceState source) {
    if (_isSubmitting || !_showEditor) return false;
    if (ref.read(votingSubmissionGuardProvider).isNotEmpty) return false;
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.length > _maxSourceNameLength || url.isEmpty) return false;
    try {
      parseStaticVotingConfigSource(url);
    } on StaticVotingConfigSourceMalformed {
      return false;
    }
    return _duplicateMessage(url, source, excludingId: _editingSourceId) ==
        null;
  }

  Future<void> _saveEditor() async {
    final source = ref.read(votingConfigSourceProvider).value;
    if (source == null || !_canSaveEditor(source)) return;
    if (_blockIfVotingSubmissionInProgress()) return;
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _validationField = null;
    });

    try {
      await _validateSource(url);
      await ref
          .read(votingConfigSourceProvider.notifier)
          .saveSource(id: _editingSourceId, name: name, sourceUrl: url);
      await _refreshAndClose();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = _messageFromError(error);
        _validationField = 'url';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _useDefault(VotingConfigSourceState source) async {
    if (_isSubmitting || source.isDefault) return;
    if (_blockIfVotingSubmissionInProgress()) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _validationField = null;
    });

    try {
      await ref.read(votingConfigSourceProvider.notifier).resetDefault();
      await _refreshAndClose();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = _messageFromError(error);
        _validationField = null;
        _isSubmitting = false;
      });
    }
  }

  Future<void> _useSaved(SavedVotingConfigSource saved) async {
    if (_isSubmitting) return;
    if (_blockIfVotingSubmissionInProgress()) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _validationField = null;
    });

    try {
      await _validateSource(saved.sourceUrl);
      await ref
          .read(votingConfigSourceProvider.notifier)
          .setCustom(saved.sourceUrl);
      await _refreshAndClose();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = _messageFromError(error);
        _validationField = null;
        _isSubmitting = false;
      });
    }
  }

  Future<void> _deleteSaved(SavedVotingConfigSource saved) async {
    if (_isSubmitting) return;
    if (_blockIfVotingSubmissionInProgress()) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _validationField = null;
    });

    try {
      final source = ref.read(votingConfigSourceProvider).value;
      final wasActive =
          source != null &&
          !source.isDefault &&
          _sameSourceUrl(source.sourceUrl, saved.sourceUrl);
      await ref
          .read(votingConfigSourceProvider.notifier)
          .deleteSavedSource(saved.id);
      if (wasActive) {
        await _refreshAndClose();
      } else if (mounted) {
        setState(() {
          _isSubmitting = false;
          if (_editingSourceId == saved.id) {
            _editingSourceId = null;
            _showEditor = false;
            _nameController.clear();
            _urlController.clear();
            _submitError = null;
            _validationField = null;
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = _messageFromError(error);
        _validationField = null;
        _isSubmitting = false;
      });
    }
  }

  bool _blockIfVotingSubmissionInProgress() {
    final guards = ref.read(votingSubmissionGuardProvider);
    if (guards.isEmpty) return false;
    setState(() {
      _submitError = guards.first.message;
      _validationField = null;
      _isSubmitting = false;
    });
    return true;
  }

  Future<void> _validateSource(String input) async {
    final parsed = parseStaticVotingConfigSource(input);
    await VotingConfigLoader(
      httpClient: ref.read(votingHttpClientProvider),
      sourceUrl: parsed.raw,
    ).load();
  }

  Future<void> _refreshAndClose() async {
    ref.invalidate(votingConfigProvider);
    await ref.read(votingRoundsProvider.notifier).reload();
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
    });
    widget.onUpdated?.call();
  }

  String? _duplicateMessage(
    String input,
    VotingConfigSourceState source, {
    String? excludingId,
  }) {
    if (_sameSourceUrl(input, kDefaultStaticVotingConfigSource)) {
      return 'This source URL is already added.';
    }
    for (final saved in source.savedSources) {
      if (saved.id == excludingId) continue;
      if (_sameSourceUrl(input, saved.sourceUrl)) {
        return 'This source URL is already added.';
      }
    }
    return null;
  }

  String _messageFromError(Object error) {
    if (error is StaticVotingConfigSourceMalformed) return error.message;
    if (error is VotingHttpException) {
      return "Couldn't load voting config from that source.";
    }
    final text = error.toString().trim();
    return text.isEmpty ? "Couldn't update voting config." : text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sourceState = ref.watch(votingConfigSourceProvider);
    final submissionInProgress = ref
        .watch(votingSubmissionGuardProvider)
        .isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.width,
          maxHeight: MediaQuery.sizeOf(context).height - AppSpacing.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: sourceState.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: AppIcon(AppIcons.loader)),
            ),
            error: (error, _) =>
                _PanelError(message: error.toString(), onClose: widget.onClose),
            data: (source) {
              final nameMessage = _nameMessage();
              final urlMessage = _urlMessage(source);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PanelHeader(onClose: widget.onClose),
                  const SizedBox(height: AppSpacing.xs),
                  _CurrentSourceText(source: source),
                  if (_submitError != null && _validationField == null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _submitError!,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SourceCard(
                            title: 'Coinholder poll',
                            sourceUrl: kDefaultStaticVotingConfigSource,
                            isDefault: true,
                            selected: source.isDefault,
                            onUse: source.isDefault || submissionInProgress
                                ? null
                                : () => _useDefault(source),
                          ),
                          for (final saved in source.savedSources) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _SourceCard(
                              title: saved.name,
                              sourceUrl: saved.sourceUrl,
                              selected:
                                  !source.isDefault &&
                                  _sameSourceUrl(
                                    source.sourceUrl,
                                    saved.sourceUrl,
                                  ),
                              onUse:
                                  submissionInProgress ||
                                      (!source.isDefault &&
                                          _sameSourceUrl(
                                            source.sourceUrl,
                                            saved.sourceUrl,
                                          ))
                                  ? null
                                  : () => _useSaved(saved),
                              onEdit: submissionInProgress
                                  ? null
                                  : () => _startEdit(saved),
                              onDelete: submissionInProgress
                                  ? null
                                  : () => _deleteSaved(saved),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          if (_showEditor)
                            _EditorCard(
                              isEditing: _isEditing,
                              nameController: _nameController,
                              urlController: _urlController,
                              nameMessage: nameMessage,
                              urlMessage: urlMessage,
                              isSubmitting: _isSubmitting,
                              canSave: _canSaveEditor(source),
                              onChanged: () => setState(() {
                                _submitError = null;
                                _validationField = null;
                              }),
                              onCancel: _cancelEditor,
                              onSave: _saveEditor,
                            )
                          else
                            AppButton(
                              onPressed: _isSubmitting || submissionInProgress
                                  ? null
                                  : _startAdd,
                              variant: AppButtonVariant.secondary,
                              minWidth: 220,
                              leading: const AppIcon(AppIcons.addNew),
                              child: const Text('Add custom source'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CurrentSourceText extends StatelessWidget {
  const _CurrentSourceText({required this.source});

  final VotingConfigSourceState source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = source.isDefault
        ? 'Default'
        : _compactSourceUrl(source.sourceUrl);
    return Text.rich(
      TextSpan(
        text: 'Current: ',
        children: [
          TextSpan(
            text: label,
            style: TextStyle(color: colors.text.brandCrimson),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.sourceUrl,
    required this.selected,
    this.isDefault = false,
    this.onUse,
    this.onEdit,
    this.onDelete,
  });

  final String title;
  final String sourceUrl;
  final bool selected;
  final bool isDefault;
  final VoidCallback? onUse;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? colors.background.raised : colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(
          color: selected ? colors.border.medium : colors.border.subtle,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SelectionIndicator(selected: selected),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        _DefaultBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _compactSourceUrl(sourceUrl),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (onEdit != null)
              _SmallIconButton(
                icon: AppIcons.options,
                semanticLabel: 'Edit saved source',
                onTap: onEdit!,
              ),
            if (onDelete != null)
              _SmallIconButton(
                icon: AppIcons.trash,
                semanticLabel: 'Delete saved source',
                onTap: onDelete!,
              ),
            AppButton(
              onPressed: onUse,
              variant: selected
                  ? AppButtonVariant.secondary
                  : AppButtonVariant.primary,
              size: AppButtonSize.small,
              minWidth: 64,
              child: Text(selected ? 'Active' : 'Use'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.isEditing,
    required this.nameController,
    required this.urlController,
    required this.nameMessage,
    required this.urlMessage,
    required this.isSubmitting,
    required this.canSave,
    required this.onChanged,
    required this.onCancel,
    required this.onSave,
  });

  final bool isEditing;
  final TextEditingController nameController;
  final TextEditingController urlController;
  final String? nameMessage;
  final String? urlMessage;
  final bool isSubmitting;
  final bool canSave;
  final VoidCallback onChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? 'Edit custom source' : 'Add custom source',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: nameMessage == null ? 66 : 82,
              child: AppTextField(
                label: 'Title',
                controller: nameController,
                autofocus: !isEditing,
                trailingSlotWidth: 40,
                inputHorizontalPadding: AppSpacing.s,
                textInputAction: TextInputAction.next,
                messageText: nameMessage,
                tone: nameMessage == null
                    ? AppTextFieldTone.neutral
                    : AppTextFieldTone.destructive,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: urlMessage == null ? 66 : 82,
              child: AppTextField(
                label: 'Static config URL',
                controller: urlController,
                trailingSlotWidth: 40,
                inputHorizontalPadding: AppSpacing.s,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                messageText: urlMessage,
                tone: urlMessage == null
                    ? AppTextFieldTone.neutral
                    : AppTextFieldTone.destructive,
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSave(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppButton(
                  onPressed: isSubmitting ? null : onCancel,
                  variant: AppButtonVariant.secondary,
                  minWidth: 128,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  onPressed: canSave ? onSave : null,
                  variant: AppButtonVariant.primary,
                  minWidth: 160,
                  trailing: const AppIcon(AppIcons.chevronForward),
                  child: Text(isSubmitting ? 'Validating...' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.icon.brandCrimson : colors.background.ground,
        border: Border.all(
          color: selected ? colors.icon.brandCrimson : colors.border.medium,
        ),
      ),
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: selected
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.ground,
                  ),
                  child: const SizedBox(width: 8, height: 8),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.neutralStrongOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: 2,
        ),
        child: Text(
          'Default',
          style: AppTypography.labelSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              'Voting config',
              style: AppTypography.headlineMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          if (onClose != null)
            Positioned(
              right: 0,
              child: _SmallIconButton(
                icon: AppIcons.cross,
                semanticLabel: 'Close voting config settings',
                onTap: onClose!,
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  const _PanelError({required this.message, this.onClose});

  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelHeader(onClose: onClose),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.destructive,
          ),
        ),
      ],
    );
  }
}

class _SmallIconButton extends StatefulWidget {
  const _SmallIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? colors.button.ghost.bgHover
                    : colors.background.ground.withValues(alpha: 0),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(
                    widget.icon,
                    size: AppIconSize.medium,
                    color: colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }
}

String _compactSourceUrl(String raw) {
  final trimmed = raw.trim();
  try {
    final source = parseStaticVotingConfigSource(trimmed);
    final path = source.uri.path.replaceFirst(RegExp(r'^/'), '');
    return path.isEmpty ? source.uri.host : '${source.uri.host}/$path';
  } on StaticVotingConfigSourceMalformed {
    return trimmed;
  }
}

bool _sameSourceUrl(String lhs, String rhs) {
  try {
    final left = parseStaticVotingConfigSource(lhs.trim());
    final right = parseStaticVotingConfigSource(rhs.trim());
    return left.uri == right.uri && left.sha256Hex == right.sha256Hex;
  } on StaticVotingConfigSourceMalformed {
    return lhs.trim() == rhs.trim();
  }
}
