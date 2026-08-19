#!/usr/bin/env python3

import sys
import tomllib
from pathlib import Path


DEPENDENCY_SECTIONS = ("dependencies", "dev-dependencies", "build-dependencies")


def git_dependency_sources(manifest: dict) -> list[str]:
    violations = []

    def inspect(table: dict, section: str) -> None:
        for name, dependency in table.items():
            if isinstance(dependency, dict) and "git" in dependency:
                violations.append(f"{section}.{name}")

    for section in DEPENDENCY_SECTIONS:
        inspect(manifest.get(section, {}), section)

    inspect(manifest.get("workspace", {}).get("dependencies", {}), "workspace.dependencies")

    for target, target_manifest in manifest.get("target", {}).items():
        for section in DEPENDENCY_SECTIONS:
            inspect(target_manifest.get(section, {}), f"target.{target}.{section}")

    for source, patched_dependencies in manifest.get("patch", {}).items():
        inspect(patched_dependencies, f"patch.{source}")

    return violations


def main() -> int:
    violations = []

    for path in sorted(Path.cwd().rglob("Cargo.toml")):
        if ".git" in path.parts or "target" in path.parts:
            continue

        manifest = tomllib.loads(path.read_text(encoding="utf-8"))
        violations.extend(
            f"{path}: {dependency}" for dependency in git_dependency_sources(manifest)
        )

    if violations:
        print("Git dependency sources must be removed before merge.", file=sys.stderr)
        print(
            "Publish the required crates and use registry version requirements.",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
