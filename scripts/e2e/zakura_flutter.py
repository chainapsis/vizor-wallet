"""Flutter E2E scenarios on Zakura regtest chains: catalog and commands.

A Flutter case serves its chain on the app's default regtest ports, so the
app's endpoint presets and the tests' defaults need no override: the
lightwalletd shim on 9067, the HTTP control on 18232 and the in-test
lightwalletd proxy on 19068. Nothing may listen on 19067, the Unavailable
preset. Each phase is one `flutter test` run from the checkout root.

The lightwalletd URL define replaces the endpoint preset with a custom one at
bootstrap, which turns off fallback. Only scenarios whose shell runner passed
it get it; the endpoint tests configure their presets themselves.
"""
from __future__ import annotations

import dataclasses
import os
import re
import sys

import e2e_runtime as runtime

LIGHTWALLETD_PORT = 9067
CONTROL_PORT = 18232
PROXY_PORT = 19068
UNAVAILABLE_PORT = 19067
# The screenshot tests post to a host driver that captures the simulator.
SCREENSHOT_PORT = 39070
# voting-services.sh serves the vote chain, PIR and the voting gateway here.
VOTING_PORTS = {"pir": 13000, "vote_api": 1317, "vote_rpc": 26657, "voting_gateway": 18080}
FIXED_PORTS = {"rpc": CONTROL_PORT, "lwd": LIGHTWALLETD_PORT, "proxy": PROXY_PORT}

DEFAULT_ACTIVATION = 1
MIGRATION_ACTIVATION = 500
INITIAL_BLOCKS = 100

DESKTOP_UA = ("uregtest1nu0qx0nca0ncpshm5x47ldc90835m2fy3gjuh3empp5js9qanzjwxppsw7x07a2ec3z52ute7d7f0z68ez90"
              "qlagx5ankjm4eyd6l90p")
IMPORT_UA = ("uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s"
             "9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn")
IMPORT_TRANSPARENT = "tmPTcChwqcza88W1mydzwkZ25C9qQm3ugiM"

DESKTOP_MNEMONIC = ("winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle "
                    "ethics found child scare curve congress renew salute pig better used")
RECEIVER_MNEMONIC = ("return try reason flat civil wolf dwarf announce toddler uphold equip range neck proof "
                     "gauge east rifle swim tray twin venue fossil will version")

LIGHTWALLETD_OVERRIDE = ("ZCASH_E2E_LIGHTWALLETD_URL", f"http://127.0.0.1:{LIGHTWALLETD_PORT}")
# Scenarios whose tests put their in-test proxy in front of lightwalletd.
PROXY_OVERRIDE = ("ZCASH_E2E_LIGHTWALLETD_URL", f"http://127.0.0.1:{PROXY_PORT}")
PAYMENT_LINKS = (("VIZOR_PAYMENT_LINK_REGTEST_ENABLED", "true"),
                 ("VIZOR_DEEPLINK_BASE_URL", "https://link-dev.vizor.cash"))


@dataclasses.dataclass(frozen=True)
class Derived:
    """An address of a test mnemonic, from the wallet address tool the run builds."""
    mnemonic: str
    field: str


RECEIVER_UA = Derived(RECEIVER_MNEMONIC, "unifiedAddress")
RECEIVER_TEX = Derived(RECEIVER_MNEMONIC, "texAddress")
DESKTOP_TRANSPARENT = Derived(DESKTOP_MNEMONIC, "transparentAddress")


@dataclasses.dataclass(frozen=True)
class Funding:
    """One payment from a mature coinbase, confirmed before the app starts."""
    address: str | Derived
    zatoshi: int
    pool: str
    source_height: int


@dataclasses.dataclass(frozen=True)
class OrchardNotes:
    """Orchard notes on the desktop wallet's first diversified addresses.

    They are funded before a controlled activation, one transaction per tuple
    of coinbase heights, and the total is split as the Ironwood shell runner
    split it.
    """
    total_zatoshi: int
    note_count: int = 1
    sources: tuple[tuple[int, ...], ...] = ((1,),)


@dataclasses.dataclass(frozen=True)
class Phase:
    """One `flutter test` run; `mine_before` blocks are mined while no app runs.

    `fundings` counts the coinbases the test spends through the control.
    A phase may run on another platform than its scenario, with its own
    defines on top of the scenario's. A `reinstall` phase starts on the
    simulator only after the app and its data are gone.
    """
    test: str
    mine_before: int = 0
    args: tuple[str, ...] = ()
    fundings: int = 0
    platform: str | None = None
    defines: tuple[tuple[str, str], ...] = ()
    reinstall: bool = False


