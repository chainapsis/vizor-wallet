#!/usr/bin/env bash
set -euo pipefail

mode="${1:-follow}"
predicate='subsystem == "frb_user" AND (eventMessage CONTAINS[c] "migration" OR eventMessage CONTAINS[c] "denom" OR eventMessage CONTAINS[c] "resubmit" OR eventMessage CONTAINS[c] "sync:" OR messageType >= 16)'

case "$mode" in
  follow)
    exec /usr/bin/log stream --style compact --level info --predicate "$predicate"
    ;;
  recent)
    exec /usr/bin/log show --style compact --last 30m --predicate "$predicate"
    ;;
  *)
    echo "usage: $0 [follow|recent]" >&2
    exit 1
    ;;
esac
