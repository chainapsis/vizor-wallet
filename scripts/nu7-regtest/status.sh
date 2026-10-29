#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

zebra_rpc getblockchaininfo | python3 -c 'import json,sys
info = json.load(sys.stdin)
print("height %s, tip branch %s" % (info["blocks"], info["consensus"]["chaintip"]))
for upgrade in info.get("upgrades", {}).values():
    if upgrade["name"] in ("NU6.3", "NU7"):
        print("%s at %s: %s" % (upgrade["name"], upgrade["activationheight"], upgrade["status"]))'
