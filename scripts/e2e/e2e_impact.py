"""Conservative, side-effect-free changed-file selection for catalogued E2Es."""

from __future__ import annotations

import dataclasses
from pathlib import PurePosixPath
import re
from typing import Any, Mapping, Sequence

from e2e_catalog import Catalog, CatalogError, Scenario


_DETAIL_FIELDS = frozenset(
    {
        "mapping_version",
        "changed_files",
        "ignored_files",
        "fallback_files",
        "reasons",
        "coverage_gaps",
        "coverage_scope",
    }
)
_PROVENANCE_FIELDS = frozenset({"kind", "values", "tags", "impact"})
_GIT_FIELDS = frozenset(
    {"base_ref", "base_commit", "merge_bases", "head_commit", "include_worktree"}
)
_OID_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")

# These catalogued wrappers exec a base script, so a base-script change affects
# both the base scenario and the dependent wrapper scenario.
_SCRIPT_SCENARIOS: dict[str, tuple[str, ...]] = {
    "scripts/e2e/flutter-macos-regtest-payment-link.sh": (
        "flutter.macos.payment-link-restart",
        "flutter.macos.payment-link-recovery",
    ),
    "scripts/e2e/flutter-macos-regtest-voting.sh": (
        "flutter.macos.voting",
        "flutter.macos.voting-slow-helper",
    ),
    "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration.sh": (
        "flutter.ios.ironwood-pre-migration-send",
        "flutter.ios.ironwood-migration",
    ),
}

