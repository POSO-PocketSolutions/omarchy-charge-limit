import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
CLI = ROOT / "system" / "charge-limit"


class ChargeLimitCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.bat = base / "BAT0"
        self.bat.mkdir()
        (self.bat / "charge_control_start_threshold").write_text("0\n")
        (self.bat / "charge_control_end_threshold").write_text("100\n")
        (self.bat / "capacity").write_text("55\n")
        (self.bat / "status").write_text("Charging\n")
        self.config = base / "charge-limit.conf"
        self.env = {
            **os.environ,
            "CHARGE_LIMIT_BAT_PATH": str(self.bat),
            "CHARGE_LIMIT_CONFIG": str(self.config),
        }

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        return subprocess.run(
            ["bash", str(CLI), *args],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def start(self):
        return (self.bat / "charge_control_start_threshold").read_text().strip()

    def end(self):
        return (self.bat / "charge_control_end_threshold").read_text().strip()

    def config_values(self):
        values = {}
        for line in self.config.read_text().splitlines():
            key, _, value = line.partition("=")
            values[key] = value
        return values

    def test_set_applies_and_persists(self):
        result = self.run_cli("set", "75", "80")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.start(), "75")
        self.assertEqual(self.end(), "80")
        self.assertEqual(
            self.config_values(), {"START": "75", "END": "80", "ENABLED": "1"}
        )

    def test_set_rejects_end_not_greater_than_start(self):
        result = self.run_cli("set", "80", "80")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.end(), "100")

    def test_set_rejects_out_of_range(self):
        self.assertNotEqual(self.run_cli("set", "10", "120").returncode, 0)
        self.assertNotEqual(self.run_cli("set", "-5", "80").returncode, 0)

    def test_full_charges_to_100_without_touching_saved_limit(self):
        self.run_cli("set", "75", "80")
        result = self.run_cli("full")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.end(), "100")
        self.assertEqual(self.config_values()["END"], "80")

    def test_toggle_switches_both_ways(self):
        self.run_cli("set", "75", "80")
        self.run_cli("toggle")
        self.assertEqual(self.end(), "100")
        self.run_cli("toggle")
        self.assertEqual(self.end(), "80")

    def test_off_disables_autoapply_but_keeps_saved_values(self):
        self.run_cli("set", "75", "80")
        self.run_cli("off")
        self.assertEqual(self.end(), "100")
        values = self.config_values()
        self.assertEqual(values["ENABLED"], "0")
        self.assertEqual(values["START"], "75")
        self.assertEqual(values["END"], "80")

    def test_boot_respects_disabled_flag(self):
        self.run_cli("set", "75", "80")
        self.run_cli("off")
        (self.bat / "charge_control_end_threshold").write_text("100\n")
        result = self.run_cli("boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.end(), "100")

    def test_boot_reapplies_when_enabled(self):
        self.run_cli("set", "75", "80")
        (self.bat / "charge_control_end_threshold").write_text("100\n")
        (self.bat / "charge_control_start_threshold").write_text("0\n")
        result = self.run_cli("boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.end(), "80")
        self.assertEqual(self.start(), "75")


if __name__ == "__main__":
    unittest.main()
