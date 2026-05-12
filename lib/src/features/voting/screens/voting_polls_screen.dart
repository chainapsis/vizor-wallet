import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/navigation/app_back_resolver.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_routes.dart';

class VotingPollsScreen extends ConsumerStatefulWidget {
  const VotingPollsScreen({super.key});

  @override
  ConsumerState<VotingPollsScreen> createState() => _VotingPollsScreenState();
}

class _VotingPollsScreenState extends ConsumerState<VotingPollsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(votingRoundsProvider.notifier).startPolling();
    });
  }

  @override
  void dispose() {
    ref.read(votingRoundsProvider.notifier).stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rounds = ref.watch(votingRoundsProvider);
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _VotingTopBar(),
            Expanded(
              child: rounds.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _VotingMessage(
                  title: "Couldn't load polls",
                  message: error.toString(),
                  actionLabel: 'Try Again',
                  onAction: () =>
                      ref.read(votingRoundsProvider.notifier).refresh(),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const _VotingMessage(
                      title: 'No polls available',
                      message: 'There are no coinholder polls to display yet.',
                    );
                  }
                  final sortedItems = _sortRoundsByDate(items);
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          40,
                        ),
                        itemCount: sortedItems.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.base),
                        itemBuilder: (context, index) => _PollCard(
                          round: sortedItems[index],
                          onTap: () => context.push(
                            votingPollRoute(sortedItems[index].roundId),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VotingTopBar extends StatelessWidget {
  const _VotingTopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(left: AppSpacing.md, child: _VotingBackButton()),
          Text(
            'COINHOLDER POLLING',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.18,
            ),
          ),
        ],
      ),
    );
  }
}

class _VotingBackButton extends StatefulWidget {
  const _VotingBackButton();

  @override
  State<_VotingBackButton> createState() => _VotingBackButtonState();
}

