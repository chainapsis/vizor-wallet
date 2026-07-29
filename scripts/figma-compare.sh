#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/figma-compare.sh widget [options]
  scripts/figma-compare.sh native [options]

Options:
  --scenario <id>          Registered scenario (default: pay-recipient)
  --theme <dark|light>     Theme (default: dark)
  --form-factor <value>    desktop or mobile (default: desktop)
  --width <logical-px>     Widget-test logical width
  --height <logical-px>    Widget-test logical height
  --pixel-ratio <ratio>    Widget simulated DPR / native content scale
  --output <absolute-path> Override the generated PNG path
  --start-minimized        Native macOS restoration check only
  -h, --help               Show this help

`widget` is the normal code-to-Figma comparison path. `native` launches the
real macOS window for final window-shell and restoration verification.
EOF
}

fail() {
  echo "fail: $*" >&2
  exit 2
}

take_value() {
  local flag="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || fail "missing value for $flag"
  printf '%s' "$value"
}

MODE="${1:-}"
case "$MODE" in
  widget|native) shift ;;
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 2 ;;
  *) fail "unknown mode $MODE" ;;
esac

SCENARIO="pay-recipient"
THEME="dark"
FORM_FACTOR="desktop"
WIDTH=""
HEIGHT=""
PIXEL_RATIO=""
OUTPUT=""
START_MINIMIZED="false"

while (($# > 0)); do
  case "$1" in
    --scenario) SCENARIO="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --theme) THEME="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --form-factor) FORM_FACTOR="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --width) WIDTH="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --height) HEIGHT="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --pixel-ratio) PIXEL_RATIO="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --output) OUTPUT="$(take_value "$1" "${2:-}")"; shift 2 ;;
    --start-minimized) START_MINIMIZED="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

[[ "$THEME" == "dark" || "$THEME" == "light" ]] || \
  fail "--theme must be dark or light"
[[ "$FORM_FACTOR" == "desktop" || "$FORM_FACTOR" == "mobile" ]] || \
  fail "--form-factor must be desktop or mobile"

OUTPUT_ROOT="$HOME/Library/Containers/com.keplr.vizor/Data/tmp/vizor-figma-compare"
if [[ -z "$OUTPUT" ]]; then
  if [[ "$MODE" == "widget" ]]; then
    OUTPUT="$OUTPUT_ROOT/$SCENARIO/content.widget.png"
  else
    OUTPUT="$OUTPUT_ROOT/$SCENARIO/content.png"
  fi
fi
[[ "$OUTPUT" == /* ]] || fail "--output must be an absolute path"

DEFINES=(
  "--dart-define=FIGMA_COMPARE_SCENARIO=$SCENARIO"
  "--dart-define=FIGMA_COMPARE_THEME=$THEME"
  "--dart-define=FIGMA_COMPARE_OUTPUT=$OUTPUT"
)
[[ -z "$WIDTH" ]] || DEFINES+=("--dart-define=FIGMA_COMPARE_WIDTH=$WIDTH")
[[ -z "$HEIGHT" ]] || DEFINES+=("--dart-define=FIGMA_COMPARE_HEIGHT=$HEIGHT")
[[ -z "$PIXEL_RATIO" ]] || \
  DEFINES+=("--dart-define=FIGMA_COMPARE_PIXEL_RATIO=$PIXEL_RATIO")

cd "$ROOT_DIR"

if [[ "$MODE" == "widget" ]]; then
  if [[ "$START_MINIMIZED" == "true" ]]; then
    fail "--start-minimized is available only in native mode"
  fi

  TEST_FILE="test/figma_compare/figma_compare_capture_desktop_test.dart"
  if [[ "$FORM_FACTOR" == "mobile" ]]; then
    TEST_FILE="test/figma_compare/figma_compare_capture_mobile_test.dart"
    DEFINES+=("--dart-define=VIZOR_FORM_FACTOR=mobile")
  fi

  fvm flutter test --no-pub --update-goldens \
    --tags figma-capture --run-skipped \
    "${DEFINES[@]}" \
    "$TEST_FILE"
  echo "ok: $OUTPUT"
  exit 0
fi

[[ "$FORM_FACTOR" == "desktop" ]] || \
  fail "native mode currently verifies macOS only; use the iOS Simulator workflow for mobile"
[[ -z "$WIDTH" && -z "$HEIGHT" ]] || \
  fail "native macOS size comes from production window bootstrap; omit --width/--height"

DEFINES+=("--dart-define=FIGMA_COMPARE_START_MINIMIZED=$START_MINIMIZED")
fvm flutter run --no-pub -d macos -t lib/figma_compare.dart "${DEFINES[@]}"
