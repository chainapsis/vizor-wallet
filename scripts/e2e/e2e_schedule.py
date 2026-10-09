"""Pure timing-informed dispatch; reports are estimates, never PASS authority."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import math
from pathlib import Path
import re
import statistics

from e2e_catalog import CatalogError, Scenario, _read_json


ORDERS = ("catalog", "short-first", "long-first")
_STATUSES = {"passed", "failed", "timed_out", "cancelled", "not_run"}


@dataclass(frozen=True)
class Schedule:
    indices: tuple[int, ...]
    record: dict


def schedule_scenarios(catalog, scenarios, *, order="short-first", timing_reports=()):
    """Keep case identities intact; only order the selected dispatch indices.

    Successful case durations include preparation and cleanup, not shared builds.
    Unknown timings follow measured cases in catalog order. Failed timings are
    not estimates of a completed scenario. Source revisions remain provenance,
    not a claim that an older run validates the currently selected code.
    """
    if order not in ORDERS:
        raise CatalogError("unknown dispatch order: " + str(order))
    selected = tuple(scenarios)
    canonical = catalog.scenarios_by_id
    if (any(not isinstance(case, Scenario) or canonical.get(case.id) != case for case in selected)
        or len({case.id for case in selected}) != len(selected)):
        raise CatalogError("schedule requires distinct current catalog cases")
    if isinstance(timing_reports, (str, bytes, Path)):
        raise CatalogError("timing reports must be a sequence of paths")
    samples, history, paths, hashes = {}, [], set(), set()
    for supplied in timing_reports:
        path = Path(supplied).resolve(strict=True)
        raw, encoded = _read_json(path)
        digest = hashlib.sha256(encoded).hexdigest()
        if path in paths or digest in hashes:
            raise CatalogError("duplicate timing report: " + str(path))
        paths.add(path)
        hashes.add(digest)
        if (not isinstance(raw, dict) or type(raw.get("schema_version")) is not int
            or raw["schema_version"] != 2 or raw.get("catalog_sha256") != catalog.fingerprint
            or not isinstance(raw.get("source_commit"), str)
            or not re.fullmatch(r"[0-9a-f]{40}", raw["source_commit"])
            or not isinstance(raw.get("results"), list) or not raw["results"]):
            raise CatalogError("timing report must bind schema 2, current catalog and source: " + str(path))
        seen = set()
        for result in raw["results"]:
            if not isinstance(result, dict) or not isinstance(result.get("scenario_id"), str):
                raise CatalogError("invalid timing result identity: " + str(path))
            case = canonical.get(result["scenario_id"])
            if (case is None or case.id in seen
                or (result.get("profile"), result.get("target"), result.get("test"))
                    != (case.profile, case.target, case.test)
                or not isinstance(result.get("status"), str) or result["status"] not in _STATUSES):
                raise CatalogError("timing result does not match its current catalog case: " + str(path))
            seen.add(case.id)
            duration = result.get("duration_seconds")
            if (isinstance(duration, bool) or not isinstance(duration, (int, float))
                or not math.isfinite(duration) or duration < 0
                or result["status"] == "passed" and duration == 0):
                raise CatalogError("invalid case duration in timing report: " + str(path))
            if result["status"] == "passed":
                samples.setdefault(case.id, []).append(float(duration))
        history.append({"path":str(path), "sha256":digest, "source_commit":raw["source_commit"]})
    estimates = {case.id:float(statistics.median(samples[case.id]))
                 for case in selected if case.id in samples}
    for case_id, estimate in estimates.items():
        if not math.isfinite(estimate):
            raise CatalogError("non-finite median timing estimate for case: " + case_id)
    catalog_index = {case.id:index for index, case in enumerate(catalog.scenarios)}
    indices = list(range(len(selected)))
    def priority(index):
        case = selected[index]
        if order == "catalog" or case.id not in estimates:
            return (int(order != "catalog"), 0.0, catalog_index[case.id])
        return (0, estimates[case.id] * (-1 if order == "long-first" else 1), catalog_index[case.id])
    indices.sort(key=priority)
    return Schedule(tuple(indices), {
        "order":order, "dispatch_indices":indices,
        "dispatch_scenarios":[selected[index].id for index in indices],
        "estimated_seconds":estimates,
        "estimate_samples":{case.id:len(samples[case.id]) for case in selected if case.id in samples},
        "history_sources":history,
    })
