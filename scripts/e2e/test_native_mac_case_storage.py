"""Owned support tests: real private files/children; modelled signing/native I/O."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import threading
import time
import unittest
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
try:
    import native_mac_case_storage as STORAGE
    import test_native_mac_cleanup as FIXTURES
finally:
    sys.path.pop(0)


class MacCaseStorageTests(unittest.TestCase):
    def setUp(self):
        # Reuse the isolated signed-artifact fixture, not its test methods/results.
        self.host = FIXTURES.MacCleanupHostTests()
        self.host.setUp()
        self.addCleanup(self.host.doCleanups)
        self.case = self.host.case
        self.home = self.host.root / "model-home"
        self.sdk_base = self.home / "Library/Containers/com.keplr.vizor/Data/Library/Application Support"
        self.sdk_base.mkdir(parents=True, mode=0o700)
        home_patch = patch.object(STORAGE, "_home", return_value=self.home)
        home_patch.start()
        self.addCleanup(home_patch.stop)
        self.context_updates = {}
        self.probe_updates = {}
        self.verify_updates = {}
        self.helper_code = ""
        self.app_code = ""
        self.install_scripts()

    def path(self, *, case=None):
        selected = self.case if case is None else case
        return self.sdk_base / "com.keplr.vizor/e2e" / selected.workspace.namespace

    def install_scripts(self):
        self.host.rewrite_helper(f"""
import json,sys,os
from pathlib import Path
ns=sys.argv[sys.argv.index('--namespace')+1]
support=Path({str(self.sdk_base)!r})/'com.keplr.vizor/e2e'/ns
value={FIXTURES.receipt()!r}
value.update(namespace=ns)
service='com.keplr.vizor.regtest.secure_store.e2e.'+ns
for item,target in zip(value['keychain'],[service,service+'.mnemonic']): item['service']=target
value['preferences']['prefix']='flutter.vizor_e2e_'+ns+'.'
if '--support-location' in sys.argv:
 value={{'schema_version':1,'platform':'macos','mode':'support_location','namespace':ns,
 'expected_team':{FIXTURES.TEAM!r},'identity':value['identity'],
 'support_directory':str(support),'completed':True}}
 value.update({self.probe_updates!r})
elif '--verify' in sys.argv:
 value['mode']='verify'
 for item in value['keychain']:
  del item['delete_status']
  item.update(before_status=-25300,after_status=-25300)
 value['preferences'].update(before_count=0,removed_count=0)
 value.update({self.verify_updates!r})
else:
 {self.helper_code or 'pass'}
print(json.dumps(value))
""")
        executable = self.host.cohort_app / "Contents/MacOS/Cohort"
        executable.write_text(f"#!{sys.executable}\n" + f"""
