import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../models/swap_models.dart';
import '../swap_asset_icon.dart';
import '../swap_modal_controls.dart';
import '../../../../../l10n/app_localizations.dart';

/// Mobile asset picker — built on [MobileModalScaffold] with the asset
/// `_Modal Type` variant (8px title-to-body gap, no bottom inset) so the
/// scrolling list fills to the card edge. The list keeps a STABLE viewport
/// height — it doesn't grow/shrink as the search filters results — bounded by
/// the space above the keyboard so its bottom and scrollbar stay on screen.
/// State logic is ported from the shared [SwapAssetSelectorModal]; the
/// constructor adds [onClose] for the scaffold's close button.
class MobileSwapAssetSelectorModal extends StatefulWidget {
  const MobileSwapAssetSelectorModal({
    required this.assets,
    required this.selected,
    required this.onSelected,
    required this.onClose,
    this.initialQuery = '',
    super.key,
  });

  final List<SwapAsset> assets;
  final SwapAsset selected;
  final ValueChanged<SwapAsset> onSelected;
  final VoidCallback onClose;
  final String initialQuery;

  @override
  State<MobileSwapAssetSelectorModal> createState() =>
      _MobileSwapAssetSelectorModalState();
}

class _MobileSwapAssetSelectorModalState
    extends State<MobileSwapAssetSelectorModal> {
  // Mobile row: the 40px mobile asset icon needs a taller row than the
  // desktop 44/32.
  static const double _rowHeight = 52;
  static const double _rowGap = AppSpacing.xxs; // 4
  static const double _scrollbarGutter = AppSpacing.sm;
  static const double _scrollbarThickness = 6;

  /// Stable scroll-viewport bounds: at least ~4 rows so a sparse (or empty)
  /// result set doesn't collapse the modal, at most ~7 rows of travel before
  /// it scrolls.
  static const double _minListHeight = _rowHeight * 4 + _rowGap * 3; // 188
  static const double _maxListHeight = _rowHeight * 7 + _rowGap * 6; // 332

  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode(debugLabel: 'MobileSwapAssetSelectorSearch');
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _clearQuery() {
    if (_queryController.text.isEmpty) return;
    setState(() => _queryController.clear());
    _focusNode.requestFocus();
  }

  List<SwapAsset> get _filteredAssets {
    final query = _queryController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.assets;
    return [
      for (final asset in widget.assets)
        if (asset.symbol.toLowerCase().contains(query) ||
            asset.displayName.toLowerCase().contains(query) ||
            asset.chainLabel.toLowerCase().contains(query) ||
            asset.railLabel.toLowerCase().contains(query))
          asset,
    ];
  }

  /// The scroll viewport height: a stable [_minListHeight].._maxListHeight,
  /// further capped to the room above the keyboard so the list bottom and its
  /// scrollbar stay on screen.
  double _listHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    // Reserve for the title, the search field, the inter-element gaps and the
    // card's own top/bottom margins.
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.top - 220;
    return available.clamp(_minListHeight, _maxListHeight);
  }

  double _listContentHeight(int itemCount) {
    if (itemCount <= 0) return 0;
    return itemCount * _rowHeight + (itemCount - 1) * _rowGap;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final assets = _filteredAssets;
    final hasQuery = _queryController.text.isNotEmpty;
    final listHeight = _listHeight(context);
    final listContentHeight = _listContentHeight(assets.length);
    final showScrollbar = listContentHeight > listHeight;

    return MobileModalScaffold(
      key: const ValueKey('swap_external_asset_menu'),
      title: AppLocalizations.of(context).swapSelectAsset,
      onClose: widget.onClose,
      // Asset `_Modal Type` variant: 8px title-to-body gap; a small bottom
      // inset so the list isn't flush against the card edge.
      bodyGap: AppSpacing.xs,
      bottomPadding: AppSpacing.s,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MobileTextField(
            fieldKey: const ValueKey('swap_asset_search_field'),
            controller: _queryController,
            focusNode: _focusNode,
            hintText: AppLocalizations.of(context).swapSearchTokenOrChain,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            leading: SizedBox(
              width: AppInputSizing.iconWrapWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: AppIcon(
                  AppIcons.search,
                  size: AppInputSizing.iconSize,
                  color: colors.icon.accent,
                ),
              ),
            ),
            trailing: hasQuery
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SwapInlineIconButton(
                      key: const ValueKey('swap_asset_search_clear_button'),
                      iconName: AppIcons.cross,
                      onTap: _clearQuery,
                      size: AppInputSizing.iconSize,
                    ),
                  )
                : null,
          ),
          // The _Modal Type Field reserves an (opacity-0) error line, so the
          // search sits ~24px above the list.
          const SizedBox(height: 24),
          SizedBox(
            height: listHeight,
            child: assets.isEmpty
                ? Center(
                    child: SizedBox(
                      width: 112,
                      child: Text(
                        AppLocalizations.of(context).swapNoTokensFound,
                        textAlign: TextAlign.center,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                  )
                : RawScrollbar(
                    key: const ValueKey('swap_asset_selector_scrollbar'),
                    controller: _scrollController,
                    thumbVisibility: showScrollbar,
                    interactive: true,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: _scrollbarThickness,
                    mainAxisMargin: 0,
                    padding: EdgeInsets.zero,
                    crossAxisMargin:
                        (_scrollbarGutter - _scrollbarThickness) / 2,
                    thumbColor: colors.background.overlay,
                    child: Padding(
                      key: const ValueKey('swap_asset_selector_list_gutter'),
                      padding: const EdgeInsets.only(right: _scrollbarGutter),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.separated(
                          controller: _scrollController,
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: assets.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: _rowGap),
                          itemBuilder: (context, index) {
                            final asset = assets[index];
                            return _AssetMenuRow(
                              asset: asset,
                              selected: widget.selected == asset,
                              onTap: () => widget.onSelected(asset),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssetMenuRow extends StatelessWidget {
  const _AssetMenuRow({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final SwapAsset asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_asset_row_${asset.identityKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: _MobileSwapAssetSelectorModalState._rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: selected ? colors.background.neutralSubtleOpacity : null,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Row(
            children: [
              SwapAssetIcon(
                asset: asset,
                selected: selected,
                // Mobile asset size (40) with the composer's 0.5/0.1 badge so
                // the chain mark stays the same 20px circle.
                size: AppAssetSize.size,
                badgeScale: 0.5,
                overhangScale: 0.1,
                showChainBadge: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      asset.chainLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
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
