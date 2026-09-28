#!/usr/bin/env bash
# Call the caller-provided run_flutter_scenario function for each journey.
ledger_speculos_scenarios() {
  case "$1" in
    desktop)
      run_flutter_scenario "imports and sends with Ledger through Speculos"
      run_flutter_scenario "sends to TEX with two Ledger approvals through Speculos"
      run_flutter_scenario "shields transparent balance with Ledger through Speculos"
      run_flutter_scenario "pays with Ledger through Speculos"
      run_flutter_scenario "swaps with Ledger through Speculos"
      run_flutter_scenario "signs sequential voting bundles with Ledger through Speculos"
      if [[ "${VIZOR_LEDGER_RUN_ORCHARD_TO_IRONWOOD_CANARY:-false}" == "true" ]]; then
        run_flutter_scenario "signs Orchard to Ironwood crossing through Speculos"
      fi
      run_flutter_scenario "signs sequential Ledger operations in one app lifecycle"
      ;;
    mobile)
      run_flutter_scenario "imports with Ledger through Speculos"
      run_flutter_scenario "sends with Ledger through Speculos"
      run_flutter_scenario "blocks recovered Orchard send until the Ledger app is compatible"
      run_flutter_scenario "sends to TEX with two Ledger approvals through Speculos"
      run_flutter_scenario "shields transparent balance with Ledger through Speculos"
      run_flutter_scenario "pays with Ledger through Speculos"
      run_flutter_scenario "swaps with Ledger through Speculos"
      run_flutter_scenario "signs sequential voting bundles with Ledger through Speculos"
      if [[ "${VIZOR_LEDGER_RUN_ORCHARD_TO_IRONWOOD_CANARY:-false}" == "true" ]]; then
        run_flutter_scenario "signs Orchard to Ironwood crossing through Speculos"
      fi
      ;;
    *) echo "Unknown Ledger lane: $1" >&2; return 2 ;;
  esac
}
