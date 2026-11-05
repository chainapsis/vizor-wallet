#!/usr/bin/env bash
set -euo pipefail

# Downloads the Korean and Simplified Chinese fonts that widget captures use
# to render ko/zh text (`scripts/figma-compare.sh widget --locale ko`). Flutter
# tests cannot read system fonts, so without these the CJK glyphs render as
# boxes with the wrong widths. The fonts stay outside the repository; the
# release app keeps using the platform's own CJK fonts.

DIR="${VIZOR_CAPTURE_FONT_DIR:-$HOME/.cache/vizor/capture-fonts}"
# google/fonts revision; Noto Sans KR/SC, SIL Open Font License 1.1.
COMMIT="fbe81817505e8aeadc53cc7a38a2b76fb57c333e"
BASE="https://raw.githubusercontent.com/google/fonts/$COMMIT/ofl"

fetch() {
  local name="$1" source="$2" sha="$3"
  local target="$DIR/$name"
  if [[ -f "$target" ]] && shasum -a 256 "$target" | grep -q "^$sha "; then
    echo "ok: $target"
    return
  fi
  local partial="$target.partial"
  curl -fsSL -o "$partial" "$BASE/$source"
  if ! shasum -a 256 "$partial" | grep -q "^$sha "; then
    rm -f "$partial"
    echo "fail: checksum mismatch for $source" >&2
    exit 1
  fi
  mv "$partial" "$target"
  echo "ok: $target"
}

mkdir -p "$DIR"
fetch NotoSansKR-VF.ttf 'notosanskr/NotoSansKR%5Bwght%5D.ttf' \
  194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252
fetch NotoSansSC-VF.ttf 'notosanssc/NotoSansSC%5Bwght%5D.ttf' \
  a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da