# A script may run several phases, and one phase may be reused by several
# catalog entries. Keep those non-mechanical relationships explicit.
_INTEGRATION_SCENARIOS: dict[str, tuple[str, ...]] = {
    "integration_test/regtest_import_sync_test.dart": ("flutter.macos.import-sync",),
    "integration_test/regtest_fallback_endpoint_test.dart": ("flutter.macos.fallback-endpoint",),
    "integration_test/regtest_custom_endpoint_no_fallback_test.dart": ("flutter.macos.custom-endpoint-no-fallback",),
    "integration_test/regtest_sync_startup_stall_recovery_test.dart": ("flutter.macos.sync-startup-stall-recovery",),
    "integration_test/regtest_slow_height_fallback_test.dart": ("flutter.macos.slow-height-fallback",),
    "integration_test/regtest_shield_transparent_test.dart": ("flutter.macos.shield-transparent",),
    "integration_test/regtest_shield_transparent_retry_test.dart": ("flutter.macos.shield-transparent-retry",),
    "integration_test/regtest_multi_account_send_test.dart": ("flutter.macos.multi-account-send",),
    "integration_test/regtest_tex_send_test.dart": ("flutter.macos.tex-send",),
    "integration_test/regtest_mempool_receive_history_test.dart": (
        "flutter.macos.mempool-receive-history",
        "flutter.macos.mempool-during-sync",
        "flutter.macos.mempool-expiry",
    ),
    "integration_test/regtest_mobile_voting_reinstall_test.dart": (
        "flutter.macos.voting",
        "flutter.macos.voting-slow-helper",
    ),
    "integration_test/regtest_voting_ironwood_setup_test.dart": (
        "flutter.macos.voting",
        "flutter.macos.voting-slow-helper",
    ),
    "integration_test/regtest_voting_test.dart": (
        "flutter.macos.voting",
        "flutter.macos.voting-slow-helper",
    ),
    "integration_test/regtest_payment_uri_send_test.dart": ("flutter.macos.payment-uri-send",),
    "integration_test/regtest_payment_uri_locked_send_test.dart": ("flutter.macos.payment-uri-locked-send",),
    "integration_test/regtest_payment_request_round_trip_test.dart": ("flutter.macos.payment-request-round-trip",),
    "integration_test/regtest_payment_link_round_trip_test.dart": ("flutter.macos.payment-link-round-trip",),
    "integration_test/regtest_payment_link_restart_prepare_test.dart": ("flutter.macos.payment-link-restart",),
    "integration_test/regtest_payment_link_restart_resume_test.dart": ("flutter.macos.payment-link-restart",),
    "integration_test/regtest_payment_link_failure_prepare_test.dart": ("flutter.macos.payment-link-recovery",),
    "integration_test/regtest_payment_link_failure_reorg_resume_test.dart": ("flutter.macos.payment-link-recovery",),
    "integration_test/regtest_mobile_create_sync_test.dart": ("flutter.ios.create-sync",),
    "integration_test/regtest_mobile_import_sync_test.dart": ("flutter.ios.import-sync",),
    "integration_test/regtest_mobile_account_management_test.dart": ("flutter.ios.account-management",),
    "integration_test/regtest_mobile_multi_account_send_test.dart": ("flutter.ios.multi-account-send",),
    "integration_test/regtest_mobile_mempool_receive_test.dart": ("flutter.ios.mempool-receive",),
    "integration_test/regtest_mobile_fallback_endpoint_test.dart": ("flutter.ios.fallback-endpoint",),
    "integration_test/regtest_mobile_slow_height_fallback_test.dart": ("flutter.ios.slow-height-fallback",),
    "integration_test/regtest_mobile_ironwood_pre_migration_send_test.dart": ("flutter.ios.ironwood-pre-migration-send",),
    "integration_test/regtest_mobile_ironwood_migration_test.dart": ("flutter.ios.ironwood-migration",),
    "integration_test/regtest_mobile_ironwood_migration_many_notes_test.dart": (
        "flutter.ios.ironwood-migration-many-notes",
        "flutter.ios.ironwood-migration-500-notes",
    ),
    "integration_test/regtest_mobile_ironwood_migration_multi_account_test.dart": ("flutter.ios.ironwood-migration-multi-account",),
    "integration_test/regtest_mobile_ironwood_migration_reorg_test.dart": ("flutter.ios.ironwood-migration-reorg",),
    "integration_test/regtest_mobile_ironwood_migration_restart_prepare_test.dart": ("flutter.ios.ironwood-migration-restart",),
    "integration_test/regtest_mobile_ironwood_migration_restart_resume_test.dart": ("flutter.ios.ironwood-migration-restart",),
    "integration_test/regtest_mobile_ironwood_migration_network_recovery_test.dart": ("flutter.ios.ironwood-migration-network-recovery",),
    "integration_test/regtest_mobile_ironwood_background_migration_test.dart": ("flutter.ios.ironwood-background-migration",),
    "integration_test/regtest_mobile_ironwood_background_restart_prepare_test.dart": ("flutter.ios.ironwood-background-restart",),
    "integration_test/regtest_mobile_ironwood_background_restart_resume_test.dart": ("flutter.ios.ironwood-background-restart",),
    "integration_test/regtest_mobile_payment_link_round_trip_test.dart": ("flutter.ios.payment-link-round-trip",),
    "integration_test/regtest_mobile_payment_uri_send_test.dart": ("flutter.ios.payment-uri-send",),
    "integration_test/regtest_mobile_gift_onboarding_test.dart": ("flutter.ios.gift-onboarding",),
    "integration_test/regtest_mobile_ironwood_migration_account_reimport_test.dart": ("flutter.ios.ironwood-migration-account-reimport",),
}


@dataclasses.dataclass(frozen=True)
class ImpactSelection:
    scenarios: tuple[Scenario, ...]
    details: dict[str, Any]


def normalize_changed_paths(paths: Sequence[str]) -> tuple[str, ...]:
    """Return stable, lexical POSIX repository paths without touching disk."""

    if isinstance(paths, (str, bytes)):
        raise CatalogError("changed paths must be a sequence, not one string")
    normalized: list[str] = []
    seen: set[str] = set()
    for index, raw in enumerate(paths):
        if not isinstance(raw, str):
            raise CatalogError(f"changed path {index} must be a string")
        if not raw or "\x00" in raw or "\\" in raw:
            raise CatalogError(f"changed path {index} is not a safe POSIX path")
        path = PurePosixPath(raw)
        if path.is_absolute() or ".." in path.parts:
            raise CatalogError(f"changed path {index} must be repository-relative")
        value = str(path)
        if value in ("", "."):
            raise CatalogError(f"changed path {index} must name a file")
        if value not in seen:
            seen.add(value)
            normalized.append(value)
    return tuple(normalized)


