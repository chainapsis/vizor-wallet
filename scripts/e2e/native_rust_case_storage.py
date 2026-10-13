"""Private Rust wallet tempdirs; remove only after their original writers join."""
from __future__ import annotations

import contextlib
import os

import e2e_runtime as runtime
import native_owned_tree as tree


class RustCaseStorage:
    def __init__(self, case):
        self.case = case
        self.path = case.workspace.root / "wallet-temp"
        self._finished = False
        case.workspace.verify_owned()
        if not case.accepting_launches or case.launched_process_count:
            raise runtime.RunnerError("Rust storage requires a fresh original case")
        self.path.mkdir(mode=0o700)
        self._identity = tree.identity(self.path.stat())
        self.verify_owned()

    def verify_owned(self):
        self.case.workspace.verify_owned()
        if self.path != self.case.workspace.root / "wallet-temp":
            raise runtime.RunnerError("Rust wallet storage attachment changed")
        with contextlib.ExitStack() as stack:
            parent = tree.open_directory(stack, self.case.workspace.root, private=True)
            wallet = tree.open_directory(stack, "wallet-temp", dir_fd=parent, private=True)
            if tree.identity(os.fstat(wallet)) != self._identity:
                raise runtime.RunnerError("original Rust wallet storage directory changed")

    def close(self, *, timeout=60.0, cancel_event=None):
        if self._finished:
            raise runtime.RunnerError("Rust wallet storage already finalized or retained")
        self._finished = True
        # No exit-code, JSON receipt or caller boolean authorizes this removal.
        self.case.close(timeout=timeout)
        self.verify_owned()
        with contextlib.ExitStack() as stack:
            parent = tree.open_directory(stack, self.case.workspace.root, private=True)
            wallet = tree.open_directory(stack, "wallet-temp", dir_fd=parent, private=True)
            if tree.identity(os.fstat(wallet)) != self._identity:
                raise runtime.RunnerError("original Rust wallet storage changed before removal")
            tree.remove_entries(wallet, tree.scan(wallet, allow_links=True), self.verify_owned)
            self.verify_owned()
            os.rmdir("wallet-temp", dir_fd=parent)
            try:
                os.stat("wallet-temp", dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                return {"wallet_storage_absent": True, "namespace": self.case.workspace.namespace}
            raise runtime.RunnerError("Rust wallet storage absence is unproven")

    def retain(self):
        self._finished = True
        self.case.close()
