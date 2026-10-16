"""The iOS simulator a run creates for its Flutter iOS scenarios.

A run never targets a simulator it did not create. It creates one iPhone 16,
boots it, runs every iOS scenario on it and deletes it afterwards. `flutter
test` installs the app afresh for each scenario, and the app clears Keychain
entries left by an earlier install on its first launch.
"""
from __future__ import annotations

import json
import plistlib
import re
import subprocess

import e2e_runtime as runtime

DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
_UDID = re.compile(r"^[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}$")


def _simctl(*arguments, timeout=120):
    try:
        completed = subprocess.run(["/usr/bin/xcrun", "simctl", *arguments],
            capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise runtime.RunnerError(f"simctl {arguments[0]} did not finish within {timeout}s") from error
    if completed.returncode:
        raise runtime.RunnerError(f"simctl {arguments[0]} failed: {completed.stderr.strip()}")
    return completed.stdout


def newest_runtime():
    """The newest available iOS runtime that can run an iPhone 16."""
    runtimes = json.loads(_simctl("list", "runtimes", "--json"))["runtimes"]
    usable = [item for item in runtimes
              if item.get("platform") == "iOS" and item.get("isAvailable") is True
              and any(kind.get("identifier") == DEVICE_TYPE for kind in item.get("supportedDeviceTypes", ()))]
    if not usable:
        raise runtime.RunnerError("no available iOS simulator runtime can run an iPhone 16")
    return max(usable, key=lambda item: tuple(int(part) for part in item["version"].split(".")))["identifier"]


def uninstall_app(udid, app):
    """Uninstall the built `app` (a Runner.app path) if a test run left it on the device.

    Flutter's integration runner normally uninstalls the app when it finishes.
    """
    bundle = plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"]
    if _installed(udid, bundle):
        try:
            _simctl("terminate", udid, bundle)
        except runtime.RunnerError:
            pass  # The app was not running.
        _simctl("uninstall", udid, bundle)
    if _installed(udid, bundle):
        raise runtime.RunnerError(f"{bundle} is still installed after simctl uninstall")


def _installed(udid, bundle):
    return subprocess.run(["/usr/bin/xcrun", "simctl", "get_app_container", udid, bundle, "data"],
        capture_output=True, timeout=120).returncode == 0


class RunSimulator:
    """Create and boot this run's simulator; delete() removes only that device."""

    def __init__(self, run_id, runtime_identifier):
        self.name = f"Vizor Zakura E2E {run_id}"
        self.runtime = runtime_identifier
        udid = _simctl("create", self.name, DEVICE_TYPE, runtime_identifier).strip()
        if not _UDID.match(udid):
            raise runtime.RunnerError(f"simctl create returned an invalid UDID: {udid!r}")
        self.udid = udid
        try:
            _simctl("bootstatus", udid, "-b", timeout=600)
        except BaseException as primary:
            try:
                self.delete()
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    def describe(self):
        return {"name": self.name, "udid": self.udid, "runtime": self.runtime}

    def delete(self):
        """Shut the device down if it still runs, then delete it."""
        state = json.loads(_simctl("list", "devices", "--json"))["devices"]
        booted = any(device.get("udid") == self.udid and device.get("state") != "Shutdown"
                     for devices in state.values() for device in devices)
        if booted:
            _simctl("shutdown", self.udid)
        _simctl("delete", self.udid)
