"""The run's own iOS simulator: runtime choice, boot failure and deletion."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_simulator as SIMULATOR

UDID = "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"


def runtime(identifier, version, *, platform="iOS", available=True, device=SIMULATOR.DEVICE_TYPE):
    return {"identifier": identifier, "version": version, "platform": platform,
            "isAvailable": available, "supportedDeviceTypes": [{"identifier": device}]}


class FakeSimctl:
    """Answers simctl like a host with one booted device of this run."""
    def __init__(self, *, boot_fails=False, state="Booted"):
        self.calls = []
        self.boot_fails = boot_fails
        self.state = state

    def __call__(self, *arguments, timeout=120):
        self.calls.append(arguments[0])
        if arguments[0] == "create":
            return UDID + "\n"
        if arguments[0] == "bootstatus" and self.boot_fails:
            raise SIMULATOR.runtime.RunnerError("simctl bootstatus failed")
        if arguments[:2] == ("list", "devices"):
            return json.dumps({"devices": {"iOS-26-3": [{"udid": UDID, "state": self.state}]}})
        return ""


class RuntimeTests(unittest.TestCase):
    def test_the_newest_available_ios_runtime_for_the_device_wins(self):
        inventory = {"runtimes": [
            runtime("iOS-26-3", "26.3.1"), runtime("iOS-27-0", "27.0"),
            runtime("iOS-28-0", "28.0", available=False), runtime("watchOS-12-0", "12.0", platform="watchOS"),
            runtime("iOS-29-0", "29.0", device="com.apple.CoreSimulator.SimDeviceType.iPad-Pro")]}
        with patch.object(SIMULATOR, "_simctl", return_value=json.dumps(inventory)):
            self.assertEqual(SIMULATOR.newest_runtime(), "iOS-27-0")

    def test_no_usable_runtime_is_an_error(self):
        inventory = {"runtimes": [runtime("iOS-27-0", "27.0", available=False)]}
        with patch.object(SIMULATOR, "_simctl", return_value=json.dumps(inventory)), \
             self.assertRaises(SIMULATOR.runtime.RunnerError):
            SIMULATOR.newest_runtime()


class LifecycleTests(unittest.TestCase):
    def test_a_booted_simulator_is_shut_down_and_deleted(self):
        simctl = FakeSimctl()
        with patch.object(SIMULATOR, "_simctl", side_effect=simctl):
            simulator = SIMULATOR.RunSimulator("a1b2c3d4e5", "iOS-26-3")
            self.assertEqual(simulator.describe(),
                {"name": "Vizor Zakura E2E a1b2c3d4e5", "udid": UDID, "runtime": "iOS-26-3"})
            simulator.delete()
        self.assertEqual(simctl.calls, ["create", "bootstatus", "list", "shutdown", "delete"])

    def test_a_simulator_that_fails_to_boot_is_deleted(self):
        simctl = FakeSimctl(boot_fails=True, state="Shutdown")
        with patch.object(SIMULATOR, "_simctl", side_effect=simctl), \
             self.assertRaises(SIMULATOR.runtime.RunnerError):
            SIMULATOR.RunSimulator("a1b2c3d4e5", "iOS-26-3")
        self.assertEqual(simctl.calls, ["create", "bootstatus", "list", "delete"])


class UninstallTests(unittest.TestCase):
    def uninstall(self, installed):
        """Runs uninstall_app while get_app_container reports `installed` in turn."""
        states = iter(installed)
        calls = []

        def run(command, **_kwargs):
            calls.append(command[2])
            return subprocess.CompletedProcess(command, 0 if next(states) else 1)

        def simctl(*arguments, timeout=120):
            calls.append(arguments[0])
            return ""

        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Runner.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.example.model"}))
            with patch.object(SIMULATOR.subprocess, "run", side_effect=run), \
                 patch.object(SIMULATOR, "_simctl", side_effect=simctl):
                SIMULATOR.uninstall_app(UDID, app)
        return calls

    def test_an_app_the_test_run_left_installed_is_uninstalled(self):
        self.assertEqual(self.uninstall([True, False]),
                         ["get_app_container", "terminate", "uninstall", "get_app_container"])

    def test_an_app_flutter_uninstalled_is_left_alone(self):
        self.assertEqual(self.uninstall([False, False]), ["get_app_container", "get_app_container"])

    def test_an_app_that_survives_uninstall_is_an_error(self):
        with self.assertRaises(SIMULATOR.runtime.RunnerError):
            self.uninstall([True, True])


if __name__ == "__main__":
    unittest.main()
