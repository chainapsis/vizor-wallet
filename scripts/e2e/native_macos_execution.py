"""Run an existing selected integration test through an original native worker.

The artifact builder supplies its own compiled/signed cohort and cleanup helper.
This execution boundary neither adopts caches nor enables pending catalog cases.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import threading
import time

import e2e_runtime as runtime
from native_mac_case_storage import MacCaseStorage
from native_worker_lifecycle import NativeWorkerCase
from native_zakura_front import _capture


class NativeMacosExecutionError(runtime.RunnerError):
    """Original app/driver identity, assertion result or process completion failed."""


def execute_native_macos_case(session, *, dart, source_root, timeout=600.0, cancel_event=None):
    """Direct app launch + original VM driver; caller finalizes or retains this case."""
    if (not isinstance(session, NativeWorkerCase) or not isinstance(session.storage, MacCaseStorage)
        or session._front is None or session._control is None or session._finished):
        raise NativeMacosExecutionError("expected this original prepared native macOS worker case")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not 0 < timeout < float("inf"):
        raise NativeMacosExecutionError("execution timeout must be positive and finite")
    root = Path(source_root)
    executable = Path(dart).resolve(strict=True)
    if not root.is_absolute() or root.resolve(strict=True) != root or not os.access(executable, os.X_OK):
        raise NativeMacosExecutionError("execution source/Dart must be explicit and canonical")
    driver = root / "test_driver/native_owned_case.dart"
    paths = (driver, root/".dart_tool/package_config.json", executable)
    source = {path:_capture(path) for path in paths}
    session.verify_owned()
    session.storage.helper.verify_unchanged()
    environment = {**os.environ, **session.case.workspace.launch_environment()}
    manifest = json.loads(environment["VIZOR_E2E_CASE_MANIFEST"])
    if manifest["scenario_id"] == "flutter.macos.tex-send":
        environment["ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW"] = "1"
    if manifest["scenario_id"] == "flutter.macos.mempool-during-sync":
        # Match the existing shell test: prove pending discovery during real sync,
        # without throttling sibling cases or the parent process.
        environment["ZCASH_E2E_SYNC_BATCH_SIZE"] = "50"
        environment["ZCASH_E2E_SYNC_BATCH_DELAY_MS"] = "750"
    cancel = cancel_event if cancel_event is not None else threading.Event()
    deadline = time.monotonic() + timeout
    if cancel.is_set():
        raise runtime.Cancelled()
    app_lines = []
    app = session.storage.start_app(env=environment, raw_lines=app_lines, max_output_bytes=8*1024*1024)
    startup_deadline = min(deadline, time.monotonic() + 30.0)

    def check():
        if cancel.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= deadline:
            raise NativeMacosExecutionError("native integration deadline expired", 124)
        session.verify_owned()
        session._front.assert_running()
        session.case._require_member(app)
        if app.process.poll() is not None:
            raise NativeMacosExecutionError("original native app exited before its integration result")
        if app._capture.errors or app._capture.output_limit_error is not None:
            raise NativeMacosExecutionError("original native app output failed")

    while True:
        check()
        # Read only this original child pipe's capture, never adopt a pathname log.
        urls = re.findall(r"The Dart VM service is listening on (http://(?:127\.0\.0\.1|localhost):[1-9][0-9]{0,4}/[^\s]*)",
                          "".join(app_lines))
        if urls:
            if len(set(urls)) != 1:
                raise NativeMacosExecutionError("original native app VM endpoint is ambiguous")
            vm_url = urls[0]
            break
        if time.monotonic() >= startup_deadline:
            raise NativeMacosExecutionError("original native app did not publish its VM endpoint")
        session._control.pump(deadline=deadline, cancel_event=cancel)
    check()
    driver_lines = []
    driver_process = session.case.start_process([str(executable),
        "--packages="+str(root/".dart_tool/package_config.json"), str(driver)],
        env={**environment,"VM_SERVICE_URL":vm_url,"VIZOR_E2E_APP_PID":str(app.process.pid)},
        max_output_bytes=2*1024*1024, raw_lines=driver_lines)
    while driver_process.process.poll() is None:
        check()
        session._control.pump(deadline=deadline, cancel_event=cancel)
    code = session.case.wait_process(driver_process, timeout=deadline-time.monotonic(), cancel_event=cancel)
    if code != 0:
        raise NativeMacosExecutionError("original integration driver reported failing assertions", code)
    markers = [line[len("VIZOR_E2E_RESULT="):] for line in driver_lines
               if line.startswith("VIZOR_E2E_RESULT=")]
    if len(markers) != 1:
        raise NativeMacosExecutionError("original driver did not publish exactly one integration result")
    result = json.loads(markers[0])
    if (not isinstance(result, dict) or set(result) != {"case_manifest","pid"}
        or result["case_manifest"] != manifest or type(result["pid"]) is not int
        or result["pid"] != app.process.pid):
        raise NativeMacosExecutionError("integration result is not bound to this original app/case")
    check()
    if {path:_capture(path) for path in source} != source:
        raise NativeMacosExecutionError("original integration driver source/tool changed")
    session.storage.helper.verify_unchanged()
    return {"scenario_id":manifest["scenario_id"], "namespace":manifest["namespace"],
            "app_pid":app.process.pid,"driver_pid":driver_process.process.pid,
            "driver_exit_code":code,"assertions_passed":True,"native_cleanup_pending":True}
