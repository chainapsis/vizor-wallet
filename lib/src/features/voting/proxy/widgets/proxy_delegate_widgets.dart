import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import '../../widgets/voting_metadata_widgets.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../delegate_picture.dart';
import '../proxy_delegation_copy.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_repository.dart';

/// Accepts any non-empty scan for a proxy field, after the same payload
/// cleanup an address scan gets. The field's own lookup or import validates
/// what was read.
Future<MobileScanOutcome> proxyScanResolver(String raw) async {
  final text = normalizeAddressScanPayload(raw);
  return text == null || text.isEmpty
      ? const MobileScanOutcome.rejected(null)
      : MobileScanOutcome.accepted(text);
}

/// The largest share of a [ProxyPaneLayout]'s height its pinned action
/// may take, so the body keeps some room. An action that can outgrow it
/// scrolls a part of itself, as the review's finality footer does.
const kProxyPinnedActionMaxShare = 0.8;

/// Shared frame for the delegator panes: the desktop toolbar and title, a
/// scrolling body capped at 560 px, and an optional pinned action of at
/// most [kProxyPinnedActionMaxShare] of the pane's height.
class ProxyPaneLayout extends StatelessWidget {
  /// Creates the frame.
  const ProxyPaneLayout({
    required this.showDesktopToolbar,
    required this.title,
    required this.child,
    this.action,
    this.toolbarLeading,
    super.key,
  });

  /// Desktop shows the toolbar and title; mobile gets both from its nav bar.
  final bool showDesktopToolbar;

  /// Pane title, shown on desktop only; null when [child] has its own.
  final String? title;

  /// Scrolling body.
  final Widget child;

  /// Pinned action below the body.
  final Widget? action;

  /// Replaces the toolbar's route-derived back link on desktop.
  final Widget? toolbarLeading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final action = this.action;
        return _layout(
          context,
          action == null
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight.isFinite
                        ? constraints.maxHeight * kProxyPinnedActionMaxShare
                        : double.infinity,
                  ),
                  child: action,
                ),
        );
      },
    );
  }

  /// The frame around [action], already capped in height.
  Widget _layout(BuildContext context, Widget? action) {
    if (!showDesktopToolbar) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: VotingPaneScrollView(
              maxWidth: 560,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.s,
                AppSpacing.sm,
                0,
              ),
              scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: child,
            ),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: action,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPaneToolbar(leading: toolbarLeading, backLinkMinWidth: 60),
        Expanded(
          child: VotingPaneScrollView(
            maxWidth: 560,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title case final title?) ...[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.displaySmall.copyWith(
                      color: context.colors.text.accent,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                child,
              ],
            ),
          ),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.md,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: action,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bordered surface used for every delegator card.
class ProxyCard extends StatelessWidget {
  /// Creates a card.
  const ProxyCard({required this.child, super.key});

  /// Card content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: child,
    );
  }
}

/// Tone of a [ProxyNotice].
enum ProxyNoticeTone { info, warning, error }

/// A short message with an icon and an optional action, never colour alone.
class ProxyNotice extends StatelessWidget {
  /// Creates a notice.
  const ProxyNotice({
    required this.message,
    this.tone = ProxyNoticeTone.info,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Text to show.
  final String message;

  /// Icon and colour.
  final ProxyNoticeTone tone;

  /// Action button label, shown with [onAction].
  final String? actionLabel;

  /// Action handler.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, color) = switch (tone) {
      ProxyNoticeTone.info => (AppIcons.help, colors.icon.regular),
      ProxyNoticeTone.warning => (AppIcons.warning, colors.icon.warning),
      ProxyNoticeTone.error => (
        AppIcons.warningCircle,
        colors.icon.destructive,
      ),
    };
    final textColor = tone == ProxyNoticeTone.error
        ? colors.text.destructive
        : colors.text.primary;
    final label = actionLabel;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(icon, size: AppIconSize.medium, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(color: textColor),
                ),
                if (label != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    onPressed: onAction,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    child: Text(label),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary body text used across the delegator screens.
class ProxyBodyText extends StatelessWidget {
  /// Creates the text.
  const ProxyBodyText(this.text, {this.strong = false, super.key});

  /// Text to show.
  final String text;

  /// Uses the accent colour and strong weight.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      text,
      style: strong
          ? AppTypography.bodyMediumStrong.copyWith(color: colors.text.accent)
          : AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
    );
  }
}

/// A 5x5 mirrored glyph derived from a fingerprint. Decorative: the
/// fingerprint text beside it is what screen readers announce.
class ProxyIdenticon extends StatelessWidget {
  /// Creates an identicon.
  const ProxyIdenticon({required this.fingerprint, this.size = 40, super.key});

  /// Fingerprint the glyph is drawn from.
  final String fingerprint;

