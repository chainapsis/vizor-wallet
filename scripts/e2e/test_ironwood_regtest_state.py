#!/usr/bin/env python3
"""Validate reset semantics without Docker or touching the real regtest state."""
import subprocess
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "ironwood-regtest" / "lib.sh"


def clear(state: Path):
    subprocess.run(
        ["bash", "-c", 'source "$1"; STATE_DIR="$2"; clear_ironwood_state',
         "ironwood-state-test", str(LIB), str(state)], check=True,
    )


class ResetTest(unittest.TestCase):
    def test_repeated_reset_preserves_bind_mount_inodes_and_clears_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            mounts = [state / "zcashd", state / "lightwalletd"]
            for mount in mounts:
                mount.mkdir()
            original_inodes = [path.stat().st_ino for path in [state, *mounts]]
            for _ in range(2):
                for mount in mounts:
                    (mount / "nested").mkdir()
                    (mount / "nested" / "chain-data").write_text("stale")
                (state / "activation-height").write_text("150")
                (state / "gift-funder.db").write_text("stale")
                clear(state)
                self.assertEqual(
                    [path.stat().st_ino for path in [state, *mounts]], original_inodes,
                )
                self.assertEqual({path.name for path in state.iterdir()}, {"zcashd", "lightwalletd"})
                self.assertTrue(all(not list(path.iterdir()) for path in mounts))

    def test_mount_symlink_is_replaced_without_deleting_its_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            state = parent / "state"
            state.mkdir()
            outside = parent / "outside"
            outside.mkdir()
            retained = outside / "retained"
            retained.write_text("retained")
            (state / "zcashd").symlink_to(outside, target_is_directory=True)
            clear(state)
            self.assertEqual(retained.read_text(), "retained")
            self.assertFalse((state / "zcashd").is_symlink())
            self.assertTrue((state / "zcashd").is_dir())


if __name__ == "__main__":
    unittest.main()