def _tags(tags: Sequence[str]) -> tuple[str, ...]:
    if isinstance(tags, (str, bytes)):
        raise CatalogError("tags must be a sequence, not one string")
    result: list[str] = []
    for index, tag in enumerate(tags):
        if not isinstance(tag, str) or not tag or tag != tag.strip():
            raise CatalogError(f"tag {index} must be a non-empty trimmed string")
        result.append(tag)
    if len(set(result)) != len(result):
        raise CatalogError("tags must not contain duplicates")
    return tuple(result)


def _matches_tags(scenario: Scenario, tags: tuple[str, ...]) -> bool:
    return all(tag in scenario.tags for tag in tags)


def _runnable(scenario: Scenario, catalog: Catalog) -> bool:
    return scenario.supported and catalog.profiles_by_id[scenario.profile].supported


def _pending_reason(scenario: Scenario, catalog: Catalog) -> str:
    return (
        scenario.pending_reason
        or catalog.profiles_by_id[scenario.profile].pending_reason
        or "scenario is not currently runnable"
    )


def select_changed_scenarios(
    catalog: Catalog,
    paths: Sequence[str],
    *,
    tags: Sequence[str] = (),
) -> ImpactSelection:
    """Select directly affected scenarios, conservatively widening unknowns."""

    changed = normalize_changed_paths(paths)
    requested_tags = _tags(tags)
    by_id = catalog.scenarios_by_id
    script_ids = {
        scenario.script: scenario.id
        for scenario in catalog.scenarios
        if scenario.script is not None
    }
    mac_catalog = tuple(
        scenario.id
        for scenario in catalog.scenarios
        if scenario.engine == "flutter-macos"
    )
    ios_catalog = tuple(
        scenario.id
        for scenario in catalog.scenarios
        if scenario.engine == "flutter-ios"
    )
    flutter_catalog = tuple(
        scenario.id
        for scenario in catalog.scenarios
        if scenario.engine.startswith("flutter-")
    )
    all_catalog = tuple(scenario.id for scenario in catalog.scenarios)

    affected: dict[str, dict[str, list[str]]] = {}
    gap_ids: set[str] = set()
    ignored: list[dict[str, str]] = []
    fallback_files: list[str] = []

    def add(path: str, ids: Sequence[str], rule: str) -> None:
        for scenario_id in ids:
            if scenario_id not in by_id:
                raise CatalogError(
                    f"impact rule {rule!r} references unknown scenario {scenario_id!r}"
                )
            record = affected.setdefault(scenario_id, {"paths": [], "rules": []})
            if path not in record["paths"]:
                record["paths"].append(path)
            if rule not in record["rules"]:
                record["rules"].append(rule)
            if not _runnable(by_id[scenario_id], catalog):
                gap_ids.add(scenario_id)

    def gaps(engine: str) -> None:
        for scenario in catalog.scenarios:
            matches = (
                engine == "all"
                or engine == "flutter" and scenario.engine.startswith("flutter-")
                or engine == "macos" and scenario.engine == "flutter-macos"
            )
            if matches and not _runnable(scenario, catalog):
                gap_ids.add(scenario.id)

    for path in changed:
        suffix = PurePosixPath(path).suffix.lower()
        if suffix in {".md", ".rst"}:
            ignored.append({"path": path, "reason": "documentation"})
            continue
        if path in {"test/support", "test/e2e"} or path.startswith(
            ("test/support/", "test/e2e/")
        ):
            add(path, flutter_catalog, "shared-test-support")
            continue
        if path == "test" or path.startswith("test/"):
            ignored.append({"path": path, "reason": "unit-test-only"})
            continue
        if path in _SCRIPT_SCENARIOS:
            add(path, _SCRIPT_SCENARIOS[path], "shared-base-script")
            continue
        if path in script_ids:
            add(path, (script_ids[path],), "exact-script")
            continue
        if path in _INTEGRATION_SCENARIOS:
            add(path, _INTEGRATION_SCENARIOS[path], "integration-phase")
            continue
        match = re.fullmatch(r"rust/tests/([^/]+)\.rs", path)
        if match:
            ids = tuple(
                scenario.id
                for scenario in catalog.scenarios
                if scenario.engine == "rust" and scenario.target == match.group(1)
            )
            if ids:
                add(path, ids, "rust-target")
                continue
        if path in {
            "rust/tests/support/direct_zakura.rs",
            "rust/tests/support/direct_zakura_control.rs",
            "rust/examples/regtest_direct_funder.rs",
            "scripts/e2e/direct_zakura.py",
        }:
            direct_ids = tuple(
                scenario.id
                for scenario in catalog.scenarios
                if scenario.profile in {"zakura-direct-height1", "zakura-direct-activation500"}
                or scenario.profile in {"flutter-direct-height1", "flutter-direct-activation500"} and path in {
                    "rust/examples/regtest_direct_funder.rs", "scripts/e2e/direct_zakura.py",
                }
            )
            add(path, direct_ids, "direct-zakura-fixture")
            continue
        if path == "integration_test/support/regtest_lightwalletd_proxy.dart":
            add(path, tuple(scenario.id for scenario in catalog.scenarios
                            if scenario.profile in {"flutter-direct-height1", "flutter-direct-activation500"}),
                "lightwalletd-proxy")
            continue
        if path == "integration_test/support/desktop_regtest_flow.dart":
            add(path, mac_catalog, "desktop-regtest-flow")
            continue
        if path == "integration_test/support/mobile_regtest_flow.dart":
            add(path, ios_catalog, "mobile-regtest-flow")
            continue
        if path == "integration_test/support/payment_link_regtest_flow.dart":
            add(path, ("flutter.macos.payment-link-round-trip", "flutter.macos.payment-link-restart",
                       "flutter.macos.payment-link-recovery"), "payment-link-regtest-flow")
            continue
        if path == "integration_test/support/desktop_activity_flow.dart":
            add(path, mac_catalog, "desktop-activity-flow")
            continue
        if path == "integration_test/support/desktop_onboarding_flow.dart":
            add(path, mac_catalog, "desktop-onboarding")
            continue
        if path.startswith("lib/src/rust/"):
            add(path, all_catalog, "shared-runtime")
            gaps("all")
            continue
        if path.startswith("lib/"):
            add(path, flutter_catalog, "flutter-production")
            gaps("flutter")
            continue
        if path.startswith("macos/"):
            add(path, mac_catalog, "macos-native")
            gaps("macos")
            continue
        if (
            path.startswith("rust/src/")
            or path in {"rust/Cargo.toml", "rust/Cargo.lock", "rust/build.rs"}
            or path.startswith("rust_builder/")
            or path.startswith("scripts/e2e/")
            or path.startswith("scripts/regtest/")
            or path in {"docker-compose.zcash-regtest.yml", "scripts/generate-rust-bridge.sh"}
        ):
            add(path, all_catalog, "shared-runtime")
            gaps("all")
            continue

        add(path, all_catalog, "fallback")
        gaps("all")
        fallback_files.append(path)

    candidates = {
        scenario.id for scenario in catalog.scenarios if scenario.id in affected
    }
    selected = tuple(
        scenario
        for scenario in catalog.scenarios
        if scenario.id in candidates and _matches_tags(scenario, requested_tags)
    )
    if candidates and not selected:
        raise CatalogError("changed-file candidates were all removed by tag filters")

    selected_ids = {scenario.id for scenario in selected}
    reasons = [
        {
            "scenario_id": scenario.id,
            "paths": affected[scenario.id]["paths"],
            "rules": affected[scenario.id]["rules"],
        }
        for scenario in catalog.scenarios
        if scenario.id in selected_ids
    ]
    coverage_gaps = [
        {
            "scenario_id": scenario.id,
            "pending_reason": _pending_reason(scenario, catalog),
        }
        for scenario in catalog.scenarios
        if scenario.id in gap_ids and _matches_tags(scenario, requested_tags)
    ]
    details = {
        "mapping_version": 1,
        "changed_files": list(changed),
        "ignored_files": ignored,
        "fallback_files": fallback_files,
        "reasons": reasons,
        "coverage_gaps": coverage_gaps,
        "coverage_scope": "catalog-selection-with-pending-gaps",
    }
    return ImpactSelection(scenarios=selected, details=details)


