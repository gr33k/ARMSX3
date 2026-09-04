#!/usr/bin/env python3
"""Source/package contract checks; these do not substitute for device UI tests."""
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
VIEW = (ROOT / "app/ARMSX3ViewController.mm").read_text()
SETTINGS = (ROOT / "app/ARMSX3SettingsViewController.mm").read_text()


class SettingsContract(unittest.TestCase):
    def test_no_probe_buttons(self):
        self.assertNotIn('[self button:@"JIT Test"', VIEW)
        self.assertNotIn('[self button:@"Metal Probe"', VIEW)
        self.assertIn('[self button:@"Settings"', VIEW)

    def test_all_settings_persist_and_have_safe_defaults(self):
        for name, default in [("ShowDebugLog", "NO"), ("ShowRuntimeOverlay", "NO"),
                              ("ShowInputDiagnostics", "NO"), ("ShowTouchControls", "YES"),
                              ("KeepScreenAwake", "YES")]:
            key = "ARMSX3" + name
            self.assertIn(f"{key}: @{default}", SETTINGS)
            self.assertIn(f"boolForKey:{key}", VIEW)
        self.assertIn("setBool:sender.isOn forKey:sender.accessibilityIdentifier", SETTINGS)

    def test_visibility_is_reapplied_and_menu_survives(self):
        layout = VIEW.split("- (void)updateLayoutMode", 1)[1].split("- (UIButton*)", 1)[0]
        self.assertIn("self.logView.hidden = landscape ||", layout)
        self.assertIn("self.landscapeMenuButton.hidden = !landscape;", layout)
        self.assertIn("button.hidden = landscape || !touch;", layout)
        self.assertIn("rail_width = touch ? bounds.size.height * artwork_aspect : 0.0;", VIEW)
        self.assertIn("[strong_self.touchReleaseTokens removeAllObjects]", VIEW)

    def test_versions_agree(self):
        info = plistlib.loads((ROOT / "app/Info.plist.in").read_bytes())
        cmake = (ROOT / "CMakeLists.txt").read_text()
        self.assertEqual(info["CFBundleShortVersionString"], "0.37.0")
        self.assertEqual(info["CFBundleVersion"], "37")
        self.assertIn('XCODE_ATTRIBUTE_MARKETING_VERSION "0.37.0"', cmake)
        self.assertIn("XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION 37", cmake)

    def test_renderer_and_jit_safety_are_not_changed(self):
        self.assertIn("Native Metal gameplay remains under development", SETTINGS)
        build = (ROOT / "scripts/build-accepted-core-ipa.sh").read_text()
        self.assertIn("a8faeb02e8b2c87af85d4b77e54bbadf149d0bc33b263e63b0b6b694e3dd1794", build)
        self.assertIn('if [[ "$ACTUAL_SHA" != "$EXPECTED_CORE_SHA" ]]', build)


if __name__ == "__main__":
    unittest.main()
