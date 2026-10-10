"""Read-only Git change discovery for catalogued E2E selection."""

from __future__ import annotations

import dataclasses
import os
from pathlib import Path
import re
import subprocess
from typing import Sequence

from e2e_catalog import CatalogError


_GIT_TIMEOUT_SECONDS = 30
_OID_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")


@dataclasses.dataclass(frozen=True)
class ChangedFiles:
    paths: tuple[str, ...]
    git: dict[str, object]


def _run_git(root: Path, arguments: Sequence[str]) -> bytes:
    env = os.environ.copy()
    env["GIT_OPTIONAL_LOCKS"] = "0"
    try:
        completed = subprocess.run(
            ["git", *arguments],
            cwd=root,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=_GIT_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise CatalogError(
            f"git {' '.join(arguments[:2])} timed out while collecting changed files"
        ) from error
    except OSError as error:
        raise CatalogError(f"could not run git while collecting changed files: {error}") from error
    if completed.returncode != 0:
        try:
            detail = completed.stderr.decode("utf-8", errors="strict").strip()
        except UnicodeDecodeError:
            detail = "git returned non-UTF-8 error output"
        suffix = f": {detail}" if detail else ""
        raise CatalogError(
            f"git {' '.join(arguments[:2])} failed with exit {completed.returncode}{suffix}"
        )
    return completed.stdout


def _decode_oid(output: bytes, location: str) -> str:
    try:
        text = output.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        raise CatalogError(f"{location} returned a non-ASCII object ID") from error
    if not text.endswith("\n") or text.count("\n") != 1:
        raise CatalogError(f"{location} returned malformed object ID output")
    oid = text[:-1]
    if _OID_RE.fullmatch(oid) is None:
        raise CatalogError(f"{location} returned an invalid commit object ID")
    return oid


def _decode_oids(output: bytes, location: str) -> tuple[str, ...]:
    try:
        text = output.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        raise CatalogError(f"{location} returned non-ASCII object IDs") from error
    if not text or not text.endswith("\n"):
        raise CatalogError(f"{location} returned no merge base")
    values = text[:-1].split("\n")
    if any(_OID_RE.fullmatch(value) is None for value in values):
        raise CatalogError(f"{location} returned malformed object ID output")
    return tuple(dict.fromkeys(values))


def _decode_nul_paths(output: bytes, location: str) -> tuple[str, ...]:
    if not output:
        return ()
    if not output.endswith(b"\0"):
        raise CatalogError(f"{location} returned malformed NUL-delimited paths")
    encoded_paths = output[:-1].split(b"\0")
    if any(not path for path in encoded_paths):
        raise CatalogError(f"{location} returned an empty changed path")
    try:
        return tuple(path.decode("utf-8", errors="strict") for path in encoded_paths)
    except UnicodeDecodeError as error:
        raise CatalogError(f"{location} returned a non-UTF-8 changed path") from error


def _resolve_commit(root: Path, revision: str, location: str) -> str:
    return _decode_oid(
        _run_git(root, ["rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"]),
        location,
    )


def _worktree_status(root: Path) -> bytes:
    """Capture the changed path set so a multi-command read cannot silently drift."""

    return _run_git(
        root,
        [
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all",
            "--no-renames",
            "--ignore-submodules=none",
            "--",
        ],
    )


def collect_changed_files(root: Path, base_ref: str) -> ChangedFiles:
    """Collects committed and local changes relative to ``base_ref``."""

    if not isinstance(base_ref, str) or not base_ref:
        raise ValueError("base_ref must be a non-empty string")
    repository = Path(root)
    base_commit = _resolve_commit(repository, base_ref, "base reference")
    head_commit = _resolve_commit(repository, "HEAD", "HEAD")
    initial_status = _worktree_status(repository)
    merge_bases = _decode_oids(
        _run_git(repository, ["merge-base", "--all", base_commit, head_commit]),
        "git merge-base",
    )

    collected: list[str] = []
    for merge_base in merge_bases:
        collected.extend(
            _decode_nul_paths(
                _run_git(
                    repository,
                    [
                        "diff",
                        "--name-only",
                        "-z",
                        "--no-renames",
                        "--no-ext-diff",
                        "--no-textconv",
                        merge_base,
                        head_commit,
                        "--",
                    ],
                ),
                "committed git diff",
            )
        )
    collected.extend(
        _decode_nul_paths(
            _run_git(
                repository,
                [
                    "diff",
                    "--cached",
                    "--name-only",
                    "-z",
                    "--no-renames",
                    "--no-ext-diff",
                    "--no-textconv",
                    head_commit,
                    "--",
                ],
            ),
            "staged git diff",
        )
    )
    collected.extend(
        _decode_nul_paths(
            _run_git(
                repository,
                [
                    "diff",
                    "--name-only",
                    "-z",
                    "--no-renames",
                    "--no-ext-diff",
                    "--no-textconv",
                    "--",
                ],
            ),
            "unstaged git diff",
        )
    )
    collected.extend(
        _decode_nul_paths(
            _run_git(
                repository,
                ["ls-files", "--others", "--exclude-standard", "-z", "--"],
            ),
            "git ls-files",
        )
    )

    final_head = _resolve_commit(repository, "HEAD", "HEAD recheck")
    if final_head != head_commit:
        raise CatalogError("HEAD changed while collecting changed files")
    if _worktree_status(repository) != initial_status:
        raise CatalogError("worktree paths changed while collecting changed files")

    return ChangedFiles(
        paths=tuple(dict.fromkeys(collected)),
        git={
            "base_ref": base_ref,
            "base_commit": base_commit,
            "merge_bases": list(merge_bases),
            "head_commit": head_commit,
            "include_worktree": True,
        },
    )
