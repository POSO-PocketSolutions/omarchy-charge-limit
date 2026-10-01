import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class StatusScriptTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.bat = base / "BAT0"
        self.bat.mkdir()
        (self.bat / "charge_control_start_threshold").write_text("75\n")
        (self.bat / "charge_control_end_threshold").write_text("80\n")
        (self.bat / "capacity").write_text("55\n")
        (self.bat / "status").write_text("Charging\n")
        self.config = base / "charge-limit.conf"
        self.config.write_text("START=75\nEND=80\nENABLED=1\n")

    def tearDown(self):
        self.tmp.cleanup()

    def run_status(self):
        env = {
            **os.environ,
            "CHARGE_LIMIT_BAT_PATH": str(self.bat),
            "CHARGE_LIMIT_CONFIG": str(self.config),
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts" / "status")],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_limited_mode(self):
        data = self.run_status()
        self.assertTrue(data["supported"])
        self.assertEqual(data["mode"], "limited")
        self.assertEqual(data["savedEnd"], "80")
        self.assertTrue(data["enabled"])

    def test_full_mode(self):
        (self.bat / "charge_control_start_threshold").write_text("0\n")
        (self.bat / "charge_control_end_threshold").write_text("100\n")
        data = self.run_status()
        self.assertEqual(data["mode"], "full")


class HistoryScriptTest(unittest.TestCase):
    def _run_with_fake_busctl(self, body):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        bindir = Path(tmp.name) / "bin"
        bindir.mkdir()
        fake = bindir / "busctl"
        fake.write_text(body)
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        env = {**os.environ, "PATH": f"{bindir}:/usr/bin:/bin"}
        return subprocess.run(
            ["bash", str(ROOT / "scripts" / "history")],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_normalizes_and_orders_samples(self):
        body = (
            "#!/bin/bash\n"
            "printf '%s\\n' "
            "'{\"type\":\"a(udu)\",\"data\":[[[300,80,2],[100,60,1],"
            "[200,70,4],[400,90,5]]]}'\n"
        )
        result = self._run_with_fake_busctl(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data["available"])
        self.assertEqual(data["hours"], 24)
        self.assertEqual([p["timestamp"] for p in data["points"]], [100, 200, 300, 400])
        self.assertEqual([p["level"] for p in data["points"]], [60, 70, 80, 90])
        self.assertEqual(
            [p["state"] for p in data["points"]],
            ["charging", "full", "discharging", "pending-charge"],
        )

    def test_returns_valid_json_when_unavailable(self):
        result = self._run_with_fake_busctl("#!/bin/bash\nexit 1\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertFalse(data["available"])
        self.assertEqual(data["points"], [])
        self.assertTrue(len(data["error"]) > 0)


if __name__ == "__main__":
    unittest.main()