import json,os,time
from pathlib import Path
manifest=json.loads(os.environ['VIZOR_E2E_CASE_MANIFEST'])
ns=manifest['namespace']
support=Path({str(self.sdk_base)!r})/'com.keplr.vizor/e2e'/ns
(support/'wallet.db').write_text('synthetic-wallet-state')
service='com.keplr.vizor.regtest.secure_store.e2e.'+ns
context={{'schema_version':1,'namespace':ns,'pid':os.getpid(),'support_directory':str(support),
'secure_store_services':[service,service+'.mnemonic'],'preferences_prefix':'flutter.vizor_e2e_'+ns+'.',
'os_background_scheduling_enabled':False,'storage_cleanup_completed':False}}
context.update({self.context_updates!r})
Path(manifest['context_path']).write_text(json.dumps(context))
print('owned-app-ready',flush=True)
{self.app_code or 'pass'}
""")

    def prepare(self, *, case=None):
        return STORAGE.prepare_mac_case_storage(
            case or self.case, self.host.capture(), timeout=3, cancel_event=threading.Event(),
        )

    def close(self, owner):
        return owner.close(timeout=3, cancel_event=threading.Event())

    def app(self, owner):
        managed = owner.start_app(env=os.environ)
        owner.case.wait_process(managed, timeout=3, cancel_event=threading.Event())
        return managed

    def test_fresh_probe_allocates_original_private_support_before_app(self):
        owner = self.prepare()
        self.assertEqual(owner.path, self.path())
        self.assertEqual(owner.path.stat().st_mode & 0o777, 0o700)
        self.assertEqual(owner.case.launched_process_count, 2)
        self.assertTrue(owner.case.accepting_launches)
        self.assertEqual(set(file.name for file in owner.path.iterdir()), {STORAGE._MARKER})
        self.assertTrue(owner.case.workspace.marker_path.exists())
        owner.verify_owned()

    def test_restart_stops_original_writer_and_archives_context_without_native_deletion(self):
        owner = self.prepare()
        first = self.app(owner)
        wallet = owner.path/"wallet.db"
        identity = (wallet.stat().st_dev, wallet.stat().st_ino, wallet.read_bytes())
        owner.stop_app_for_restart(first, timeout=3)
        self.assertTrue(first.cleanup_completed)
        self.assertTrue(self.case.accepting_launches)
        context = Path(self.case.workspace.context_path)
        self.assertFalse(context.exists())
        archived = context.with_name("native-context-before-restart.json")
        self.assertEqual(json.loads(archived.read_text())["pid"], first.process.pid)
        self.assertEqual(archived.stat().st_mode & 0o777, 0o600)
        second = self.app(owner)
        self.assertNotEqual(first.process.pid, second.process.pid)
        self.assertEqual((wallet.stat().st_dev, wallet.stat().st_ino, wallet.read_bytes()), identity)
        self.close(owner)
        self.assertTrue(archived.exists())

    def test_restart_does_not_overwrite_existing_evidence(self):
        owner = self.prepare()
        app = self.app(owner)
        archive = self.case.workspace.root/"native-context-before-restart.json"
        archive.write_text("retained evidence")
        with self.assertRaises(FileExistsError):
            owner.stop_app_for_restart(app, timeout=3)
        self.assertEqual(archive.read_text(), "retained evidence")
        self.assertTrue(Path(self.case.workspace.context_path).exists())
        self.assertTrue((owner.path/"wallet.db").exists())
        owner.retain()

    def test_restart_rejects_another_owned_child_without_signalling_it(self):
        owner = self.prepare()
        app = self.app(owner)
        sibling = self.case.start_process([sys.executable,"-c","import time;time.sleep(30)"], env=os.environ)
        with self.assertRaisesRegex(STORAGE.MacCaseStorageError, "last original native app"):
            owner.stop_app_for_restart(sibling, timeout=3)
        self.assertIsNone(sibling.process.poll())
        self.assertTrue(app.cleanup_completed)
        owner.retain()

    def test_restart_context_with_another_pid_is_not_archived_or_removed(self):
        owner = self.prepare()
        app = self.app(owner)
        context = Path(self.case.workspace.context_path)
        value = json.loads(context.read_text())
        value["pid"] += 1
        context.write_text(json.dumps(value))
        with self.assertRaisesRegex(STORAGE.MacCaseStorageError, "owned app/support"):
            owner.stop_app_for_restart(app, timeout=3)
        self.assertTrue(context.exists())
        self.assertFalse(context.with_name("native-context-before-restart.json").exists())
        owner.retain()

    def test_real_owned_app_context_then_native_cleanup_then_only_support_removed(self):
        owner = self.prepare()
        self.app(owner)
        self.assertEqual((owner.path / "wallet.db").read_text(), "synthetic-wallet-state")
        observed = self.close(owner)
        self.assertEqual(observed.namespace, owner.case.workspace.namespace)
        self.assertFalse(owner.path.exists())
        self.assertTrue(owner.case.workspace.root.exists())
        self.assertTrue(Path(owner.case.workspace.context_path).exists())
        self.assertEqual(len(list(owner.case.workspace.root.glob("process-*.log"))), 4)
        context = json.loads(Path(owner.case.workspace.context_path).read_text())
        self.assertIs(context["storage_cleanup_completed"], False)
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.close(owner)

    def test_fresh_empty_case_can_close_without_fabricating_app_context(self):
        owner = self.prepare()
        self.close(owner)
        self.assertFalse(owner.path.exists())
        self.assertFalse(Path(self.case.workspace.context_path).exists())

    def test_failed_scenario_retains_native_and_filesystem_state_and_stops_app(self):
        self.app_code = "time.sleep(30)"
        self.install_scripts()
        owner = self.prepare()
        writer = owner.start_app(env=os.environ)
        deadline = time.monotonic() + 3
        while "owned-app-ready" not in writer.log_path.read_text() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertIn("owned-app-ready", writer.log_path.read_text())
        self.assertEqual((owner.path / "wallet.db").read_text(), "synthetic-wallet-state")
        with patch.object(STORAGE.native, "clean_mac_case") as native_cleanup:
            owner.retain()
            native_cleanup.assert_not_called()
        self.assertTrue(writer.cleanup_completed)
        self.assertTrue(owner.path.exists())
        self.assertTrue((owner.path / STORAGE._MARKER).exists())
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.close(owner)

    def test_preexisting_case_is_never_adopted_or_removed(self):
        self.path().mkdir(parents=True)
        sentinel = self.path() / "existing-wallet"
        sentinel.write_text("preserve")
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.prepare()
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertFalse((self.path() / STORAGE._MARKER).exists())

    def test_duplicate_owner_and_late_allocation_are_refused(self):
        owner = self.prepare()
        with self.assertRaisesRegex(STORAGE.MacCaseStorageError, "fresh"):
            self.prepare()
        owner.retain()

    def test_probe_failure_scope_extra_fields_and_path_overrides_do_not_allocate(self):
        for field, value in (
            ("completed", False), ("schema_version", True), ("mode", "delete"),
            ("namespace", "other"), ("expected_team", "other"),
            ("support_directory", str(self.host.root)), ("error_code", None),
        ):
            with self.subTest(field=field):
                case = self.host.make_case(index=30 + len(self.host.cases))
                self.probe_updates = {field: value}
                self.install_scripts()
                with self.assertRaises(STORAGE.MacCaseStorageError):
                    self.prepare(case=case)
                self.assertFalse(self.path(case=case).exists())

    def test_nested_support_removed_but_sibling_and_ordinary_state_survive(self):
        owner = self.prepare()
        nested = owner.path / "wallet/tor/cache"
        nested.mkdir(parents=True)
        (nested / "owned.dat").write_text("owned")
        sibling = owner.path.with_name(owner.path.name + "0")
        sibling.mkdir()
        (sibling / "wallet.db").write_text("sibling")
        ordinary = self.sdk_base / "com.keplr.vizor/wallet.db"
        ordinary.write_text("ordinary")
        self.close(owner)
        self.assertFalse(owner.path.exists())
        self.assertEqual((sibling / "wallet.db").read_text(), "sibling")
        self.assertEqual(ordinary.read_text(), "ordinary")

    def test_symlink_hardlink_and_nonregular_children_are_refused_before_native_cleanup(self):
        for kind in ("symlink", "hardlink", "fifo"):
            with self.subTest(kind=kind):
                case = self.host.make_case(index=50 + len(self.host.cases))
                owner = self.prepare(case=case)
                sentinel = self.host.root / (kind + "-untouched")
                sentinel.write_text("preserve")
                target = owner.path / "unsafe"
                if kind == "symlink":
                    target.symlink_to(sentinel)
                elif kind == "hardlink":
                    os.link(sentinel, target)
                else:
                    os.mkfifo(target)
                with patch.object(STORAGE.native, "clean_mac_case") as cleanup:
                    with self.assertRaises(STORAGE.MacCaseStorageError):
                        self.close(owner)
                    cleanup.assert_not_called()
                self.assertEqual(sentinel.read_text(), "preserve")
                self.assertTrue(owner.path.exists())
                self.assertTrue(target.exists())

    def test_replaced_support_directory_does_not_authorize_either_tree(self):
        owner = self.prepare()
        original = owner.path.with_name(owner.path.name + "-original")
        owner.path.rename(original)
        owner.path.mkdir(mode=0o700)
        sentinel = owner.path / "user-state"
        sentinel.write_text("preserve")
        with patch.object(STORAGE.native, "clean_mac_case") as cleanup:
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
            cleanup.assert_not_called()
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertTrue((original / STORAGE._MARKER).exists())

    def test_changed_marker_is_sticky_even_after_bytes_are_restored(self):
        owner = self.prepare()
        marker = owner.path / STORAGE._MARKER
        original = marker.read_bytes()
        marker.write_bytes(b"{}")
        with self.assertRaises(STORAGE.MacCaseStorageError):
            owner.verify_owned()
        marker.write_bytes(original)
        with patch.object(STORAGE.native, "clean_mac_case") as cleanup:
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
            cleanup.assert_not_called()
        self.assertTrue(owner.path.exists())

    def test_wrong_app_context_cannot_authorize_native_or_support_removal(self):
        for update in (
            {"pid": 1}, {"pid": True}, {"namespace": "other"},
            {"support_directory": str(self.host.root)}, {"secure_store_services": []},
            {"preferences_prefix": "flutter."}, {"storage_cleanup_completed": True},
            {"os_background_scheduling_enabled": True}, {"schema_version": True},
        ):
            with self.subTest(update=update):
                case = self.host.make_case(index=70 + len(self.host.cases))
                self.context_updates = update
                self.install_scripts()
                owner = self.prepare(case=case)
                writer = self.app(owner)
                with patch.object(STORAGE.native, "clean_mac_case") as cleanup:
                    with self.assertRaises(STORAGE.MacCaseStorageError):
                        self.close(owner)
                    cleanup.assert_not_called()
                self.assertTrue(writer.cleanup_completed)
                self.assertEqual((owner.path / "wallet.db").read_text(), "synthetic-wallet-state")

    def test_untracked_context_or_missing_owned_app_context_retains_state(self):
        owner = self.prepare()
        Path(self.case.workspace.context_path).write_text("{}")
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.close(owner)
        self.assertTrue(owner.path.exists())
        second = self.host.make_case(index=99)
        other = self.prepare(case=second)
        self.app(other)
        Path(second.workspace.context_path).unlink()
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.close(other)
        self.assertTrue(other.path.exists())

    def test_native_failure_does_not_remove_any_support_file(self):
        owner = self.prepare()
        self.app(owner)
        before = {entry.name: entry.read_bytes() for entry in owner.path.iterdir()}
        with patch.object(STORAGE.native, "clean_mac_case", side_effect=STORAGE.runtime.RunnerError("native absence unproven")):
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
        self.assertEqual(before, {entry.name: entry.read_bytes() for entry in owner.path.iterdir()})
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.close(owner)

    def test_mutation_during_native_cleanup_prevents_all_filesystem_removal(self):
        owner = self.prepare()
        self.app(owner)
        cleanup = STORAGE.native.clean_mac_case
        def mutate(*args, **kwargs):
            observed = cleanup(*args, **kwargs)
            (owner.path / "unexpected.db").write_text("retained")
            return observed
        with patch.object(STORAGE.native, "clean_mac_case", side_effect=mutate):
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
        self.assertTrue((owner.path / "wallet.db").exists())
        self.assertTrue((owner.path / STORAGE._MARKER).exists())
        self.assertEqual((owner.path / "unexpected.db").read_text(), "retained")

    def test_unproven_writer_teardown_never_reaches_native_or_filesystem_cleanup(self):
        owner = self.prepare()
        self.case._cleanup_failed(STORAGE.runtime.RunnerError("unproven process output"))
        with patch.object(STORAGE.native, "clean_mac_case") as cleanup:
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
            cleanup.assert_not_called()
        self.assertTrue((owner.path / STORAGE._MARKER).exists())

    def test_child_moved_after_open_is_not_mutated_through_the_stale_descriptor(self):
        owner = self.prepare()
        child = owner.path / "nested"
        child.mkdir()
        (child / "original.bin").write_text("preserve-original")
        moved = self.host.root / "moved-child"
        remove = STORAGE.owned_tree.remove_entries
        swapped = False
        def swap_on_recursion(fd, entries, verify):
            nonlocal swapped
            if not swapped and {item.name for item in entries} == {"original.bin"}:
                swapped = True
                child.rename(moved)
                child.mkdir()
                (child / "replacement.bin").write_text("preserve-replacement")
            return remove(fd, entries, verify)
        with patch.object(STORAGE.owned_tree, "remove_entries", side_effect=swap_on_recursion):
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
        self.assertTrue(swapped)
        self.assertEqual((moved / "original.bin").read_text(), "preserve-original")
        self.assertEqual((child / "replacement.bin").read_text(), "preserve-replacement")
        self.assertTrue((owner.path / STORAGE._MARKER).exists())

    def test_partial_remove_is_failed_and_remaining_marker_and_case_evidence_survive(self):
        owner = self.prepare()
        (owner.path / "a.bin").write_text("owned-first")
        (owner.path / "b.bin").write_text("owned-second")
        unlink = STORAGE.os.unlink
        def fail_second(name, **kwargs):
            if name == "b.bin":
                raise PermissionError("model removal failure")
            return unlink(name, **kwargs)
        with patch.object(STORAGE.os, "unlink", side_effect=fail_second):
            with self.assertRaises(STORAGE.MacCaseStorageError):
                self.close(owner)
        self.assertFalse((owner.path / "a.bin").exists())
        self.assertEqual((owner.path / "b.bin").read_text(), "owned-second")
        self.assertTrue((owner.path / STORAGE._MARKER).exists())
        self.assertTrue(owner.case.workspace.marker_path.exists())
        self.assertEqual(len(list(owner.case.workspace.root.glob("process-*.log"))), 3)
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.close(owner)

    def test_cancellation_or_interruption_retains_state_and_classification(self):
        owner = self.prepare()
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaises(STORAGE.runtime.Cancelled):
            owner.close(timeout=3, cancel_event=cancelled)
        self.assertTrue((owner.path / STORAGE._MARKER).exists())
        other = self.prepare(case=self.host.make_case(index=101))
        with patch.object(STORAGE.native, "clean_mac_case", side_effect=KeyboardInterrupt("model interrupt")):
            with self.assertRaises(KeyboardInterrupt):
                self.close(other)
        self.assertTrue((other.path / STORAGE._MARKER).exists())

    def test_native_preflight_cannot_adopt_or_delete_retained_state(self):
        self.verify_updates = {"completed": False, "error_code": "native_state_retained"}
        self.install_scripts()
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.prepare()
        self.assertTrue((self.path() / STORAGE._MARKER).exists())
        self.assertTrue(self.case.accepting_launches)
        logs = sorted(self.case.workspace.root.glob("process-*.log"))
        self.assertEqual(len(logs), 2)
        self.assertEqual(json.loads(logs[-1].read_text())["mode"], "verify")
        with self.assertRaises(STORAGE.MacCaseStorageError):
            self.prepare()

    def test_preflight_cancellation_and_timeout_keep_their_primary_classification(self):
        for index, primary in enumerate((STORAGE.runtime.Cancelled(), STORAGE.runtime.RunnerError("model timeout", 124))):
            with self.subTest(primary=type(primary).__name__):
                case = self.host.make_case(index=120 + index)
                run_command = case.run_command
                def fail_preflight(command, **kwargs):
                    if "--verify" in command:
                        raise primary
                    return run_command(command, **kwargs)
                with patch.object(case, "run_command", side_effect=fail_preflight):
                    with self.assertRaises(STORAGE.runtime.RunnerError) as raised:
                        self.prepare(case=case)
                self.assertEqual(raised.exception.exit_code, primary.exit_code)
                if isinstance(primary, STORAGE.runtime.Cancelled):
                    self.assertIsInstance(raised.exception, STORAGE.runtime.Cancelled)
                self.assertTrue((self.path(case=case) / STORAGE._MARKER).exists())


if __name__ == "__main__":
    unittest.main()