@dataclasses.dataclass(frozen=True)
class Voting:
    """The vote chain, PIR server and gateway a voting scenario votes against.

    The first phase migrates the wallet's Orchard notes into Ironwood voting
    power; voting-services.sh then starts the services for the later phases.
    A `final_tally` scenario waits for the round to finalize and checks its
    tally. A `ledger` one signs on the Speculos device that
    ledger-speculos-docker.sh runs.
    """
    slow_helper: bool = False
    discovery_transition: bool = False
    final_tally: bool = False
    ledger: bool = False


@dataclasses.dataclass(frozen=True)
class FlutterScenario:
    id: str
    platform: str
    phases: tuple[Phase, ...]
    defines: tuple[tuple[str, str], ...] = ()
    env: tuple[tuple[str, str], ...] = ()
    funding: tuple[Funding, ...] = ()
    orchard_notes: OrchardNotes | None = None
    screenshots: bool = False
    voting: Voting | None = None
    activation_height: int = DEFAULT_ACTIVATION
    initial_blocks: int = INITIAL_BLOCKS
    timeout_seconds: int = 1200


def _payment_link(id, tests, lightwalletd=LIGHTWALLETD_OVERRIDE, mine_between=0):
    """A desktop Gift Card scenario; the sender holds 1.25 ZEC, and between
    a prepare and a resume phase the chain advances with the app stopped."""
    phases = tuple(Phase(f"integration_test/{test}_test.dart", mine_before=mine_between if index else 0)
                   for index, test in enumerate(tests))
    return FlutterScenario(id, "macos", phases, defines=(lightwalletd, *PAYMENT_LINKS),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),))


def _ironwood(id, platform, test, notes, *defines, initial_blocks=INITIAL_BLOCKS):
    """A migration scenario as the Ironwood shell runner ran it."""
    return FlutterScenario(id, platform, (Phase(test),),
        defines=(LIGHTWALLETD_OVERRIDE,
                 ("ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT", str(notes.note_count)),
                 ("ZCASH_FAST_TESTNET_MIGRATION", "false"),
                 ("ZCASH_E2E_ORCHARD_FUNDING_TX_COUNT", str(len(notes.sources))), *defines),
        orchard_notes=notes, activation_height=MIGRATION_ACTIVATION, initial_blocks=initial_blocks)


def _ironwood_restart(id, platform, prefix, notes, *, mine_between=0):
    """A prepare phase that keeps the app installed, then a resume phase."""
    return FlutterScenario(id, platform,
        (Phase(f"integration_test/{prefix}_prepare_test.dart", args=("--no-uninstall",)),
         Phase(f"integration_test/{prefix}_resume_test.dart", mine_before=mine_between)),
        defines=(LIGHTWALLETD_OVERRIDE,), orchard_notes=notes,
        activation_height=MIGRATION_ACTIVATION)


def _voting(id, platform, test, voting=Voting(), *, reinstall=False):
    """Migrate voting power on the desktop app, then vote on the platform's app.

    With `reinstall`, the vote phase leaves the wallet, the app is reinstalled
    and a last phase restores the same wallet against the same round.
    """
    vote_defines = (("ZCASH_E2E_VOTING_KEEP_APP_STATE", "1" if reinstall else "0"),
                    ("ZCASH_E2E_REUSE_MIGRATED_WALLET", "true"),
                    ("ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN", "true"))
    phases = (Phase("integration_test/regtest_voting_ironwood_setup_test.dart", platform="macos",
                    defines=(("ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT", "1"),
                             ("ZCASH_FAST_TESTNET_MIGRATION", "false"),
                             ("ZCASH_E2E_ORCHARD_FUNDING_TX_COUNT", "1"),
                             ("ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI", "13000000"))),
              Phase(f"integration_test/{test}_test.dart", defines=vote_defines))
    if reinstall:
        phases += (Phase("integration_test/regtest_mobile_voting_reinstall_test.dart", defines=vote_defines,
                         reinstall=True),)
    return FlutterScenario(id, platform, phases, defines=(LIGHTWALLETD_OVERRIDE,),
        orchard_notes=OrchardNotes(13_000_000), voting=voting,
        activation_height=MIGRATION_ACTIVATION, timeout_seconds=3600)


