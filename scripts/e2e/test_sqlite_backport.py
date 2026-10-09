"""Offline package/provenance checks; the real wallet scenarios test behavior."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "rust/vendor/zakura-client-sqlite"


class SqliteBackportTests(unittest.TestCase):
    def test_only_recorded_upstream_source_and_packaging_differ_from_rc7(self):
        metadata = json.loads((PACKAGE / "PATCHES.json").read_text())
        self.assertEqual(metadata["backported_commit"], "e1cf20a25b3b43dd49463a804a82a5d6248b16bb")
        self.assertEqual(metadata["registry_archive_sha256"], "e70bc4e3cf36b8b933af0926369b2b9b27cb3fc67eda14ac6f091df524885f47")
        self.assertEqual(metadata["modified_package_files"], ["src/wallet.rs"])
        expected = {**metadata["published_file_sha256"], **metadata["patched_file_sha256"],
                    **metadata["normalized_metadata_sha256"], **metadata["license_file_sha256"]}
        actual = {path.relative_to(PACKAGE).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in PACKAGE.rglob("*") if path.is_file() and path.name != "PATCHES.json"}
        self.assertEqual(actual, expected)
        self.assertNotEqual(expected["src/wallet.rs"], metadata["published_file_sha256"]["src/wallet.rs"])
        self.assertTrue(metadata["removal_condition"])

    def test_one_rc7_package_override_without_a_dependency_family_upgrade(self):
        manifest = (ROOT / "rust/Cargo.toml").read_text()
        self.assertIn('zakura-client-sqlite = { path = "vendor/zakura-client-sqlite" }', manifest)
        entries = (ROOT / "rust/Cargo.lock").read_text().split("[[package]]")
        sqlite = [entry for entry in entries if '\nname = "zakura-client-sqlite"\n' in entry]
        self.assertEqual(len(sqlite), 1)
        self.assertIn('version = "0.1.0-rc7"', sqlite[0])
        self.assertNotIn("source =", sqlite[0])
        self.assertNotIn("checksum =", sqlite[0])
        wallet = (PACKAGE / "src/wallet.rs").read_text()
        self.assertIn("window_floor.unwrap_or(truncation_target)", wallet)
        self.assertIn("fn rewind_to_chain_state_above_every_checkpoint_leaves_trees_untouched()", wallet)


if __name__ == "__main__":
    unittest.main()