  /// Edge length.
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = sha256.convert(utf8.encode(fingerprint)).bytes;
    final hue = (bytes[0] * 256 + bytes[1]) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.5, 0.48).toColor();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(size / 4),
          border: Border.all(color: context.colors.border.subtle),
        ),
        padding: EdgeInsets.all(size / 8),
        child: CustomPaint(painter: _IdenticonPainter(bytes, color)),
      ),
    );
  }
}

class _IdenticonPainter extends CustomPainter {
  _IdenticonPainter(this.bytes, this.color);

  final List<int> bytes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 5;
    final paint = Paint()..color = color;
    for (var row = 0; row < 5; row++) {
      for (var column = 0; column < 3; column++) {
        final bit = row * 3 + column;
        if ((bytes[2 + bit ~/ 8] >> (bit % 8)) & 1 == 0) continue;
        for (final x in {column, 4 - column}) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, row * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_IdenticonPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.bytes != bytes;
}

/// A delegate's wallet list picture once Rust decodes it, and the identicon
/// otherwise: while it loads, without a picture, or on any failure.
/// Decorative, like the identicon.
class ProxyDelegateAvatar extends ConsumerStatefulWidget {
  /// Creates the avatar.
  const ProxyDelegateAvatar({
    required this.fingerprint,
    this.picture,
    this.size = 40,
    super.key,
  });

  /// Fingerprint the identicon is drawn from.
  final String fingerprint;

  /// Vizor's list picture, if any.
  final ProxyDelegatePicture? picture;

  /// Edge length.
  final double size;

  @override
  ConsumerState<ProxyDelegateAvatar> createState() =>
      _ProxyDelegateAvatarState();
}

/// Loads the avatar's picture and owns its image handle.
class _ProxyDelegateAvatarState extends ConsumerState<ProxyDelegateAvatar> {
  /// This avatar's own handle to the decoded picture.
  ui.Image? _image;

  /// Bumped whenever the picture changes, so a stale load is dropped.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _show(widget.picture);
  }

  @override
  void didUpdateWidget(ProxyDelegateAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final picture = widget.picture;
    final old = oldWidget.picture;
    if (picture?.key != old?.key || !identical(picture?.webp, old?.webp)) {
      _release();
      _show(picture);
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  /// Shows [picture] at once when it is already decoded, and otherwise once
  /// its load finishes.
  void _show(ProxyDelegatePicture? picture) {
    if (picture == null) return;
    final generation = _generation;
    final cache = ref.read(delegatePictureCacheProvider);
    final cached = cache.cached(picture);
    if (cached != null) {
      _image = cached;
      return;
    }
    unawaited(
      cache.load(picture).then((image) {
        if (!mounted || generation != _generation) {
          image?.dispose();
          return;
        }
        setState(() => _image = image);
      }),
    );
  }

  /// Drops this avatar's handle and any load in flight.
  void _release() {
    _generation++;
    _image?.dispose();
    _image = null;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return ProxyIdenticon(fingerprint: widget.fingerprint, size: widget.size);
    }
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.size / 4),
        child: RawImage(
          image: image,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// A round check: empty while not chosen, filled with a tick once chosen,
/// and greyed out when it can't be chosen.
class ProxyCheckCircle extends StatelessWidget {
  /// Creates the check.
  const ProxyCheckCircle({
    required this.selected,
    this.enabled = true,
    super.key,
  });

  /// Whether the delegate is chosen.
  final bool selected;

  /// Whether an empty check can be ticked.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.background.inverse : null,
        border: selected
            ? null
            : Border.all(
                color: enabled ? colors.border.medium : colors.border.subtle,
                width: 1.5,
              ),
      ),
      child: selected
          ? AppIcon(AppIcons.check, color: colors.icon.inverse)
          : null,
    );
  }
}

/// One delegate in a list: picture, name, handle on its network and the
/// check. Tapping the row adds or removes the delegate.
class ProxyDelegateListRow extends StatelessWidget {
  /// Creates the row.
  const ProxyDelegateListRow({
    required this.entry,
    required this.selected,
    this.onToggle,
    this.showKey = false,
    super.key,
  });

  /// Delegate to show.
  final ProxyDelegateListing entry;

  /// Whether the delegate is chosen.
  final bool selected;

  /// Adds or removes the delegate; null when it can't be added, because
  /// the picker is full or the delegate is suspended or retired.
  final VoidCallback? onToggle;

