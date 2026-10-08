"""Strict, side-effect-free catalog and selection helpers for E2E tests."""

from __future__ import annotations

import dataclasses
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
from typing import Any, Sequence


CATALOG_SCHEMA_VERSION = 1
REPORT_SCHEMA_VERSION = 2
_CATALOG_PATH = Path(__file__).with_name("catalog.json")
_ROOT_FIELDS = frozenset({"schema_version", "profiles", "scenarios", "suites"})
_PROFILE_FIELDS = frozenset({"id", "supported", "pending_reason"})
_SCENARIO_FIELDS = frozenset(
    {
        "id",
        "engine",
        "script",
        "target",
        "test",
        "profile",
        "tags",
        "timeout_seconds",
        "supported",
        "pending_reason",
    }
)
_REPORT_STATUSES = frozenset(
    {"passed", "failed", "timed_out", "cancelled", "not_run"}
)
_FAILED_STATUSES = frozenset({"failed", "timed_out"})
_ENGINES = frozenset({"rust", "flutter-macos", "flutter-ios"})


class CatalogError(ValueError):
    """Raised when the catalog, selection, or prior report is invalid."""


@dataclasses.dataclass(frozen=True)
class Profile:
    id: str
    supported: bool
    pending_reason: str | None = None


@dataclasses.dataclass(frozen=True)
class Scenario:
    id: str
    engine: str
    script: str | None
    target: str
    test: str
    profile: str
    tags: tuple[str, ...]
    timeout_seconds: float
    supported: bool
    pending_reason: str | None = None

@dataclasses.dataclass(frozen=True)
class Catalog:
    schema_version: int
    profiles: tuple[Profile, ...]
    scenarios: tuple[Scenario, ...]
    suites: dict[str, tuple[str, ...]]
    fingerprint: str

    @property
    def scenarios_by_id(self) -> dict[str, Scenario]:
        return {scenario.id: scenario for scenario in self.scenarios}

    @property
    def profiles_by_id(self) -> dict[str, Profile]:
        return {profile.id: profile for profile in self.profiles}


@dataclasses.dataclass(frozen=True)
class Plan:
    catalog_sha256: str
    selected: tuple[Scenario, ...]
    required_profiles: tuple[str, ...]
    required_targets: tuple[str, ...]
    runnable: bool
    blockers: tuple[str, ...]

def _reject_json_constant(value: str) -> None:
    raise CatalogError(f"non-finite JSON number is not allowed: {value}")


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise CatalogError(f"duplicate JSON key is not allowed: {key!r}")
        value[key] = item
    return value


