#!/usr/bin/env python3
"""Select E2Es without side effects, or explicitly run supported isolated cases."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Sequence


# A preview must not create bytecode caches in the checkout either.
sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import e2e_catalog
import e2e_changes
import e2e_impact
import e2e_schedule


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Preview Vizor E2E selections or run supported isolated native cases"
    )
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--suite")
    selection.add_argument("--scenario", dest="scenarios", action="append")
    selection.add_argument("--failed-from", type=Path)
    selection.add_argument(
        "--changed-file", dest="changed_files", action="append",
        help="select by repository-relative path; repeat for more paths",
    )
    selection.add_argument(
        "--changed-from",
        help="select changes since the Git merge base with REF, including local changes",
    )
    parser.add_argument(
        "--tag", dest="tags", action="append", default=[],
        help="require a tag; repeat to require all tags",
    )
    display = parser.add_mutually_exclusive_group()
    display.add_argument("--list", action="store_true")
    display.add_argument("--plan", action="store_true")
    display.add_argument("--run", action="store_true")
    parser.add_argument("--flutter", type=Path)
    parser.add_argument("--zakura-cache", type=Path)
    parser.add_argument("--grpcurl", type=Path)
    parser.add_argument("--proto-dir", type=Path)
    parser.add_argument("--ios-runtime", help="available CoreSimulator runtime identifier (iOS only)")
    parser.add_argument("--ios-device-type", help="device type supported by that runtime (iOS only)")
    parser.add_argument("--voting-sdk-cache", type=Path,
                        help="Git source cache containing the pinned vote-sdk commit (voting only)")
    parser.add_argument("--voting-pir-cache", type=Path,
                        help="Git source cache containing the pinned PIR commit (voting only)")
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--repeat", type=int, default=1,
                        help="fresh isolated repetitions, each with its own rerunnable report")
    parser.add_argument("--build-jobs", type=int, default=4)
    parser.add_argument("--order", choices=e2e_schedule.ORDERS, default="short-first",
                        help="dispatch by measured successful case duration, or catalog order")
    parser.add_argument("--timing-report", dest="timing_reports", type=Path, action="append", default=[],
                        help="schema-2 case report for duration estimates; repeat for median samples")
    return parser.parse_args(argv)


def _select(
    args: argparse.Namespace, catalog: e2e_catalog.Catalog,
) -> tuple[tuple[e2e_catalog.Scenario, ...], dict[str, Any]]:
    tags = tuple(args.tags)
    if any(not tag or tag != tag.strip() for tag in tags):
        raise e2e_catalog.CatalogError("tags must be non-empty trimmed strings")
    if len(set(tags)) != len(tags):
        raise e2e_catalog.CatalogError("tags must not contain duplicates")

    if args.changed_files is not None or args.changed_from is not None:
        git = None
        if args.changed_from is not None:
            changes = e2e_changes.collect_changed_files(REPO_ROOT, args.changed_from)
            paths, git = changes.paths, changes.git
            kind, values = "changed_from", [args.changed_from]
        else:
            paths = tuple(args.changed_files)
            kind, values = "changed_file", list(args.changed_files)
        impact = e2e_impact.select_changed_scenarios(catalog, paths, tags=tags)
        provenance = e2e_impact.make_changed_provenance(
            impact, kind=kind, values=values, tags=tags, git=git,
        )
        return impact.scenarios, provenance

    if args.suite is not None:
        kind, values = "suite", [args.suite]
    elif args.scenarios is not None:
        kind, values = "scenario", list(args.scenarios)
    elif args.failed_from is not None:
        kind, values = "failed_from", [str(args.failed_from)]
    elif args.list:
        scenarios = tuple(
            scenario for scenario in catalog.scenarios
            if all(tag in scenario.tags for tag in tags)
        )
        if not scenarios:
            raise e2e_catalog.CatalogError("selection matched no E2E scenarios")
        return scenarios, {"kind": "list", "values": ["all"], "tags": list(tags)}
    else:
        raise e2e_catalog.CatalogError(
            "select one of --suite, --scenario, --failed-from, --changed-file, or --changed-from"
        )

    scenarios = e2e_catalog.select_scenarios(
        catalog, suite=args.suite, scenario_ids=tuple(args.scenarios or ()),
        failed_from=args.failed_from, tags=tags,
    )
    return scenarios, {"kind": kind, "values": values, "tags": list(tags)}


def _list_record(
    catalog: e2e_catalog.Catalog, scenario: e2e_catalog.Scenario,
) -> dict[str, Any]:
    profile = catalog.profiles_by_id[scenario.profile]
    reasons = tuple(dict.fromkeys(
        reason for reason in (scenario.pending_reason, profile.pending_reason) if reason
    ))
    return {
        "scenario_id": scenario.id,
        "engine": scenario.engine,
        "script": scenario.script,
        "target": scenario.target,
        "test": scenario.test,
        "profile": scenario.profile,
        "tags": list(scenario.tags),
        "timeout_seconds": scenario.timeout_seconds,
        "supported": scenario.supported,
        "runnable": scenario.supported and profile.supported,
        "pending_reason": "; ".join(reasons) if reasons else None,
    }


def run(args: argparse.Namespace) -> int:
    if not (args.list or args.plan or args.run):
        raise e2e_catalog.CatalogError(
            "execution requires --run; use --list or --plan for a side-effect-free preview"
        )
    catalog = e2e_catalog.load_catalog()
    scenarios, selection = _select(args, catalog)
    schedule = e2e_schedule.schedule_scenarios(catalog, scenarios,
        order=args.order, timing_reports=args.timing_reports)
    if args.run:
        if not scenarios:
            print(json.dumps({"selection":selection,"execution_mode":"no-tests","results":[]}))
            return 0
        plan = e2e_catalog.plan(catalog, scenarios)
        if not plan.runnable:
            raise e2e_catalog.CatalogError("selected execution is pending: " + "; ".join(plan.blockers))
        if sys.version_info < (3, 11):
            raise e2e_catalog.CatalogError("isolated execution requires Python 3.11 or newer")
        # Keep all backend/platform imports out of side-effect-free previews.
        from native_macos_suite import run_native_suite
        return run_native_suite(args,catalog,scenarios,selection,source_root=REPO_ROOT)
    if args.list:
        record = {
            "catalog_sha256": catalog.fingerprint,
            "selection": selection,
            "scenarios": [_list_record(catalog, scenario) for scenario in scenarios],
        }
    else:
        plan = e2e_catalog.plan(catalog, scenarios) if scenarios else None
        record = {
            "catalog_sha256": catalog.fingerprint,
            "selection": selection,
            "selected_scenarios": [
                {
                    "scenario_id": scenario.id,
                    "profile": scenario.profile,
                    "target": scenario.target,
                    "test": scenario.test,
                    "timeout_seconds": scenario.timeout_seconds,
                }
                for scenario in scenarios
            ],
            "engines": list(dict.fromkeys(scenario.engine for scenario in scenarios)),
            "required_profiles": list(plan.required_profiles) if plan else [],
            "required_targets": list(plan.required_targets) if plan else [],
            "runnable": plan.runnable if plan else False,
            "execution_mode": ("ready" if plan.runnable else "blocked") if scenarios else "no-tests",
            "pending_blockers": list(plan.blockers) if plan else [],
        }
    record["schedule"] = schedule.record
    print(json.dumps(record, indent=2, sort_keys=True, allow_nan=False))
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    try:
        return run(parse_args(argv))
    except (e2e_catalog.CatalogError, ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