def _string_values(value: Any, location: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{location} must be a non-empty string array")
    if any(not isinstance(item, str) or not item for item in value):
        raise ValueError(f"{location} must contain non-empty strings")
    return tuple(value)


def _validate_git(git: Any, base_ref: str) -> dict[str, Any]:
    if not isinstance(git, dict) or set(git) != _GIT_FIELDS:
        raise ValueError("changed_from git metadata fields are invalid")
    if git.get("base_ref") != base_ref:
        raise ValueError("changed_from base_ref must equal its selector value")
    for field in ("base_commit", "head_commit"):
        if not isinstance(git.get(field), str) or not _OID_RE.fullmatch(git[field]):
            raise ValueError(f"changed_from {field} must be a full hexadecimal OID")
    merge_bases = git.get("merge_bases")
    if not isinstance(merge_bases, list) or not merge_bases or any(
        not isinstance(item, str) or not _OID_RE.fullmatch(item)
        for item in merge_bases
    ):
        raise ValueError("changed_from merge_bases must contain unique full OIDs")
    if len(set(merge_bases)) != len(merge_bases):
        raise ValueError("changed_from merge_bases must contain unique full OIDs")
    if git.get("include_worktree") is not True:
        raise ValueError("changed_from must include the worktree")
    return git


def make_changed_provenance(
    impact: ImpactSelection,
    *,
    kind: str,
    values: Sequence[str],
    tags: Sequence[str],
    git: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Build strict selection metadata; collection of Git evidence is external."""

    tag_values = _tags(tags)
    raw_values = list(values)
    if not raw_values or any(not isinstance(item, str) or not item for item in raw_values):
        raise ValueError("changed provenance values must be non-empty strings")
    if kind == "changed_file":
        if git is not None:
            raise ValueError("changed_file provenance must use git=null")
        if normalize_changed_paths(raw_values) != tuple(impact.details["changed_files"]):
            raise ValueError("changed_file values must match the impact paths")
        git_record = None
    elif kind == "changed_from":
        if len(raw_values) != 1:
            raise ValueError("changed_from requires exactly one base ref")
        git_record = dict(_validate_git(dict(git) if git is not None else git, raw_values[0]))
    else:
        raise ValueError("changed provenance kind is invalid")
    return {
        "kind": kind,
        "values": raw_values,
        "tags": list(tag_values),
        "impact": {**impact.details, "git": git_record},
    }


def validate_changed_provenance(
    selection: Any,
    catalog: Catalog,
    scenarios: Sequence[Scenario],
) -> None:
    """Recompute and strictly validate changed-file selection metadata."""

    if not isinstance(selection, dict) or set(selection) != _PROVENANCE_FIELDS:
        raise ValueError("changed provenance fields are invalid")
    kind = selection.get("kind")
    values = _string_values(selection.get("values"), "changed provenance values")
    raw_tags = selection.get("tags")
    if not isinstance(raw_tags, list):
        raise ValueError("changed provenance tags must be an array")
    tags = _tags(raw_tags)
    impact = selection.get("impact")
    if not isinstance(impact, dict) or set(impact) != _DETAIL_FIELDS | {"git"}:
        raise ValueError("changed provenance impact fields are invalid")
    if type(impact.get("mapping_version")) is not int or impact["mapping_version"] != 1:
        raise ValueError("changed provenance mapping_version must be integer 1")

    if kind == "changed_file":
        if impact["git"] is not None:
            raise ValueError("changed_file provenance must use git=null")
        recomputed = select_changed_scenarios(catalog, values, tags=tags)
    elif kind == "changed_from":
        if len(values) != 1:
            raise ValueError("changed_from requires exactly one base ref")
        _validate_git(impact["git"], values[0])
        changed_files = impact.get("changed_files")
        if not isinstance(changed_files, list):
            raise ValueError("changed_from impact.changed_files must be an array")
        recomputed = select_changed_scenarios(catalog, changed_files, tags=tags)
    else:
        raise ValueError("changed provenance kind is invalid")

    expected_impact = {**recomputed.details, "git": impact["git"]}
    if impact != expected_impact:
        raise ValueError("changed provenance impact is stale or malformed")
    actual_ids = tuple(getattr(scenario, "id", None) for scenario in scenarios)
    expected_ids = tuple(scenario.id for scenario in recomputed.scenarios)
    if actual_ids != expected_ids:
        raise CatalogError("changed provenance scenarios do not match recomputed IDs")
