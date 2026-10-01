import json
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class PluginContractTest(unittest.TestCase):
    def test_plugin_files_exist(self):
        for rel in (
            "manifest.json",
            "BarWidget.qml",
            "Panel.qml",
            "scripts/status",
            "scripts/history",
            "scripts/action",
            "system/charge-limit",
            "system/charge-limit.service",
            "system/charge-limit.sudoers.in",
            "system/install.sh",
            "system/uninstall.sh",
            "assets/icon-white.png",
        ):
            self.assertTrue((ROOT / rel).exists(), f"missing {rel}")

    def test_executables_have_shebang(self):
        for rel in (
            "scripts/status",
            "scripts/history",
            "scripts/action",
            "system/charge-limit",
            "system/install.sh",
            "system/uninstall.sh",
        ):
            text = (ROOT / rel).read_text()
            self.assertTrue(
                text.startswith("#!/bin/bash"), f"{rel} must start with a bash shebang"
            )

    def test_manifest_is_publishable_bar_widget(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())

        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "io.github.mnsosa.charge-limit")
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        self.assertEqual(manifest["entryPoints"]["barWidget"], "BarWidget.qml")
        self.assertEqual(manifest["license"], "MIT")
        self.assertFalse(manifest["barWidget"]["allowMultiple"])

    def test_action_only_execs_the_root_owned_cli(self):
        action = (ROOT / "scripts" / "action").read_text()

        self.assertIn("sudo -n /usr/local/bin/charge-limit", action)
        self.assertNotIn("sudo -n ./", action)
        self.assertNotIn("$here", action)
        self.assertNotIn("BASH_SOURCE", action)

    def test_action_validates_set_arguments(self):
        action = (ROOT / "scripts" / "action").read_text()

        self.assertIn("^[0-9]+$", action)
        self.assertIn("set needs <start> <end>", action)

    def test_sudoers_only_grants_the_absolute_cli_path(self):
        sudoers = (ROOT / "system" / "charge-limit.sudoers.in").read_text()

        self.assertIn("__USER__", sudoers)
        self.assertNotIn("mnsosa", sudoers)
        for subcommand in ("toggle", "full", "on", "off"):
            self.assertIn(f"/usr/local/bin/charge-limit {subcommand}", sudoers)
        self.assertIn("/usr/local/bin/charge-limit set [0-9][0-9] [0-9][0-9]", sudoers)
        self.assertIn("/usr/local/bin/charge-limit set [0-9][0-9] 100", sudoers)
        self.assertNotIn("NOPASSWD: ALL", sudoers)

    def test_install_derives_user_and_validates_sudoers(self):
        install = (ROOT / "system" / "install.sh").read_text()

        self.assertIn("SUDO_USER", install)
        self.assertIn("visudo -cf", install)
        self.assertNotIn("mnsosa", install)

    def test_service_reapplies_on_boot_and_resume(self):
        unit = (ROOT / "system" / "charge-limit.service").read_text()

        self.assertIn("ExecStart=/usr/local/bin/charge-limit boot", unit)
        self.assertIn("suspend.target", unit)
        self.assertIn("hibernate.target", unit)


if __name__ == "__main__":
    unittest.main()
