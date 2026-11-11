"""Lane runner: how scenarios are split and how each lane is started."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_lanes as LANES
import zakura_sequential as SEQUENTIAL


def ids(scenarios):
    return [scenario.id for scenario in scenarios]


class PlanTests(unittest.TestCase):
    def test_every_scenario_lands_in_exactly_one_lane_in_catalog_order(self):
        lanes = LANES.plan_lanes(SEQUENTIAL.ALL_SCENARIOS)
        self.assertEqual(list(lanes), [LANES.FIXED, LANES.MACOS, LANES.IOS])
        planned = [s for selected in lanes.values() for s in selected]
        self.assertCountEqual(ids(planned), ids(SEQUENTIAL.ALL_SCENARIOS))
        for selected in lanes.values():
            order = [SEQUENTIAL.ALL_SCENARIOS.index(s) for s in selected]
            self.assertEqual(order, sorted(order))

    def test_default_port_scenarios_stay_in_the_fixed_lane(self):
        lanes = LANES.plan_lanes(SEQUENTIAL.ALL_SCENARIOS)
        fixed = ids(lanes[LANES.FIXED])
        for scenario in ("flutter.macos.fallback-endpoint", "flutter.macos.voting", "flutter.ios.voting",
                         "flutter.ios.screenshot-tour", "flutter.macos.payment-link-batch-restart"):
            self.assertIn(scenario, fixed)
        self.assertTrue(all(s.platform == "macos" for s in lanes[LANES.MACOS]))
        self.assertIn("flutter.macos.import-sync", ids(lanes[LANES.MACOS]))
        self.assertIn("rust.send.basic", ids(lanes[LANES.IOS]))
        self.assertIn("flutter.ios.import-sync", ids(lanes[LANES.IOS]))
        self.assertFalse(any(getattr(s, "platform", None) == "macos" for s in lanes[LANES.IOS]))

    def test_single_macos_keeps_one_macos_app_and_empty_lanes_are_omitted(self):
        lanes = LANES.plan_lanes(SEQUENTIAL.select_scenarios(["flutter.macos"]), second_macos=False)
        self.assertEqual(list(lanes), [LANES.FIXED])
        self.assertEqual(list(LANES.plan_lanes(SEQUENTIAL.select_scenarios(["rust"]))), [LANES.IOS])


class CommandTests(unittest.TestCase):
    def test_only_lanes_beside_the_fixed_one_lease_ports(self):
        selected = SEQUENTIAL.select_scenarios(["flutter.macos.import-sync"])
        options = dict(flutter=Path("/sdk/flutter"), grpcurl=Path("/bin/grpcurl"), proto_dir=None, build_jobs=2,
            keep_failed=True, ios_runtime="runtime", dart_defines=(("NAME", "value"),))
        leased = LANES.lane_command(Path("/checkout"), selected, leased=True, **options)
        self.assertEqual(leased[1:3], ["/checkout/scripts/e2e/zakura-run.py", "flutter.macos.import-sync"])
        self.assertIn("--lease-ports", leased)
        self.assertEqual(leased[-2:], ["--dart-define", "NAME=value"])
        self.assertIn("--keep-failed", leased)
        self.assertEqual(leased[leased.index("--ios-runtime") + 1], "runtime")
        self.assertNotIn("--proto-dir", leased)
        fixed = LANES.lane_command(Path("/root"), selected, leased=False, **{**options, "proto_dir": Path("/protos")})
        self.assertNotIn("--lease-ports", fixed)
        self.assertEqual(fixed[fixed.index("--proto-dir") + 1], "/protos")


if __name__ == "__main__":
    unittest.main()
