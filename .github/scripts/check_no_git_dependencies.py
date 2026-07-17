#!/usr/bin/env python3

import sys
import tomllib
from pathlib import Path


DEPENDENCY_SECTIONS = ("dependencies", "dev-dependencies", "build-dependencies")


def git_dependencies(manifest: dict) -> list[str]:
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

    return violations


def main() -> int:
    violations = []

    for path in sorted(Path.cwd().rglob("Cargo.toml")):
        if ".git" in path.parts or "target" in path.parts:
            continue

        manifest = tomllib.loads(path.read_text(encoding="utf-8"))
        violations.extend(f"{path}: {dependency}" for dependency in git_dependencies(manifest))

    if violations:
        print("Inline git dependencies are not allowed.", file=sys.stderr)
        print(
            "Use a version requirement and put source overrides in the root "
            "[patch.crates-io] table.",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