class _VotingBackButtonState extends State<_VotingBackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = AppBackResolver.resolve(context);
    return Semantics(
      button: true,
      label: 'Back to ${target.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => target.navigate(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hovered ? colors.state.hover : null,
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Center(
              child: AppIcon(
                AppIcons.arrowBack,
                size: 20,
                color: colors.icon.accent,
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

class _PollCard extends StatelessWidget {
  const _PollCard({required this.round, required this.onTap});

  final VotingRoundView round;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = round.title.isEmpty ? round.roundId : round.title;
    final description = _roundDescription(round.rawJson);
    final dateRange = _roundDateRange(round.rawJson);

    return Material(
      color: const Color(0x00000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: colors.border.subtle),
            boxShadow: [
              BoxShadow(
                color: const Color(0x0A231F20),
                offset: const Offset(0, 1),
                blurRadius: 1,
                spreadRadius: -0.5,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusBadge(status: round.status),
                  const Spacer(),
                  if (dateRange != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        dateRange,
                        textAlign: TextAlign.right,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.secondary,
                          height: 20 / 14,
                          letterSpacing: -0.22,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                  height: 24 / 16,
                  letterSpacing: -0.26,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Poll Description',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.secondary,
                  height: 20 / 14,
                  letterSpacing: -0.22,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description.isEmpty ? round.roundId : description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.primary,
                  height: 20 / 14,
                  letterSpacing: -0.22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: _statusBackground(status),
        border: Border.all(color: _statusBorder(status)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.time, size: 14, color: _statusText(status)),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              color: _statusText(status),
              height: 20 / 14,
              letterSpacing: -0.08,
            ),
          ),
        ],
      ),
    );
  }
}

class _VotingMessage extends StatelessWidget {
  const _VotingMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: onAction,
                variant: AppButtonVariant.primary,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _roundDescription(Map<String, dynamic> json) {
  for (final key in const ['description', 'body', 'summary']) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

List<VotingRoundView> _sortRoundsByDate(List<VotingRoundView> rounds) {
  return [...rounds]..sort((a, b) {
    final aDate = _roundSortDate(a.rawJson);
    final bDate = _roundSortDate(b.rawJson);
    if (aDate == null && bDate == null) {
      return a.title.compareTo(b.title);
    }
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });
}

String? _roundDateRange(Map<String, dynamic> json) {
  final start = _dateFromJson(json, const [
    'start_date',
    'startDate',
    'starts_at',
    'startsAt',
    'open_date',
    'openDate',
    'opens_at',
    'opensAt',
    'start_time',
    'startTime',
    'starts',
    'start',
    'voting_start',
    'votingStart',
    'poll_start',
    'pollStart',
    'vote_start_time',
    'voteStartTime',
    'ceremony_phase_start',
    'ceremonyPhaseStart',
  ]);
  final end = _dateFromJson(json, const [
    'end_date',
    'endDate',
    'ends_at',
    'endsAt',
    'close_date',
    'closeDate',
    'closes_at',
    'closesAt',
    'end_time',
    'endTime',
    'ends',
    'end',
    'deadline',
    'voting_end',
    'votingEnd',
    'poll_end',
    'pollEnd',
    'vote_end_time',
    'voteEndTime',
  ]);
  if (start == null && end == null) return null;
  if (start == null) return 'Ends ${_formatPollDate(end!)}';
  if (end == null) return 'Starts ${_formatPollDate(start)}';
  if (_isSameDay(start, end)) return _formatPollDate(end);
  return '${_formatPollDate(start)} - ${_formatPollDate(end)}';
}

DateTime? _roundSortDate(Map<String, dynamic> json) {
  final start = _dateFromJson(json, const [
    'start_date',
    'startDate',
    'starts_at',
    'startsAt',
    'open_date',
    'openDate',
    'opens_at',
    'opensAt',
    'start_time',
    'startTime',
    'starts',
    'start',
    'voting_start',
    'votingStart',
    'poll_start',
    'pollStart',
    'vote_start_time',
    'voteStartTime',
    'ceremony_phase_start',
    'ceremonyPhaseStart',
    'created_at',
    'createdAt',
    'published_at',
    'publishedAt',
  ]);
  final end = _dateFromJson(json, const [
    'end_date',
    'endDate',
    'ends_at',
    'endsAt',
    'close_date',
    'closeDate',
    'closes_at',
    'closesAt',
    'end_time',
    'endTime',
    'ends',
    'end',
    'deadline',
    'voting_end',
    'votingEnd',
    'poll_end',
    'pollEnd',
    'vote_end_time',
    'voteEndTime',
  ]);
  return start ?? end;
}

DateTime? _dateFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _valueFromJson(json, key);
    final date = _parseDate(value);
    if (date != null) return date;
  }
  return null;
}

Object? _valueFromJson(Object? value, String key) {
  if (value is! Map) return null;
  if (value.containsKey(key)) return value[key];
  for (final entry in value.entries) {
    if (entry.key.toString() == key) return entry.value;
  }
  for (final entry in value.entries) {
    final nested = entry.value;
    if (nested is Map) {
      final match = _valueFromJson(nested, key);
      if (match != null) return match;
    }
  }
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final milliseconds = value > 100000000000
        ? value.toInt()
        : (value * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  final text = value.toString().trim();
  final numeric = num.tryParse(text);
  if (numeric != null) return _parseDate(numeric);
  return DateTime.tryParse(text);
}

String _formatPollDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}

bool _isSameDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

String _statusLabel(String value) {
  return switch (_pollStatus(value)) {
    _PollStatus.active => 'Active',
    _PollStatus.tallying => 'Tallying',
    _PollStatus.closed => 'Closed',
  };
}

Color _statusBackground(String value) {
  return switch (_pollStatus(value)) {
    _PollStatus.active => const Color(0xFFECFDF3),
    _PollStatus.tallying => const Color(0xFFFFFAEB),
    _PollStatus.closed => const Color(0xFFF4F4F0),
  };
}

Color _statusBorder(String value) {
  return switch (_pollStatus(value)) {
    _PollStatus.active => const Color(0xFFABEFC6),
    _PollStatus.tallying => const Color(0xFFFEDF89),
    _PollStatus.closed => const Color(0xFFEBEBE6),
  };
}

Color _statusText(String value) {
  return switch (_pollStatus(value)) {
    _PollStatus.active => const Color(0xFF067647),
    _PollStatus.tallying => const Color(0xFFB54708),
    _PollStatus.closed => const Color(0xFF716C5D),
  };
}

enum _PollStatus { active, tallying, closed }

_PollStatus _pollStatus(String value) {
  final status = value.trim().toLowerCase();
  if (status == '1') return _PollStatus.active;
  if (status == '2') return _PollStatus.tallying;
  if (status == '3') return _PollStatus.closed;
  if (status.contains('tally')) return _PollStatus.tallying;
  if (status.contains('closed') ||
      status.contains('complete') ||
      status.contains('done') ||
      status.contains('ended') ||
      status.contains('final') ||
      status.contains('result')) {
    return _PollStatus.closed;
  }
  return _PollStatus.active;
}
