#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
MODULE_PATH = SCRIPT_DIR / "e2e_changes.py"
SPEC = importlib.util.spec_from_file_location("e2e_changes", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
CHANGES = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHANGES
SPEC.loader.exec_module(CHANGES)


class GitRepository:
    def __init__(self, test: unittest.TestCase) -> None:
        directory = tempfile.TemporaryDirectory()
        test.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "-q")
        self.git("config", "user.email", "e2e@example.invalid")
        self.git("config", "user.name", "E2E Test")

    def git(self, *arguments: str) -> str:
        completed = subprocess.run(
            ["git", *arguments],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        return completed.stdout.strip()

    def write(self, name: str, content: str) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def commit_all(self, message: str) -> str:
        self.git("add", "-A", "--")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")


class E2eChangesTests(unittest.TestCase):
    def test_collects_committed_staged_unstaged_and_nonignored_untracked(self) -> None:
        repo = GitRepository(self)
        repo.write("tracked.txt", "base\n")
        repo.write(".gitignore", "ignored/\n")
        base = repo.commit_all("base")

        repo.write("committed.txt", "committed\n")
        repo.commit_all("head")
        repo.write("staged.txt", "staged\n")
        repo.git("add", "--", "staged.txt")
        repo.write("tracked.txt", "unstaged\n")
        unusual = "space tab\tline\n-leading.txt"
        repo.write(unusual, "untracked\n")
        repo.write("-leading.txt", "untracked\n")
        repo.write("ignored/build.out", "ignored\n")

        changed = CHANGES.collect_changed_files(repo.root, base)

        self.assertEqual(
            set(changed.paths),
            {"committed.txt", "staged.txt", "tracked.txt", unusual, "-leading.txt"},
        )
        self.assertNotIn("ignored/build.out", changed.paths)
        self.assertEqual(changed.git["base_ref"], base)
        self.assertEqual(changed.git["base_commit"], base)
        self.assertTrue(changed.git["include_worktree"])

    def test_rename_reports_old_and_new_and_deletion_is_retained(self) -> None:
        repo = GitRepository(self)
        repo.write("old name.txt", "rename\n")
        repo.write("deleted.txt", "delete\n")
        base = repo.commit_all("base")
        repo.git("mv", "--", "old name.txt", "new name.txt")
        repo.git("rm", "-q", "--", "deleted.txt")
        repo.commit_all("rename and delete")

        changed = CHANGES.collect_changed_files(repo.root, base)

        self.assertEqual(
            set(changed.paths),
            {"old name.txt", "new name.txt", "deleted.txt"},
        )

    def test_uncommitted_renames_and_deletions_keep_every_affected_path(self) -> None:
        repo = GitRepository(self)
        for name in (
            "staged-old.txt",
            "unstaged-old.txt",
            "staged-delete.txt",
            "unstaged-delete.txt",
        ):
            repo.write(name, "base\n")
        base = repo.commit_all("base")

        repo.git("mv", "--", "staged-old.txt", "staged-new.txt")
        repo.git("rm", "-q", "--", "staged-delete.txt")
        (repo.root / "unstaged-old.txt").rename(repo.root / "unstaged-new.txt")
        (repo.root / "unstaged-delete.txt").unlink()

        changed = CHANGES.collect_changed_files(repo.root, base)

        self.assertEqual(
            {
                "staged-old.txt",
                "staged-new.txt",
                "unstaged-old.txt",
                "unstaged-new.txt",
                "staged-delete.txt",
                "unstaged-delete.txt",
            },
            set(changed.paths),
        )

    def test_diverged_ref_uses_merge_base_and_excludes_ref_only_change(self) -> None:
        repo = GitRepository(self)
        repo.write("base.txt", "base\n")
        repo.commit_all("base")
        main_branch = repo.git("branch", "--show-current")
        repo.git("checkout", "-q", "-b", "comparison")
        repo.write("comparison-only.txt", "comparison\n")
        repo.commit_all("comparison")
        repo.git("checkout", "-q", main_branch)
        repo.write("head-only.txt", "head\n")
        repo.commit_all("head")

        changed = CHANGES.collect_changed_files(repo.root, "comparison")

        self.assertIn("head-only.txt", changed.paths)
        self.assertNotIn("comparison-only.txt", changed.paths)

    def test_invalid_option_like_tree_and_blob_refs_are_rejected(self) -> None:
        repo = GitRepository(self)
        repo.write("file.txt", "content\n")
        repo.commit_all("base")
        blob = repo.git("rev-parse", "HEAD:file.txt")
        for revision in ("--help", "HEAD^{tree}", blob):
            with self.subTest(revision=revision), self.assertRaises(CHANGES.CatalogError):
                CHANGES.collect_changed_files(repo.root, revision)

    def test_unrelated_history_is_rejected(self) -> None:
        repo = GitRepository(self)
        repo.write("main.txt", "main\n")
        repo.commit_all("main")
        main_branch = repo.git("branch", "--show-current")
        repo.git("checkout", "-q", "--orphan", "unrelated")
        (repo.root / "main.txt").unlink()
        repo.write("other.txt", "other\n")
        repo.commit_all("other")
        repo.git("checkout", "-q", main_branch)

        with self.assertRaisesRegex(CHANGES.CatalogError, "merge-base"):
            CHANGES.collect_changed_files(repo.root, "unrelated")

    def test_malformed_nul_and_invalid_utf8_are_rejected(self) -> None:
        for output in (b"missing terminator", b"one\0\0", b"bad-\xff\0"):
            with self.subTest(output=output), self.assertRaises(CHANGES.CatalogError):
                CHANGES._decode_nul_paths(output, "test git")

    def test_multiple_merge_bases_are_unioned_and_paths_keep_first_order(self) -> None:
        oid = lambda digit: digit * 40
        base, head, first, second = oid("1"), oid("2"), oid("3"), oid("4")
        head_resolutions = iter((head, head))

        def fake_run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[bytes]:
            self.assertEqual(command[0], "git")
            self.assertEqual(kwargs["shell"] if "shell" in kwargs else False, False)
            self.assertEqual(kwargs["env"]["GIT_OPTIONAL_LOCKS"], "0")  # type: ignore[index]
            arguments = command[1:]
            if arguments[:3] == ["rev-parse", "--verify", "--end-of-options"]:
                value = base if arguments[3].startswith("topic") else next(head_resolutions)
                return subprocess.CompletedProcess(command, 0, f"{value}\n".encode(), b"")
            if arguments[0] == "merge-base":
                return subprocess.CompletedProcess(
                    command, 0, f"{first}\n{second}\n".encode(), b""
                )
            if arguments[0] == "ls-files":
                return subprocess.CompletedProcess(command, 0, b"untracked\0", b"")
            if "--cached" in arguments:
                output = b"staged\0"
            elif first in arguments:
                output = b"first\0duplicate\0"
            elif second in arguments:
                output = b"second\0duplicate\0"
            else:
                output = b"unstaged\0"
            return subprocess.CompletedProcess(command, 0, output, b"")

        with mock.patch.object(CHANGES.subprocess, "run", side_effect=fake_run):
            changed = CHANGES.collect_changed_files(Path("/repo"), "topic")

        self.assertEqual(
            changed.paths,
            ("first", "duplicate", "second", "staged", "unstaged", "untracked"),
        )
        self.assertEqual(changed.git["merge_bases"], [first, second])

    def test_head_change_during_collection_is_rejected(self) -> None:
        oid = lambda digit: digit * 40
        base, head, changed_head = oid("1"), oid("2"), oid("3")
        head_resolutions = iter((head, changed_head))

        def fake_run(command: list[str], **_: object) -> subprocess.CompletedProcess[bytes]:
            arguments = command[1:]
            if arguments[0] == "rev-parse":
                value = base if arguments[3].startswith("topic") else next(head_resolutions)
                return subprocess.CompletedProcess(command, 0, f"{value}\n".encode(), b"")
            if arguments[0] == "merge-base":
                return subprocess.CompletedProcess(command, 0, f"{base}\n".encode(), b"")
            return subprocess.CompletedProcess(command, 0, b"", b"")

        with (
            mock.patch.object(CHANGES.subprocess, "run", side_effect=fake_run),
            self.assertRaisesRegex(CHANGES.CatalogError, "HEAD changed"),
        ):
            CHANGES.collect_changed_files(Path("/repo"), "topic")

    def test_worktree_path_change_during_collection_is_rejected(self) -> None:
        oid = lambda digit: digit * 40
        base, head = oid("1"), oid("2")
        statuses = iter((b" M stable.txt\0", b" M stable.txt\0?? new.txt\0"))

        def fake_run(command: list[str], **_: object) -> subprocess.CompletedProcess[bytes]:
            arguments = command[1:]
            if arguments[0] == "rev-parse":
                value = base if arguments[3].startswith("topic") else head
                return subprocess.CompletedProcess(command, 0, f"{value}\n".encode(), b"")
            if arguments[0] == "status":
                return subprocess.CompletedProcess(command, 0, next(statuses), b"")
            if arguments[0] == "merge-base":
                return subprocess.CompletedProcess(command, 0, f"{base}\n".encode(), b"")
            return subprocess.CompletedProcess(command, 0, b"", b"")

        with (
            mock.patch.object(CHANGES.subprocess, "run", side_effect=fake_run),
            self.assertRaisesRegex(CHANGES.CatalogError, "worktree paths changed"),
        ):
            CHANGES.collect_changed_files(Path("/repo"), "topic")

    def test_empty_base_ref_is_rejected_without_git(self) -> None:
        with (
            mock.patch.object(CHANGES.subprocess, "run") as run,
            self.assertRaises(ValueError),
        ):
            CHANGES.collect_changed_files(Path("/repo"), "")
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
