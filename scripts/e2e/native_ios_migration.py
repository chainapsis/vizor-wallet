"""Original Orchard fixtures for the existing mobile migration scenarios."""
from __future__ import annotations

import json
import os

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
from native_worker_lifecycle import NativeWorkerCase
from zakura_batch_funding import fund_zakura_batch, migration_note_batches


# Amount, distinct notes, funding transactions. These are the existing shell
# defaults, not reduced datasets chosen to make the migrated tests pass.
IOS_MIGRATION_FUNDING = {
    "flutter.ios.ironwood-pre-migration-send": (1_095_000, 1, 1),
    "flutter.ios.ironwood-migration": (1_095_000, 1, 1),
    "flutter.ios.ironwood-migration-many-notes": (1_000_020_000, 20, 1),
    "flutter.ios.ironwood-migration-multi-account": (1_100_000, 1, 1),
    "flutter.ios.ironwood-migration-reorg": (1_100_000, 1, 1),
    "flutter.ios.ironwood-migration-restart": (123_000_000, 1, 1),
    "flutter.ios.ironwood-migration-network-recovery": (1_100_000, 1, 1),
    "flutter.ios.ironwood-background-migration": (123_000_000, 1, 1),
    "flutter.ios.ironwood-background-restart": (123_000_000, 1, 1),
    "flutter.ios.ironwood-migration-account-reimport": (123_000_000, 1, 1),
    "flutter.ios.ironwood-migration-500-notes": (500_000_000, 500, 10),
}
IOS_MIGRATION_SCENARIOS = frozenset(IOS_MIGRATION_FUNDING)
_MNEMONIC = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
_RECEIVER = "return try reason flat civil wolf dwarf announce toddler uphold equip range neck proof gauge east rifle swim tray twin venue fossil will version"


def derive_ios_migration_addresses(case, artifact, scenarios, *, cancel):
    """Run the existing SDK example once for the selected maximum note count."""
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches:
        raise runtime.RunnerError("iOS address derivation requires its original producer case")
    selected = tuple(s.id for s in scenarios if s.id in IOS_MIGRATION_SCENARIOS)
    if not selected:
        raise runtime.RunnerError("no selected iOS migration needs address derivation")
    count = max(IOS_MIGRATION_FUNDING[name][1] for name in selected)
    try:
        def derive(mnemonic, note_count):
            artifact.verify_unchanged()
            result = case.run_command([str(artifact.wallet_addresses_binary()), mnemonic, str(note_count)],
                env=os.environ.copy(), timeout=60, cancel_event=cancel, max_output_bytes=2*1024*1024)
            if result.returncode:
                raise runtime.RunnerError("original mobile SDK address derivation failed", result.returncode)
            records = [json.loads(line) for line in result.lines if line.lstrip().startswith("{")]
            if len(records) != 1 or not isinstance(records[0], dict):
                raise runtime.RunnerError("mobile SDK address derivation did not publish one object")
            record = records[0]
            addresses = record.get("unifiedAddresses")
            if (not isinstance(addresses, list) or len(addresses) != note_count
                or any(not isinstance(address, str) or not address.startswith("uregtest1")
                       or not address.isascii() or not address.isalnum() or len(address) > 4096
                       for address in addresses)
                or len(set(addresses)) != note_count or record.get("unifiedAddress") != addresses[0]):
                raise runtime.RunnerError("mobile SDK note addresses are not distinct exact regtest fixtures")
            artifact.verify_unchanged()
            return tuple(addresses)

        addresses = derive(_MNEMONIC, count)
        recipient = (derive(_RECEIVER, 1)[0]
            if "flutter.ios.ironwood-pre-migration-send" in selected else None)
        return {"note_addresses": addresses, "send_recipient": recipient}
    finally:
        case.close()


def fund_ios_migration(session, artifact, addresses, *, cancel):
    """Retain exact source/transaction/note counts before wallet decryption."""
    if not isinstance(session, NativeWorkerCase) or session.backend is None or session._finished:
        raise runtime.RunnerError("mobile migration funding requires the original prepared worker case")
    manifest = json.loads(session.case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    name = manifest["scenario_id"]
    if name not in IOS_MIGRATION_SCENARIOS or manifest["regtest_ironwood_activation_height"] != 500:
        raise runtime.RunnerError("mobile migration funding requires its activation500 case")
    amount, note_count, tx_count = IOS_MIGRATION_FUNDING[name]
    if not isinstance(addresses, dict) or not isinstance(addresses.get("note_addresses"), tuple):
        raise runtime.RunnerError("mobile migration needs the original SDK address result")
    notes = addresses["note_addresses"][:note_count]
    if len(notes) != note_count:
        raise runtime.RunnerError("mobile migration address count differs from the original fixture")
    session.verify_owned()
    batches = migration_note_batches(notes, total_zatoshi=amount, tx_count=tx_count)
    proofs = []
    for index, batch in enumerate(batches):
        # The 20-note/10.0002 fixture consumes two 6.25-ZEC coinbases.
        # The 500-note fixture keeps the original one-source-per-batch limit.
        sources = (1, 2) if note_count == 20 else (index+1,)
        proofs.append(fund_zakura_batch(session.case, session.backend, artifact,
            payments=batch, source_heights=sources, recipient_pool="orchard",
            confirmations=10, timeout=180, cancel_event=cancel))
        session.verify_owned()
    if (len(proofs) != tx_count or sum(item["payment_count"] for item in proofs) != note_count
        or sum(item["amount_zatoshi"] for item in proofs) != amount):
        raise runtime.RunnerError("mobile migration funding counts differ")
    return proofs
