#!/usr/bin/env python3
"""Bounded standalone source/media checks, not physical controller qualification."""
import hashlib
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
APP = ROOT / "platforms/ios/app"
VIEW = (APP / "ARMSX3ViewController.mm").read_text()


class StandaloneBoundary(unittest.TestCase):
    def test_shared_media_is_unchanged(self):
        for name, sha in [
            ("left", "7f90c6627f4cd3752f87c73553dd6e5981973039573f5b26ed1ed2ac214dadf4"),
            ("right", "f070d2e7dea0fbef08a8feeef16a4533b186090616c66a26bfdfad84af8bc176")
        ]:
            data = (APP / f"ControllerSkins/controller-ps3-landscape-{name}.png").read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), sha)

    def test_no_runtime_emuhub_brand_or_import(self):
        for path in APP.iterdir():
            if path.suffix in {".h", ".mm"}:
                code = path.read_text()
                self.assertNotRegex(code, r'@"[^"\n]*EmuHub[^"\n]*"')
                self.assertNotRegex(code, r'#(?:include|import).*EmuHub')
        for foreign_path in ("clients/ios/EmuHubRemote", "server/ps3-scanner.js", "docker-compose.yml"):
            self.assertFalse((ROOT / foreign_path).exists(), foreign_path)

    def test_ps_button_is_guest_input_and_separate_from_menu(self):
        install = VIEW.split("- (void)installLandscapeControls", 1)[1].split("- (void)layoutTouchControls", 1)[0]
        self.assertIn("self.playStationButton.tag = RPCS3_IOS_PAD_BUTTON_PS;", install)
        self.assertRegex(install, r'playStationButton addTarget:self action:@selector\(touchDown:\)')
        self.assertRegex(install, r'playStationButton addTarget:self action:@selector\(touchUp:\)')
        self.assertIn("UIControlEventTouchCancel | UIControlEventTouchDragExit", install)
        self.assertNotRegex(install, r'playStationButton addTarget:self action:@selector\(showGameMenu:')
        self.assertIn("self.playStationButton.hidden = !touch;", VIEW)
        self.assertIn("sender == self.playStationButton", VIEW)
        self.assertIn('imageNamed:@"AppIcon60x60@3x.png"', VIEW)
        self.assertIn("UIViewContentModeScaleAspectFit", VIEW)

    def test_existing_rail_geometry_is_literal(self):
        self.assertIn("853.0 / 1844.0", VIEW)
        frames = re.findall(r'normalized_rect\((?:left|right)_rail,[^;\n]+', VIEW)
        self.assertEqual(len(frames), 14)
        self.assertIn("0.2240, 0.5520, 0.5480, 0.2520", VIEW)
        self.assertIn("0.2210, 0.5520, 0.5410, 0.2520", VIEW)

    def test_physical_stick_clicks_and_core_guest_routes(self):
        for side, bit in [("left", "L3"), ("right", "R3")]:
            self.assertIn(f"gamepad.{side}ThumbstickButton.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_{bit}", VIEW)
        handler = (ROOT / "rpcs3/Emu/Io/IOS/IOSPadHandler.cpp").read_text()
        for bit in ("PS", "L3", "R3"):
            self.assertIn(f"button(RPCS3_IOS_PAD_BUTTON_{bit})", handler)


if __name__ == "__main__":
    unittest.main()