  /// Shows the number and fingerprint, to compare with a delegate's post.
  final bool showKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final name = entry.displayName;
    final network = switch (entry.provider) {
      ProxyDelegateProvider.x => l10n.proxyProviderXLabel,
      ProxyDelegateProvider.gitHub => l10n.proxyProviderGitHubLabel,
    };
    final secondary = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
    );
    final onToggle = this.onToggle;
    return MergeSemantics(
      child: Semantics(
        button: true,
        checked: selected,
        enabled: onToggle != null,
        child: MouseRegion(
          cursor: onToggle == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('proxy_delegate_row_${entry.index}'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.s,
              ),
              child: Row(
                children: [
                  ProxyDelegateAvatar(
                    fingerprint: entry.key.fingerprint,
                    picture: entry.listPicture,
                    size: 36,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name ?? proxyListingName(entry),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        Text(
                          name == null
                              ? l10n.proxyOnNetwork(network)
                              : l10n.proxyHandleOnNetwork(
                                  entry.handle,
                                  network,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                        if (showKey)
                          Text(
                            formatProxyDelegateId(
                              entry.index,
                              entry.key.fingerprint,
                            ),
                            style: AppTypography.codeSmall.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  ProxyCheckCircle(
                    selected: selected,
                    enabled: onToggle != null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows in one surface, split by hairlines.
class ProxyDelegateGroup extends StatelessWidget {
  /// Creates the group.
  const ProxyDelegateGroup({required this.rows, super.key});

  /// The rows, in order.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: colors.border.subtle),
            row,
          ],
        ],
      ),
    );
  }
}

/// Identity block for a delegate: picture or identicon, Vizor's list name,
/// handle and key, plus its labels, the provider first. A delegate
/// Vizor's list does not name shows no name or picture.
class ProxyDelegateSummary extends StatelessWidget {
  /// Creates the block.
  const ProxyDelegateSummary({
    required this.entry,
    this.identiconSize = 40,
    this.trailing,
    super.key,
  });

  /// Delegate to show.
  final ProxyDelegateListing entry;

  /// Edge length of the picture or identicon.
  final double identiconSize;

  /// Widget after the text, for example a selection control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = entry.displayName;
    final labels = [
      switch (entry.provider) {
        ProxyDelegateProvider.x => context.l10n.proxyProviderXLabel,
        ProxyDelegateProvider.gitHub => context.l10n.proxyProviderGitHubLabel,
      },
      entry.reviewed
          ? context.l10n.proxyReviewedLabel
          : context.l10n.proxyNotReviewedLabel,
      if (entry.newThisRound) context.l10n.proxyNewThisRoundLabel,
    ];
    final handleStyle = name == null
        ? AppTypography.bodyMediumStrong
        : AppTypography.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProxyDelegateAvatar(
          fingerprint: entry.key.fingerprint,
          picture: entry.listPicture,
          size: identiconSize,
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null)
                Text(
                  name,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              Text(
                '@${entry.handle}',
                style: handleStyle.copyWith(
                  color: name == null
                      ? colors.text.accent
                      : colors.text.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatProxyDelegateId(entry.index, entry.key.fingerprint),
                style: AppTypography.codeSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final label in labels) VotingMetadataBadge(label),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          trailing!,
        ],
      ],
    );
  }
}

/// The notices a delegate's row and profile show under its summary: not
/// reviewed, a lookalike handle, and a suspended or retired delegate.
List<Widget> proxyDelegateNotices(
  AppLocalizations l10n,
  ProxyDelegateListing entry,
) {
  final lookalike = entry.lookalikeOf;
  return [
    if (!entry.reviewed && !entry.blocked)
      ProxyNotice(
        message: l10n.proxyNotReviewed,
        tone: ProxyNoticeTone.warning,
      ),
    if (lookalike != null)
      ProxyNotice(
        message: l10n.proxyLookalike(lookalike),
        tone: ProxyNoticeTone.warning,
      ),
    if (entry.blocked)
      ProxyNotice(
        message: proxyBlockedCopy(
          l10n,
          proxyListingName(entry),
          retired: entry.status == DelegateEntryStatus.retired,
        ),
        tone: ProxyNoticeTone.error,
      ),
  ];
}

/// The review's timing notice: when delegation closes, the 24 h notice,
/// and `tooLate`.
class ProxyDelegationTimingNotice extends StatelessWidget {
  /// Creates the notice.
  const ProxyDelegationTimingNotice({
    required this.now,
    required this.voteEnd,
    super.key,
  });

  /// Current time.
  final DateTime now;

  /// Authenticated `vote_end_time`.
  final DateTime voteEnd;

  @override
  Widget build(BuildContext context) {
    final window = proxyDelegationWindowAt(now: now, voteEnd: voteEnd);
    if (window == ProxyDelegationWindow.closed) {
      return ProxyNotice(
        key: const ValueKey('proxy_timing_too_late'),
        message: context.l10n.proxyTooLate,
        tone: ProxyNoticeTone.error,
      );
    }
    final l10n = context.l10n;
    final endsLine = l10n.proxyVotingEnds(formatProxyVoteEnd(l10n, voteEnd));
    if (window == ProxyDelegationWindow.open) {
      return ProxyNotice(
        key: const ValueKey('proxy_timing_open'),
        message: endsLine,
      );
    }
    return ProxyNotice(
      key: const ValueKey('proxy_timing_closing_soon'),
      message: l10n.proxyTimingWithClosingSoon(
        endsLine,
        l10n.proxyClosingSoon(
          proxyTimeLeftCopy(l10n, now: now, voteEnd: voteEnd),
        ),
      ),
      tone: ProxyNoticeTone.warning,
    );
  }
}
