#!/usr/bin/env bash
# Runs on Zakura regtest chains; see scripts/e2e/README.md.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/zakura-run.py" \
  flutter.macos.import-sync \
  flutter.macos.fallback-endpoint \
  flutter.macos.custom-endpoint-no-fallback \
  flutter.macos.sync-startup-stall-recovery \
  flutter.macos.slow-height-fallback \
  flutter.macos.shield-transparent \
  flutter.macos.shield-transparent-retry \
  flutter.macos.multi-account-send \
  flutter.macos.tex-send \
  flutter.macos.mempool-receive-history \
  flutter.macos.mempool-during-sync \
  flutter.macos.mempool-expiry \
  flutter.macos.voting \
  flutter.macos.voting-slow-helper \
  flutter.macos.payment-uri-send \
  flutter.macos.payment-uri-locked-send \
  flutter.macos.payment-request-round-trip \
  flutter.macos.payment-link-round-trip \
  flutter.macos.payment-link-restart \
  flutter.macos.payment-link-recovery \
  "$@"