def _read_json(path: Path) -> tuple[Any, bytes]:
    try:
        encoded = path.read_bytes()
    except OSError as error:
        raise CatalogError(f"failed to read {path}: {error}") from error
    try:
        return (
            json.loads(
                encoded,
                parse_constant=_reject_json_constant,
                object_pairs_hook=_unique_object,
            ),
            encoded,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CatalogError(f"failed to parse {path}: {error}") from error


def _mapping(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise CatalogError(f"{location} must be an object")
    if not all(isinstance(key, str) for key in value):
        raise CatalogError(f"{location} keys must be strings")
    return value


def _exact_fields(value: dict[str, Any], expected: frozenset[str], location: str) -> None:
    actual = frozenset(value)
    missing = sorted(expected - actual)
    unknown = sorted(actual - expected)
    if missing or unknown:
        details = []
        if missing:
            details.append(f"missing fields: {', '.join(missing)}")
        if unknown:
            details.append(f"unknown fields: {', '.join(unknown)}")
        raise CatalogError(f"{location} has {'; '.join(details)}")


def _nonempty_string(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CatalogError(f"{location} must be a non-empty string")
    if value != value.strip():
        raise CatalogError(f"{location} must not have surrounding whitespace")
    return value


def _boolean(value: Any, location: str) -> bool:
    if not isinstance(value, bool):
        raise CatalogError(f"{location} must be a boolean")
    return value


def _optional_reason(value: Any, supported: bool, location: str) -> str | None:
    if value is None:
        if not supported:
            raise CatalogError(f"{location} requires pending_reason when unsupported")
        return None
    reason = _nonempty_string(value, f"{location}.pending_reason")
    if supported:
        raise CatalogError(f"{location} must not have pending_reason when supported")
    return reason


def _script(value: Any, engine: str, test: str, location: str) -> str | None:
    if engine == "rust":
        if value is not None:
            raise CatalogError(f"{location}.script must be null for Rust scenarios")
        return None
    script = _nonempty_string(value, f"{location}.script")
    if "\\" in script:
        raise CatalogError(f"{location}.script must use forward slashes")
    path = PurePosixPath(script)
    if (
        path.is_absolute()
        or ".." in path.parts
        or path.parts[:2] != ("scripts", "e2e")
        or path.suffix != ".sh"
    ):
        raise CatalogError(
            f"{location}.script must be a safe relative scripts/e2e/*.sh path"
        )
    if path.stem != test:
        raise CatalogError(
            f"{location}.test must equal the Flutter script stem {path.stem!r}"
        )
    return script


def _string_list(value: Any, location: str, *, nonempty: bool) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise CatalogError(f"{location} must be an array")
    items = tuple(
        _nonempty_string(item, f"{location}[{index}]")
        for index, item in enumerate(value)
    )
    if nonempty and not items:
        raise CatalogError(f"{location} must not be empty")
    if len(set(items)) != len(items):
        raise CatalogError(f"{location} must not contain duplicates")
    return items


def load_catalog(path: Path | str | None = None) -> Catalog:
    """Loads and strictly validates the E2E catalog without side effects."""

    catalog_path = _CATALOG_PATH if path is None else Path(path)
    raw, encoded = _read_json(catalog_path)
    root = _mapping(raw, "catalog")
    _exact_fields(root, _ROOT_FIELDS, "catalog")
    version = root["schema_version"]
    if isinstance(version, bool) or not isinstance(version, int):
        raise CatalogError("catalog.schema_version must be an integer")
    if version != CATALOG_SCHEMA_VERSION:
        raise CatalogError(
            f"unsupported catalog schema_version {version}; expected {CATALOG_SCHEMA_VERSION}"
        )

    raw_profiles = root["profiles"]
    if not isinstance(raw_profiles, list) or not raw_profiles:
        raise CatalogError("catalog.profiles must be a non-empty array")
    profiles: list[Profile] = []
    profile_ids: set[str] = set()
    for index, raw_profile in enumerate(raw_profiles):
        location = f"catalog.profiles[{index}]"
        item = _mapping(raw_profile, location)
        _exact_fields(item, _PROFILE_FIELDS, location)
        profile_id = _nonempty_string(item["id"], f"{location}.id")
        if profile_id in profile_ids:
            raise CatalogError(f"duplicate profile id: {profile_id}")
        profile_ids.add(profile_id)
        is_supported = _boolean(item["supported"], f"{location}.supported")
        profiles.append(
            Profile(
                id=profile_id,
                supported=is_supported,
                pending_reason=_optional_reason(item["pending_reason"], is_supported, location),
            )
        )

    raw_scenarios = root["scenarios"]
    if not isinstance(raw_scenarios, list) or not raw_scenarios:
        raise CatalogError("catalog.scenarios must be a non-empty array")
    scenarios: list[Scenario] = []
    scenario_ids: set[str] = set()
    test_mappings: set[tuple[str, str]] = set()
    profiles_by_id = {profile.id: profile for profile in profiles}
    for index, raw_scenario in enumerate(raw_scenarios):
        location = f"catalog.scenarios[{index}]"
        item = _mapping(raw_scenario, location)
        _exact_fields(item, _SCENARIO_FIELDS, location)
        scenario_id = _nonempty_string(item["id"], f"{location}.id")
        if scenario_id in scenario_ids:
            raise CatalogError(f"duplicate scenario id: {scenario_id}")
        scenario_ids.add(scenario_id)
        engine = _nonempty_string(item["engine"], f"{location}.engine")
        if engine not in _ENGINES:
            raise CatalogError(f"{location}.engine is unknown: {engine!r}")
        target = _nonempty_string(item["target"], f"{location}.target")
        test = _nonempty_string(item["test"], f"{location}.test")
        script = _script(item["script"], engine, test, location)
        if engine != "rust" and target != engine:
            raise CatalogError(
                f"{location}.target must equal Flutter engine {engine!r}"
            )
        test_mapping = (target, test)
        if test_mapping in test_mappings:
            raise CatalogError(f"duplicate Rust test mapping: {target}::{test}")
        test_mappings.add(test_mapping)
        profile = _nonempty_string(item["profile"], f"{location}.profile")
        if profile not in profiles_by_id:
            raise CatalogError(f"{location} references unknown profile {profile!r}")
        tags = _string_list(item["tags"], f"{location}.tags", nonempty=True)
        timeout = item["timeout_seconds"]
        try:
            valid_timeout = (
                not isinstance(timeout, bool)
                and isinstance(timeout, (int, float))
                and math.isfinite(timeout)
                and timeout > 0
            )
        except OverflowError:
            valid_timeout = False
        if not valid_timeout:
            raise CatalogError(f"{location}.timeout_seconds must be positive and finite")
        is_supported = _boolean(item["supported"], f"{location}.supported")
        reason = _optional_reason(item["pending_reason"], is_supported, location)
        if is_supported and not profiles_by_id[profile].supported:
            raise CatalogError(
                f"{location} cannot be supported because profile {profile!r} is unsupported"
            )
        scenarios.append(
            Scenario(
                id=scenario_id,
                engine=engine,
                script=script,
                target=target,
                test=test,
                profile=profile,
                tags=tags,
                timeout_seconds=float(timeout),
                supported=is_supported,
                pending_reason=reason,
            )
        )

    raw_suites = _mapping(root["suites"], "catalog.suites")
    if not raw_suites:
        raise CatalogError("catalog.suites must not be empty")
    suites: dict[str, tuple[str, ...]] = {}
    for raw_name, raw_members in raw_suites.items():
        name = _nonempty_string(raw_name, "catalog.suites key")
        members = _string_list(
            raw_members, f"catalog.suites[{name!r}]", nonempty=True
        )
        unknown = [member for member in members if member not in scenario_ids]
        if unknown:
            raise CatalogError(
                f"suite {name!r} references unknown scenarios: {', '.join(unknown)}"
            )
        suites[name] = members

    referenced_profiles = {scenario.profile for scenario in scenarios}
    unreferenced_profiles = sorted(profile_ids - referenced_profiles)
    if unreferenced_profiles:
        raise CatalogError(
            "catalog contains unreferenced profiles: "
            + ", ".join(unreferenced_profiles)
        )

    return Catalog(
        schema_version=version,
        profiles=tuple(profiles),
        scenarios=tuple(scenarios),
        suites=suites,
        fingerprint=hashlib.sha256(encoded).hexdigest(),
    )


def _failed_scenario_ids(path: Path | str, catalog: Catalog) -> tuple[str, ...]:
    report_path = Path(path)
    raw, _ = _read_json(report_path)
    report = _mapping(raw, "report")
    version = report.get("schema_version")
    if isinstance(version, bool) or not isinstance(version, int):
        raise CatalogError("report.schema_version must be an integer")
    if version != REPORT_SCHEMA_VERSION:
        raise CatalogError(
            f"report.schema_version must be {REPORT_SCHEMA_VERSION}"
        )
    results = report.get("results")
    if not isinstance(results, list):
        raise CatalogError("report.results must be an array")
    selected: list[str] = []
    seen: set[str] = set()
    by_id = catalog.scenarios_by_id
    for index, raw_result in enumerate(results):
        location = f"report.results[{index}]"
        result = _mapping(raw_result, location)
        scenario_id = _nonempty_string(result.get("scenario_id"), f"{location}.scenario_id")
        target = _nonempty_string(result.get("target"), f"{location}.target")
        test = _nonempty_string(result.get("test"), f"{location}.test")
        status = _nonempty_string(result.get("status"), f"{location}.status")
        if status not in _REPORT_STATUSES:
            raise CatalogError(f"{location}.status is unknown: {status!r}")
        if scenario_id in seen:
            raise CatalogError(f"report contains duplicate scenario result: {scenario_id}")
        seen.add(scenario_id)
        scenario = by_id.get(scenario_id)
        if scenario is None:
            raise CatalogError(f"report references unknown scenario: {scenario_id}")
        if (target, test) != (scenario.target, scenario.test):
            raise CatalogError(
                f"{location} identity does not match catalog for {scenario_id}: "
                f"expected {scenario.target}::{scenario.test}, got {target}::{test}"
            )
        if status in _FAILED_STATUSES:
            selected.append(scenario_id)
    return tuple(selected)


def select_scenarios(
    catalog: Catalog,
    *,
    suite: str | None = None,
    scenario_ids: Sequence[str] = (),
    failed_from: Path | str | None = None,
    tags: Sequence[str] = (),
) -> tuple[Scenario, ...]:
    """Resolves exactly one primary selector in deterministic catalog order."""

    requested_ids = tuple(scenario_ids)
    primary_count = int(suite is not None) + int(bool(requested_ids)) + int(
        failed_from is not None
    )
    if primary_count != 1:
        raise CatalogError(
            "select exactly one of suite, scenario_ids, or failed_from"
        )
    by_id = catalog.scenarios_by_id
    if suite is not None:
        if suite not in catalog.suites:
            raise CatalogError(f"unknown suite: {suite}")
        selected_ids = set(catalog.suites[suite])
    elif requested_ids:
        invalid = [
            scenario_id
            for scenario_id in requested_ids
            if not isinstance(scenario_id, str) or not scenario_id
        ]
        if invalid:
            raise CatalogError("scenario IDs must be non-empty strings")
        unknown = sorted(set(requested_ids) - set(by_id))
        if unknown:
            raise CatalogError(f"unknown scenarios: {', '.join(unknown)}")
        selected_ids = set(requested_ids)
    else:
        failed_ids = _failed_scenario_ids(failed_from, catalog)  # type: ignore[arg-type]
        selected_ids = set(failed_ids)

    requested_tags = tuple(tags)
    if any(not isinstance(tag, str) or not tag.strip() for tag in requested_tags):
        raise CatalogError("tags must be non-empty strings")
    if len(set(requested_tags)) != len(requested_tags):
        raise CatalogError("tags must not contain duplicates")
    selected = tuple(
        scenario
        for scenario in catalog.scenarios
        if scenario.id in selected_ids
        and all(tag in scenario.tags for tag in requested_tags)
    )
    if not selected:
        raise CatalogError("selector resolved to zero scenarios")
    return selected


def plan(
    catalog: Catalog,
    scenarios: Sequence[Scenario],
) -> Plan:
    """Builds a pure execution preview; it never creates artifacts or resources."""

    if not scenarios:
        raise CatalogError("cannot plan zero scenarios")
    by_id = catalog.scenarios_by_id
    profile_by_id = catalog.profiles_by_id
    selected_ids: set[str] = set()
    for scenario in scenarios:
        canonical = by_id.get(scenario.id)
        if canonical is None or canonical != scenario:
            raise CatalogError(f"scenario is not from this catalog: {scenario.id}")
        selected_ids.add(scenario.id)
    ordered = tuple(
        scenario for scenario in catalog.scenarios if scenario.id in selected_ids
    )

    blockers: list[str] = []
    profiles = tuple(dict.fromkeys(scenario.profile for scenario in ordered))
    for scenario in ordered:
        profile = profile_by_id[scenario.profile]
        reasons: list[str] = []
        if not profile.supported:
            reasons.append(profile.pending_reason or "profile is unsupported")
        if not scenario.supported:
            reasons.append(scenario.pending_reason or "scenario is unsupported")
        if reasons:
            blockers.append(f"{scenario.id}: {'; '.join(dict.fromkeys(reasons))}")
    targets = tuple(dict.fromkeys(scenario.target for scenario in ordered))
    return Plan(
        catalog_sha256=catalog.fingerprint,
        selected=tuple(ordered),
        required_profiles=profiles,
        required_targets=targets,
        runnable=not blockers,
        blockers=tuple(blockers),
    )
