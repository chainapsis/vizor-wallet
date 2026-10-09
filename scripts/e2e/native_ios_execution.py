"""Run real mobile assertions through the original owned Simulator app/Driver."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import threading
import time

import e2e_runtime as runtime
from native_ios_case_storage import OwnedIosCaseStorage
from native_worker_lifecycle import NativeWorkerCase
from native_zakura_front import _capture
from native_ios_migration import IOS_MIGRATION_SCENARIOS


IOS_SCENARIOS = frozenset({
    "flutter.ios.create-sync", "flutter.ios.import-sync", "flutter.ios.account-management",
    "flutter.ios.multi-account-send", "flutter.ios.mempool-receive",
    "flutter.ios.fallback-endpoint", "flutter.ios.slow-height-fallback",
    "flutter.ios.payment-link-round-trip", "flutter.ios.payment-uri-send",
    "flutter.ios.gift-onboarding",
}) | IOS_MIGRATION_SCENARIOS
IOS_RESTART_SCENARIOS = frozenset({
    "flutter.ios.ironwood-migration-restart", "flutter.ios.ironwood-background-restart",
})


class NativeIosExecutionError(runtime.RunnerError):
    """Real app/case/Driver binding or assertion completion failed."""


def execute_native_ios_case(session, *, dart, source_root, timeout=600.0, cancel_event=None,
                            send_recipient=None, _phase=None):
    if (not isinstance(session, NativeWorkerCase) or not isinstance(session.storage, OwnedIosCaseStorage)
        or session._front is None or session._control is None or session._finished):
        raise NativeIosExecutionError("expected this original prepared iOS worker case")
    runtime._positive_timeout(timeout)
    root = Path(source_root)
    executable = Path(dart).resolve(strict=True)
    if not root.is_absolute() or root.resolve(strict=True) != root or not os.access(executable, os.X_OK):
        raise NativeIosExecutionError("execution source/Dart must be explicit and canonical")
    environment = {**os.environ, **session.case.workspace.launch_environment()}
    manifest = json.loads(environment["VIZOR_E2E_CASE_MANIFEST"])
    if manifest["scenario_id"] not in IOS_SCENARIOS:
        raise NativeIosExecutionError("this mobile cohort does not implement the selected case")
    is_restart = manifest["scenario_id"] in IOS_RESTART_SCENARIOS
    if is_restart and _phase is None:
        # Both phases use the same originally installed app/container. No
        # reinstallation, snapshot restore or replacement wallet is involved.
        started = time.monotonic()
        prepare = execute_native_ios_case(session, dart=dart, source_root=root,
            timeout=timeout, cancel_event=cancel_event, _phase="prepare")
        def remaining():
            if cancel_event is not None and cancel_event.is_set():
                raise runtime.Cancelled()
            budget = timeout-(time.monotonic()-started)
            if budget <= 0:
                raise NativeIosExecutionError("mobile restart exhausted its whole-case deadline", 124)
            return budget
        session.storage.stop_app(session.storage._active, timeout=min(30, remaining()))
        remaining()
        session.backend.mine(50)
        resume = execute_native_ios_case(session, dart=dart, source_root=root,
            timeout=remaining(), cancel_event=cancel_event, _phase="resume")
        if prepare["app_pid"] == resume["app_pid"] or prepare["simulator_udid"] != resume["simulator_udid"]:
            raise NativeIosExecutionError("mobile restart did not preserve its original Simulator with a new app PID")
        return {"scenario_id":manifest["scenario_id"], "namespace":manifest["namespace"],
            "prepare":prepare, "resume":resume, "assertions_passed":True,
            "native_cleanup_pending":True}
    if _phase is not None and (not is_restart or _phase not in {"prepare", "resume"}):
        raise NativeIosExecutionError("invalid original mobile restart phase")
    for key in ("VIZOR_E2E_PAYMENT_LINK_PHASE", "VIZOR_E2E_VOTING_PHASE", "VIZOR_E2E_IOS_PHASE"):
        environment.pop(key, None)
    if _phase is not None:
        environment["VIZOR_E2E_IOS_PHASE"] = _phase
    driver = root/"test_driver/native_owned_case.dart"
    source = {path:_capture(path) for path in
              (driver, root/".dart_tool/package_config.json", executable)}
    cancel = cancel_event if cancel_event is not None else threading.Event()
    deadline = time.monotonic() + timeout
    if cancel.is_set():
        raise runtime.Cancelled()
    session.verify_owned()
    # Flutter's Simulator engine publishes its VM endpoint through unified
    # logging, not the simctl application's stdout. Start this original reader
    # before launch so the one startup event cannot be missed. The SDK UUID is
    # already owned; records are additionally bound to the actual UIKit PID.
    log_lines = []
    log_reader = session.case.start_process(["/usr/bin/xcrun", "simctl", "spawn",
        session.storage.simulator.udid, "log", "stream", "--style", "ndjson",
        "--level", "debug", "--predicate", 'processImagePath ENDSWITH "/Runner" AND eventMessage CONTAINS "The Dart VM service is listening on"'],
        env={"PATH":"/usr/bin:/bin", "LANG":"en_US.UTF-8"},
        raw_lines=log_lines, max_output_bytes=8*1024*1024)
    app_lines = []
    app = session.storage.start_app(timeout=min(30.0, timeout), cancel_event=cancel,
        raw_lines=app_lines, max_output_bytes=8*1024*1024, phase=_phase,
        send_recipient=send_recipient)
    startup_deadline = min(deadline, time.monotonic() + 30.0)

    def check():
        if cancel.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= deadline:
            raise NativeIosExecutionError("native iOS integration deadline expired", 124)
        session.verify_owned()
        session._front.assert_running()
        # The SDK console PID is NOT the native UIKit app PID. Bind both to
        # their original owners, and require the currently active native job.
        session.case._require_member(app.console)
        if session.storage._active is not app or session.storage._jobs(
            deadline=deadline, cancel_event=cancel) != [app.pid]:
            raise NativeIosExecutionError("original iOS app job is no longer running")
        if app.console.process.poll() is not None or app.console._capture.errors or app.console._capture.output_limit_error:
            raise NativeIosExecutionError("original iOS console/output completed before its assertions")
        session.case._require_member(log_reader)
        if (log_reader.process.poll() is not None or log_reader._capture.errors
            or log_reader._capture.output_limit_error is not None):
            raise NativeIosExecutionError("original iOS unified-log reader/output failed")

    seen_lines, urls = 0, []
    while True:
        check()
        for line in log_lines[seen_lines:]:
            seen_lines += 1
            if not line.lstrip().startswith("{"):
                continue  # The SDK's filtering banner is transport metadata.
            record = json.loads(line)
            if not isinstance(record, dict) or not isinstance(record.get("eventMessage"), str):
                raise NativeIosExecutionError("original iOS unified-log record is invalid")
            endpoints = re.findall(r"The Dart VM service is listening on (http://(?:127\.0\.0\.1|localhost):[1-9][0-9]{0,4}/[^\s]*)",
                                   record["eventMessage"])
            if endpoints:
                if type(record.get("processID")) is not int or record["processID"] != app.pid:
                    raise NativeIosExecutionError("iOS VM endpoint is not from the original native app PID")
                urls.extend(endpoints)
        if urls:
            if len(set(urls)) != 1:
                raise NativeIosExecutionError("original iOS VM endpoint is ambiguous")
            vm_url = urls[0]
            break
        if time.monotonic() >= startup_deadline:
            raise NativeIosExecutionError("original iOS app did not publish its VM endpoint")
        session._control.pump(deadline=deadline, cancel_event=cancel)
    driver_lines = []
    process = session.case.start_process([str(executable),
        "--packages="+str(root/".dart_tool/package_config.json"), str(driver)],
        env={**environment, "VM_SERVICE_URL":vm_url, "VIZOR_E2E_APP_PID":str(app.pid)},
        raw_lines=driver_lines, max_output_bytes=2*1024*1024)
    while process.process.poll() is None:
        check()
        session._control.pump(deadline=deadline, cancel_event=cancel)
    code = session.case.wait_process(process, timeout=deadline-time.monotonic(), cancel_event=cancel)
    if code:
        raise NativeIosExecutionError("original iOS Driver reported failing assertions", code)
    markers = [line[len("VIZOR_E2E_RESULT="):] for line in driver_lines if line.startswith("VIZOR_E2E_RESULT=")]
    if len(markers) != 1:
        raise NativeIosExecutionError("original iOS Driver did not publish exactly one result")
    result = json.loads(markers[0])
    if (not isinstance(result, dict) or set(result) != ({"case_manifest", "pid", "ios_phase"} if _phase else {"case_manifest", "pid"})
        or result["case_manifest"] != manifest or type(result["pid"]) is not int or result["pid"] != app.pid):
        raise NativeIosExecutionError("iOS result is not bound to the original native app/case")
    if _phase and result["ios_phase"] != _phase:
        raise NativeIosExecutionError("iOS result does not match its original restart phase")
    check()
    session.storage._verify_context(app.pid)
    if {path:_capture(path) for path in source} != source:
        raise NativeIosExecutionError("original iOS Driver source/tool changed")
    session.storage.helper.verify_unchanged()
    session.case.stop_process(process, timeout=min(5.0, deadline-time.monotonic()))
    session.case.stop_process(log_reader, timeout=min(5.0, deadline-time.monotonic()))
    return {"scenario_id":manifest["scenario_id"], "namespace":manifest["namespace"],
        "simulator_udid":app.udid, "app_pid":app.pid, "console_pid":app.console.process.pid,
        "driver_pid":process.process.pid, "driver_exit_code":code,
        "unified_log_pid":log_reader.process.pid,
        **({"ios_phase":_phase} if _phase else {}),
        "assertions_passed":True, "native_cleanup_pending":True}
