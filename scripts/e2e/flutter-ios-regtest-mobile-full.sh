#!/usr/bin/env bash
# Runs on Zakura regtest chains; see scripts/e2e/README.md.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/zakura-run.py" \
  flutter.ios.create-sync \
  flutter.ios.import-sync \
  flutter.ios.account-management \
  flutter.ios.multi-account-send \
  flutter.ios.mempool-receive \
  flutter.ios.fallback-endpoint \
  flutter.ios.slow-height-fallback \
  flutter.ios.ironwood-pre-migration-send \
  flutter.ios.ironwood-migration \
  flutter.ios.ironwood-migration-many-notes \
  flutter.ios.ironwood-migration-multi-account \
  flutter.ios.ironwood-migration-reorg \
  flutter.ios.ironwood-migration-restart \
  flutter.ios.ironwood-migration-network-recovery \
  flutter.ios.ironwood-background-migration \
  flutter.ios.ironwood-background-restart \
  flutter.ios.payment-link-round-trip \
  flutter.ios.payment-uri-send \
  flutter.ios.gift-onboarding \
  flutter.ios.ironwood-migration-account-reimport \
  flutter.ios.ironwood-migration-500-notes \
  "$@"
