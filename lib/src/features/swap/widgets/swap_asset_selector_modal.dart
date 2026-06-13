import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_models.dart';
import 'swap_asset_icon.dart';
import 'swap_modal_controls.dart';

class SwapAssetSelectorModal extends StatefulWidget {
  const SwapAssetSelectorModal({
    required this.assets,
    required this.selected,
    required this.onSelected,
    this.initialQuery = '',
    super.key,
  });

  final List<SwapAsset> assets;
  final SwapAsset selected;
  final ValueChanged<SwapAsset> onSelected;
  final String initialQuery;

  @override
  State<SwapAssetSelectorModal> createState() => _SwapAssetSelectorModalState();
}

class _SwapAssetSelectorModalState extends State<SwapAssetSelectorModal> {
  static const _modalSurfaceShadows = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
    BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode(debugLabel: 'SwapAssetSelectorSearch');
    _scrollController = ScrollController();
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final assets = _filteredAssets;
    final hasQuery = _queryController.text.isNotEmpty;
    final searchBorderColor = _focusNode.hasFocus || hasQuery
        ? colors.border.medium
        : colors.border.regular;

    // On mobile the swap modal route wraps this in the shared
    // MobileModalCard (ground surface, radius 32, bottom-anchored), so the
    // surface is full-width, draws no card, and the list scrolls within a
    // bounded height that the card hugs. Desktop keeps the fixed card.
    final isMobile = kAppFormFactor == AppFormFactor.mobile;

    return Container(
      key: const ValueKey('swap_external_asset_menu'),
      width: isMobile ? double.infinity : 312,
      height: isMobile ? null : 440,
      // Container requires a decoration to clip; the mobile card (with no
      // decoration here) is clipped by the MobileModalCard surface.
      clipBehavior: isMobile ? Clip.none : Clip.antiAlias,
      // Desktop fills to the card edge (bottom 0); mobile hugs, so the
      // content needs its own bottom breathing room.
      padding: EdgeInsets.fromLTRB(16, 24, 16, isMobile ? AppSpacing.md : 0),
      decoration: isMobile
          ? null
          : BoxDecoration(
              color: colors.background.base,
              borderRadius: BorderRadius.circular(AppRadii.large),
              boxShadow: _modalSurfaceShadows,
            ),
      child: Column(
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SwapModalIconBadge(
                iconName: AppIcons.coins,
                iconColor: colors.icon.regular,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select asset',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: colors.background.ground,
              border: Border.all(color: searchBorderColor, width: 1.5),
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AppIcon(
                      AppIcons.search,
                      size: 20,
                      color: colors.icon.accent,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      key: const ValueKey('swap_asset_search_field'),
                      controller: _queryController,
                      focusNode: _focusNode,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                      cursorColor: colors.text.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: 'Search token or chain',
                        hintStyle: AppTypography.labelLarge.copyWith(
                          color: colors.text.muted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasQuery)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SwapInlineIconButton(
                      key: const ValueKey('swap_asset_search_clear_button'),
                      iconName: AppIcons.cross,
                      onTap: _clearQuery,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _swapAssetListArea(
            isMobile,
            bounded: assets.isNotEmpty,
            child: assets.isEmpty
                ? Center(
                    child: SizedBox(
                      width: 112,
                      child: Text(
                        'No tokens or chains found',
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
                    thumbVisibility: assets.length > 5,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 3,
                    crossAxisMargin: 3,
                    thumbColor: colors.background.overlay,
                    child: Padding(
                      key: const ValueKey('swap_asset_selector_list_gutter'),
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          shrinkWrap: isMobile,
                          itemCount: assets.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.xxs),
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

/// Desktop fills the fixed-height card with the list ([Expanded]); mobile
/// lets the card hug its content, so a populated list scrolls within a
/// bounded height ([ConstrainedBox] + a shrink-wrapped list), matching the
/// other mobile list sheets. The empty state ([bounded] false) hugs its
/// text instead of reserving the full bound.
Widget _swapAssetListArea(
  bool mobile, {
  bool bounded = true,
  required Widget child,
}) {
  if (!mobile) return Expanded(child: child);
  if (bounded) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: child,
    );
  }
  return child;
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
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.background.neutralSubtleOpacity : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              SwapAssetIcon(
                asset: asset,
                selected: selected,
                size: 32,
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
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
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
