import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
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
    // Spec: the 1.5dp border slot is transparent at rest and only paints the
    // active token (Border/Neutral/medium) when the field is focused or filled.
    final searchBorderColor = _focusNode.hasFocus || hasQuery
        ? colors.border.medium
        : colors.border.medium.withValues(alpha: 0);

    return Container(
      key: const ValueKey('swap_external_asset_menu'),
      width: 312,
      height: 440,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appModalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Select asset',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
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
                      // Inputs/Field master: typed value Label M Medium,
                      // placeholder Label M Regular (Geist 14/16, -0.06).
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                      cursorColor: colors.text.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: 'Search token or chain',
                        hintStyle: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w400,
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
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: SizedBox(
                      width: 112,
                      child: Text(
                        'No tokens or chains found',
                        textAlign: TextAlign.center,
                        // Spec: Label M Regular (Geist 14/16, weight 400).
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w400,
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
                          itemCount: assets.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.xs),
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
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.background.neutralSubtleOpacity : null,
            borderRadius: BorderRadius.circular(AppRadii.small),
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
                      // Spec: chain name is Label M Regular (Geist 14/16, -0.06,
                      // weight 400) — same metrics as the ticker above, regular
                      // weight. labelMedium would be 13/14 Medium, which is wrong.
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w400,
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
