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
    this.loading = false,
    super.key,
  });

  final List<SwapAsset> assets;
  final SwapAsset selected;
  final ValueChanged<SwapAsset> onSelected;
  final String initialQuery;

  /// While true the list shows skeleton rows instead of assets — used on
  /// mobile during the first live (multi-chain) asset fetch.
  final bool loading;

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
    // Desktop opens straight into the search field (compact fixed card).
    // The mobile full-screen sheet opens at full height showing the most
    // assets; the keyboard is summoned only when the user taps search.
    if (kAppFormFactor != AppFormFactor.mobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
      });
    }
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
    final isMobile = kAppFormFactor == AppFormFactor.mobile;
    // The full-screen sheet body reaches the screen bottom, so the list
    // pads its scroll content by the home-indicator inset (read from the
    // raw view — the modal zeroes MediaQuery padding) instead of leaving a
    // visible gap that crops the last row.
    final listBottomInset = isMobile
        ? MediaQueryData.fromView(View.of(context)).padding.bottom
        : 0.0;

    final searchField = Container(
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
    );

    final Widget listChild = widget.loading
        ? const _AssetSelectorSkeleton()
        : assets.isEmpty
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
                  padding: EdgeInsets.only(bottom: listBottomInset),
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
          );

    if (isMobile) {
      // Chromeless body for the full-screen MobileSheetScaffold: the sheet
      // provides the grabber, "Select asset" title and close button, so
      // this fills the sheet with the search field and a list that expands
      // to the available height.
      return Padding(
        key: const ValueKey('swap_external_asset_menu'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.s,
          AppSpacing.sm,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchField,
            const SizedBox(height: AppSpacing.s),
            Expanded(child: listChild),
          ],
        ),
      );
    }

    // Desktop: fixed card with its own header, surface and shadow.
    return Container(
      key: const ValueKey('swap_external_asset_menu'),
      width: 312,
      height: 440,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _modalSurfaceShadows,
      ),
      child: Column(
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
          searchField,
          const SizedBox(height: 8),
          Expanded(child: listChild),
        ],
      ),
    );
  }
}

/// Placeholder rows shown while the live asset list is being fetched. A
/// gentle opacity pulse signals loading without a third-party shimmer dep.
class _AssetSelectorSkeleton extends StatefulWidget {
  const _AssetSelectorSkeleton();

  @override
  State<_AssetSelectorSkeleton> createState() => _AssetSelectorSkeletonState();
}

class _AssetSelectorSkeletonState extends State<_AssetSelectorSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: const ValueKey('swap_asset_selector_skeleton'),
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      // Lazily fills the available height: the list only builds the rows
      // that fit the viewport and clips the rest, so there's no blank gap
      // below and no overflow on short viewports.
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: 20,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xxs),
        itemBuilder: (_, _) => const _AssetSkeletonRow(),
      ),
    );
  }
}

class _AssetSkeletonRow extends StatelessWidget {
  const _AssetSkeletonRow();

  @override
  Widget build(BuildContext context) {
    final block = context.colors.background.neutralSubtleOpacity;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: block, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBar(color: block, width: 84, height: 12),
              const SizedBox(height: 6),
              _SkeletonBar(color: block, width: 120, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.color,
    required this.width,
    required this.height,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.full),
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