FLUTTER_SCENARIOS = (
    FlutterScenario(
        "flutter.macos.import-sync", "macos",
        (Phase("integration_test/regtest_import_sync_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE, ("ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN", "true")),
        funding=(Funding(IMPORT_UA, 125_000_000, "ironwood", 1),
                 Funding(IMPORT_TRANSPARENT, 75_000_000, "transparent", 2))),
    FlutterScenario(
        "flutter.macos.fallback-endpoint", "macos",
        (Phase("integration_test/regtest_fallback_endpoint_test.dart"),),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.macos.custom-endpoint-no-fallback", "macos",
        (Phase("integration_test/regtest_custom_endpoint_no_fallback_test.dart"),)),
    FlutterScenario(
        "flutter.macos.sync-startup-stall-recovery", "macos",
        (Phase("integration_test/regtest_sync_startup_stall_recovery_test.dart"),)),
    FlutterScenario(
        "flutter.macos.slow-height-fallback", "macos",
        (Phase("integration_test/regtest_slow_height_fallback_test.dart", fundings=3),),
        defines=(("ZCASH_E2E_UNIFIED_ADDRESS", DESKTOP_UA),),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.macos.shield-transparent", "macos",
        (Phase("integration_test/regtest_shield_transparent_test.dart", fundings=1),),
        defines=(LIGHTWALLETD_OVERRIDE,)),
    FlutterScenario(
        "flutter.macos.shield-transparent-retry", "macos",
        (Phase("integration_test/regtest_shield_transparent_retry_test.dart", fundings=1),)),
    FlutterScenario(
        "flutter.macos.multi-account-send", "macos",
        (Phase("integration_test/regtest_multi_account_send_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),
                 Funding(DESKTOP_TRANSPARENT, 75_000_000, "transparent", 2))),
    FlutterScenario(
        "flutter.macos.tex-send", "macos",
        (Phase("integration_test/regtest_tex_send_test.dart", fundings=1),),
        defines=(LIGHTWALLETD_OVERRIDE, ("ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN", "true"),
                 ("ZCASH_E2E_TEX_ADDRESS", RECEIVER_TEX)),
        env=(("ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW", "1"),),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.macos.payment-uri-send", "macos",
        (Phase("integration_test/regtest_payment_uri_send_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.macos.payment-uri-locked-send", "macos",
        (Phase("integration_test/regtest_payment_uri_locked_send_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.macos.payment-request-round-trip", "macos",
        (Phase("integration_test/regtest_payment_request_round_trip_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE, ("VIZOR_E2E_STEP_DELAY_MS", "0")),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.macos.mempool-receive-history", "macos",
        (Phase("integration_test/regtest_mempool_receive_history_test.dart", fundings=1),),
        defines=(LIGHTWALLETD_OVERRIDE,)),
    # The app syncs 750 blocks in slow batches, so the payment lands mid-sync.
    FlutterScenario(
        "flutter.macos.mempool-during-sync", "macos",
        (Phase("integration_test/regtest_mempool_receive_history_test.dart", fundings=1),),
        defines=(LIGHTWALLETD_OVERRIDE, ("ZCASH_E2E_MEMPOOL_TEST_MODE", "during-sync")),
        env=(("ZCASH_E2E_SYNC_BATCH_SIZE", "50"), ("ZCASH_E2E_SYNC_BATCH_DELAY_MS", "750")),
        initial_blocks=750),
    FlutterScenario(
        "flutter.macos.mempool-expiry", "macos",
        (Phase("integration_test/regtest_mempool_receive_history_test.dart", fundings=1),),
        defines=(LIGHTWALLETD_OVERRIDE, ("ZCASH_E2E_MEMPOOL_TEST_MODE", "expiry"))),
    _payment_link("flutter.macos.payment-link-round-trip", ("regtest_payment_link_round_trip",)),
    _payment_link("flutter.macos.payment-link-restart",
        ("regtest_payment_link_restart_prepare", "regtest_payment_link_restart_resume"), mine_between=6),
    _payment_link("flutter.macos.payment-link-batch-restart",
        ("regtest_payment_link_batch_restart_prepare", "regtest_payment_link_batch_restart_resume"),
        lightwalletd=PROXY_OVERRIDE, mine_between=6),
    _payment_link("flutter.macos.payment-link-recovery",
        ("regtest_payment_link_failure_prepare", "regtest_payment_link_failure_reorg_resume"),
        lightwalletd=PROXY_OVERRIDE, mine_between=5),
    _payment_link("flutter.macos.gift-card-tracking",
        ("regtest_gift_card_tracking_prepare", "regtest_gift_card_tracking_resume"), mine_between=200),
    # The shell runner ran each Gift Card outcome pair on a fresh chain.
    _payment_link("flutter.macos.gift-card-competition",
        ("regtest_gift_card_competition", "regtest_gift_card_removal_resume"), lightwalletd=PROXY_OVERRIDE),
    _payment_link("flutter.macos.gift-card-response",
        ("regtest_gift_card_response_prepare", "regtest_gift_card_response_resume"), lightwalletd=PROXY_OVERRIDE),
    FlutterScenario(
        "flutter.ios.create-sync", "ios",
        (Phase("integration_test/regtest_mobile_create_sync_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,)),
    FlutterScenario(
        "flutter.ios.account-management", "ios",
        (Phase("integration_test/regtest_mobile_account_management_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,)),
    FlutterScenario(
        "flutter.ios.import-sync", "ios",
        (Phase("integration_test/regtest_mobile_import_sync_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.ios.fallback-endpoint", "ios",
        (Phase("integration_test/regtest_mobile_fallback_endpoint_test.dart"),),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.ios.slow-height-fallback", "ios",
        (Phase("integration_test/regtest_mobile_slow_height_fallback_test.dart", fundings=3),),
        defines=(("ZCASH_E2E_UNIFIED_ADDRESS", DESKTOP_UA),),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.ios.mempool-receive", "ios",
        (Phase("integration_test/regtest_mobile_mempool_receive_test.dart", fundings=1),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.ios.multi-account-send", "ios",
        (Phase("integration_test/regtest_mobile_multi_account_send_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.ios.gift-onboarding", "ios",
        (Phase("integration_test/regtest_mobile_gift_onboarding_test.dart",
               args=("--tags", "mobile", "--run-skipped"), fundings=3),),
        defines=(LIGHTWALLETD_OVERRIDE, ("VIZOR_PAYMENT_LINK_REGTEST_ENABLED", "true"),
                 ("VIZOR_DEEPLINK_BASE_URL", "https://link-dev.vizor.cash")),
        initial_blocks=INITIAL_BLOCKS + 2),
    FlutterScenario(
        "flutter.ios.payment-link-round-trip", "ios",
        (Phase("integration_test/regtest_mobile_payment_link_round_trip_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE, ("VIZOR_PAYMENT_LINK_REGTEST_ENABLED", "true"),
                 ("VIZOR_DEEPLINK_BASE_URL", "https://link-dev.vizor.cash")),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    FlutterScenario(
        "flutter.ios.screenshot-tour", "ios",
        (Phase("integration_test/regtest_mobile_screenshot_tour_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),), screenshots=True),
    FlutterScenario(
        "flutter.ios.send-screenshots", "ios",
        (Phase("integration_test/regtest_mobile_send_screenshot_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),), screenshots=True),
    FlutterScenario(
        "flutter.ios.payment-uri-send", "ios",
        (Phase("integration_test/regtest_mobile_payment_uri_send_test.dart"),),
        defines=(LIGHTWALLETD_OVERRIDE,),
        funding=(Funding(DESKTOP_UA, 125_000_000, "ironwood", 1),)),
    _ironwood("flutter.ios.ironwood-migration", "ios",
        "integration_test/regtest_mobile_ironwood_migration_test.dart", OrchardNotes(1_095_000)),
    _ironwood("flutter.ios.ironwood-pre-migration-send", "ios",
        "integration_test/regtest_mobile_ironwood_pre_migration_send_test.dart", OrchardNotes(1_095_000),
        ("ZCASH_E2E_SEND_RECIPIENT_ADDRESS", RECEIVER_UA)),
    _ironwood("flutter.ios.ironwood-immediate-migration", "ios",
        "integration_test/regtest_mobile_ironwood_immediate_migration_test.dart", OrchardNotes(1_095_000)),
    _ironwood("flutter.ios.ironwood-migration-multi-account", "ios",
        "integration_test/regtest_mobile_ironwood_migration_multi_account_test.dart", OrchardNotes(1_100_000)),
    _ironwood("flutter.ios.ironwood-migration-network-recovery", "ios",
        "integration_test/regtest_mobile_ironwood_migration_network_recovery_test.dart", OrchardNotes(1_100_000)),
    _ironwood("flutter.ios.ironwood-migration-account-reimport", "ios",
        "integration_test/regtest_mobile_ironwood_migration_account_reimport_test.dart", OrchardNotes(123_000_000)),
    _ironwood("flutter.ios.ironwood-migration-reorg", "ios",
        "integration_test/regtest_mobile_ironwood_migration_reorg_test.dart", OrchardNotes(1_100_000)),
    _ironwood("flutter.ios.ironwood-background-migration", "ios",
        "integration_test/regtest_mobile_ironwood_background_migration_test.dart", OrchardNotes(123_000_000)),
    # 10.0002 ZEC needs two 6.25 ZEC coinbases in one transaction, and the
    # second matures one block later.
    _ironwood("flutter.ios.ironwood-migration-many-notes", "ios",
        "integration_test/regtest_mobile_ironwood_migration_many_notes_test.dart",
        OrchardNotes(1_000_020_000, 20, ((1, 2),)),
        ("ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI", "1000020000"),
        ("ZCASH_E2E_EXPECTED_SPLIT_STAGE_COUNT", "4"),
        ("ZCASH_E2E_EXPECTED_MIGRATION_BATCH_COUNT", "9"),
        initial_blocks=INITIAL_BLOCKS + 1),
    _ironwood("flutter.ios.ironwood-migration-500-notes", "ios",
        "integration_test/regtest_mobile_ironwood_migration_many_notes_test.dart",
        OrchardNotes(500_000_000, 500, tuple((height,) for height in range(1, 11))),
        ("ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI", "500000000"),
        ("ZCASH_E2E_EXPECTED_SPLIT_STAGE_COUNT", "44"),
        ("ZCASH_E2E_EXPECTED_MIGRATION_BATCH_COUNT", "7")),
    _ironwood("flutter.macos.ironwood-migration", "macos",
        "integration_test/regtest_ironwood_migration_test.dart", OrchardNotes(1_100_000)),
    _ironwood("flutter.macos.ironwood-pre-migration-send", "macos",
        "integration_test/regtest_ironwood_pre_migration_send_test.dart", OrchardNotes(1_100_000),
        ("ZCASH_E2E_SEND_RECIPIENT_ADDRESS", RECEIVER_UA)),
    _ironwood("flutter.macos.ironwood-migration-multi-account", "macos",
        "integration_test/regtest_ironwood_migration_multi_account_test.dart", OrchardNotes(1_100_000)),
    _ironwood("flutter.macos.ironwood-migration-expiry-recovery", "macos",
        "integration_test/regtest_ironwood_migration_expiry_recovery_test.dart", OrchardNotes(4_120_000)),
    _ironwood("flutter.macos.ironwood-migration-reorg", "macos",
        "integration_test/regtest_ironwood_migration_reorg_test.dart", OrchardNotes(1_100_000)),
    # 99.0002 ZEC takes sixteen 6.25 ZEC coinbases; the shell runner mined 20
    # more blocks before funding.
    _ironwood("flutter.macos.ironwood-migration-large-balance", "macos",
        "integration_test/regtest_ironwood_migration_large_balance_test.dart",
        OrchardNotes(9_900_020_000, 1, (tuple(range(1, 17)),)), initial_blocks=INITIAL_BLOCKS + 20),
    _ironwood("flutter.macos.ironwood-migration-many-notes", "macos",
        "integration_test/regtest_ironwood_migration_many_notes_test.dart",
        OrchardNotes(1_000_020_000, 20, ((1, 2),)), initial_blocks=INITIAL_BLOCKS + 1),
    _ironwood("flutter.macos.ironwood-migration-mixed-notes", "macos",
        "integration_test/regtest_ironwood_migration_mixed_notes_test.dart",
        OrchardNotes(1_000_020_000, 20, ((1,), (2,), (3,), (4,)))),
    _ironwood_restart("flutter.macos.ironwood-migration-restart", "macos",
        "regtest_ironwood_migration_restart", OrchardNotes(1_100_000)),
    _voting("flutter.macos.voting", "macos", "regtest_voting"),
    _voting("flutter.macos.voting-slow-helper", "macos", "regtest_voting", Voting(slow_helper=True)),
    _voting("flutter.macos.voting-final-tally", "macos", "regtest_voting", Voting(final_tally=True)),
    _voting("flutter.macos.voting-ledger-final-tally", "macos", "regtest_voting",
            Voting(final_tally=True, ledger=True)),
    _voting("flutter.ios.voting", "ios", "regtest_mobile_voting"),
    _voting("flutter.ios.voting-slow-helper", "ios", "regtest_mobile_voting", Voting(slow_helper=True)),
    _voting("flutter.ios.voting-discovery", "ios", "regtest_mobile_voting_discovery",
            Voting(discovery_transition=True)),
    _voting("flutter.ios.voting-reinstall", "ios", "regtest_mobile_voting", reinstall=True),
    _ironwood_restart("flutter.ios.ironwood-migration-restart", "ios",
        "regtest_mobile_ironwood_migration_restart", OrchardNotes(123_000_000), mine_between=12),
    _ironwood_restart("flutter.ios.ironwood-background-restart", "ios",
        "regtest_mobile_ironwood_background_restart", OrchardNotes(123_000_000)),
)

# Python moves into the checkout before `flutter test` replaces it, so the
# case keeps owning the process while Flutter finds the project's pubspec.
_IN_CHECKOUT = "import os, sys; os.chdir(sys.argv[1]); os.execvp(sys.argv[2], sys.argv[2:])"


def derived_addresses(scenario):
    """Every derived address the scenario's defines and funding use."""
    values = [value for _, value in scenario.defines if isinstance(value, Derived)]
    values += [payment.address for payment in scenario.funding if isinstance(payment.address, Derived)]
    return tuple(dict.fromkeys(values))


def fixed_ports(scenario):
    """The default ports the scenario's chain and host tools listen on."""
    return {**FIXED_PORTS, **({"screenshots": SCREENSHOT_PORT} if scenario.screenshots else {}),
            **(VOTING_PORTS if scenario.voting else {})}


def phase_platform(scenario, phase):
    return phase.platform or scenario.platform


def runner_sources(scenario):
    """Coinbase heights the runner spends, one tuple per funding transaction."""
    notes = scenario.orchard_notes
    return [(payment.source_height,) for payment in scenario.funding] + list(notes.sources if notes else ())


def funding_source_height(scenario, phase):
    """The first coinbase height the phase's test may spend.

    The runner's own payments take the lowest heights, and each earlier phase
    takes the next ones.
    """
    first = 1 + max((height for heights in runner_sources(scenario) for height in heights), default=0)
    return first + sum(earlier.fundings for earlier in scenario.phases[:scenario.phases.index(phase)])


def flutter_command(scenario, phase, *, flutter, device, source_root, derived=None, extra_defines=()):
    """The phase's `flutter test` command line, run from the checkout root.

    `derived` maps each Derived define to the address the run derived, and
    `extra_defines` are values the run learned while the case ran.
    """
    defines = {
        "ZCASH_DEFAULT_NETWORK": "regtest",
        "ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT": str(scenario.activation_height),
        "ZCASH_E2E_DRIVER_URL": f"http://127.0.0.1:{CONTROL_PORT}",
        "ZCASH_E2E_FUNDING_SOURCE_HEIGHT": str(funding_source_height(scenario, phase)),
    }
    if phase_platform(scenario, phase) == "macos":
        # Set VIZOR_E2E_HIDDEN_WINDOW=false to watch the window.
        defines["VIZOR_E2E_HIDDEN_WINDOW"] = os.environ.get("VIZOR_E2E_HIDDEN_WINDOW") or "true"
    else:
        defines["VIZOR_FORM_FACTOR"] = "mobile"
    for name, value in (*scenario.defines, *phase.defines, *extra_defines):
        if name in defines:
            raise ValueError(f"{scenario.id} sets the define {name} twice")
        if isinstance(value, Derived):
            if value not in (derived or {}):
                raise ValueError(f"{scenario.id} needs {name} derived before it runs")
            value = derived[value]
        defines[name] = value
    return [sys.executable, "-c", _IN_CHECKOUT, str(source_root), str(flutter), "test", phase.test,
            "-d", device, *phase.args, *(f"--dart-define={name}={value}" for name, value in defines.items())]


_PASSED = re.compile(r"^\d{2}:\d{2} \+([1-9][0-9]*)(?: ~[0-9]+)?: All tests passed!$", re.MULTILINE)


def verify_flutter_output(lines):
    """Exit 0 alone is not a pass: Flutter must report at least one passing test."""
    output = "".join(lines)
    if not _PASSED.search(output) or "Some tests failed" in output:
        raise runtime.RunnerError("flutter test did not report its tests as passed")
