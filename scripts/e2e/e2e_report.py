"""Normalize Rust attempts without losing failures or unstarted scenarios."""

from __future__ import annotations

from typing import Any, Mapping, Sequence


def normalize_results(
    selected_scenarios: Sequence[Mapping[str, Any]],
    attempts: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Report every selected scenario once, including fail-fast omissions."""
    selected = {
        (scenario["target"], scenario["test"]): scenario
        for scenario in selected_scenarios
    }
    if len(selected) != len(selected_scenarios):
        raise ValueError("selected scenarios contain duplicate test identities")
    ids = [scenario["scenario_id"] for scenario in selected_scenarios]
    if len(ids) != len(set(ids)):
        raise ValueError("selected scenarios contain duplicate scenario IDs")

    by_test: dict[tuple[str, str], Mapping[str, Any]] = {}
    for attempt in attempts:
        identity = (attempt["target"], attempt["test"])
        if identity not in selected:
            raise ValueError(f"attempted an unselected test: {identity}")
        if identity in by_test:
            raise ValueError(f"recorded a test attempt more than once: {identity}")
        if "returncode" not in attempt:
            raise ValueError(f"attempt must include returncode: {identity}")
        code = attempt["returncode"]
        error = attempt.get("error")
        if code is None:
            if not isinstance(error, str) or not error.strip():
                raise ValueError(
                    "attempt returncode may be None only for a spawn failure "
                    f"with a non-empty error: {identity}"
                )
        elif isinstance(code, bool) or not isinstance(code, int):
            raise ValueError(f"attempt returncode must be an integer: {identity}")
        by_test[identity] = attempt

    results: list[dict[str, Any]] = []
    for scenario in selected_scenarios:
        identity = (scenario["target"], scenario["test"])
        attempt = by_test.get(identity)
        result: dict[str, Any] = {
            "scenario_id": scenario["scenario_id"],
            "profile": scenario["profile"],
            "target": scenario["target"],
            "test": scenario["test"],
            "status": "not_run",
            "failure_kind": None,
            "attempt": 0,
            "worker_id": None,
            "returncode": None,
            "duration_seconds": 0.0,
            "log": None,
            "error": None,
        }
        if attempt is not None:
            for field in ("worker_id", "returncode", "duration_seconds", "log", "error"):
                if field in attempt:
                    result[field] = attempt[field]
            result["attempt"] = 1
            code = attempt["returncode"]
            error = attempt.get("error")
            if code == 0 and error is None:
                result["status"] = "passed"
            elif code == 124:
                result.update(status="timed_out", failure_kind="timeout")
            elif code == 130:
                result.update(status="cancelled", failure_kind="cancelled")
            else:
                result.update(
                    status="failed",
                    failure_kind="process" if error is not None else "test",
                )
        results.append(result)
    return results
