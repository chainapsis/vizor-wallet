import 'package:flutter/widgets.dart';

import '../../layout/mobile/app_mobile_sheet.dart';
import '../../theme/app_theme.dart';

const _addressVerifyChunkTextStyle = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);
const _addressVerifyChunksPerLine = 5;
const _addressVerifyChunkGap = 12.0;
const _addressVerifyLineHorizontalInset = 10.0;

/// Chunked mobile address verification sheet — Figma `Verify Address`
/// (4731:96657): identity title on top, the address split into 5-character
/// chunks, and a Cancel action.
Future<void> showMobileAddressVerifySheet(
  BuildContext context, {
  required String title,
  required String address,
  Widget? leading,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      final chunks = _chunkAddress(address);
      final chunkLines = _chunkAddressLines(chunks);
      return MobileModalScaffold(
        title: title,
        leading: leading,
        titleStyle: AppTypography.labelLarge.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.text.accent,
        ),
        bodyGap: AppSpacing.md,
        bottomPadding: AppSpacing.base,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              key: const ValueKey('mobile_address_verify_chunks'),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: _MobileAddressVerifyChunkGrid(
                chunks: chunks,
                chunkLines: chunkLines,
                dividerColor: colors.border.regular,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _MobileAddressVerifyCancel(
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      );
    },
  );
}

class _MobileAddressVerifyChunkGrid extends StatelessWidget {
  const _MobileAddressVerifyChunkGrid({
    required this.chunks,
    required this.chunkLines,
    required this.dividerColor,
  });

  final List<String> chunks;
  final List<List<int>> chunkLines;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var lineIndex = 0; lineIndex < chunkLines.length; lineIndex++) ...[
          _MobileAddressVerifyChunkLine(
            key: ValueKey('mobile_address_verify_line_$lineIndex'),
            chunks: chunks,
            chunkIndexes: chunkLines[lineIndex],
          ),
          if (lineIndex < chunkLines.length - 1) ...[
            const SizedBox(height: _addressVerifyChunkGap),
            Container(
              key: ValueKey('mobile_address_verify_divider_$lineIndex'),
              height: 1,
              color: dividerColor,
            ),
            const SizedBox(height: _addressVerifyChunkGap),
          ],
        ],
      ],
    );
  }
}

class _MobileAddressVerifyChunkLine extends StatelessWidget {
  const _MobileAddressVerifyChunkLine({
    required this.chunks,
    required this.chunkIndexes,
    super.key,
  });

  final List<String> chunks;
  final List<int> chunkIndexes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _addressVerifyLineHorizontalInset,
      ),
      child: Row(
        children: [
          for (
            var position = 0;
            position < _addressVerifyChunksPerLine;
            position++
          ) ...[
            if (position > 0) const SizedBox(width: _addressVerifyChunkGap),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: position < chunkIndexes.length
                    ? _MobileAddressVerifyChunkText(
                        text: chunks[chunkIndexes[position]],
                        highlighted: _isAddressVerifyChunkHighlighted(
                          chunkIndexes[position],
                          chunks.length,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileAddressVerifyChunkText extends StatelessWidget {
  const _MobileAddressVerifyChunkText({
    required this.text,
    required this.highlighted,
  });

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      text,
      style: _addressVerifyChunkTextStyle.copyWith(
        fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
        color: highlighted ? colors.text.brandCrimson : colors.text.primary,
      ),
    );
  }
}

class _MobileAddressVerifyCancel extends StatelessWidget {
  const _MobileAddressVerifyCancel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: AppButtonSizing.largeHeight,
          child: Center(
            child: Text(
              'Cancel',
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isAddressVerifyChunkHighlighted(int index, int totalChunks) {
  return index == 0 ||
      index == 2 ||
      index == totalChunks - 3 ||
      index == totalChunks - 1;
}

List<String> _chunkAddress(String address) {
  final trimmed = address.trim();
  return [
    for (var i = 0; i < trimmed.length; i += 5)
      trimmed.substring(i, i + 5 > trimmed.length ? trimmed.length : i + 5),
  ];
}

List<List<int>> _chunkAddressLines(List<String> chunks) {
  return [
    for (var i = 0; i < chunks.length; i += 5)
      [
        for (var index = i; index < chunks.length && index < i + 5; index++)
          index,
      ],
  ];
}
