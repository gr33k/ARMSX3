# Standalone controller contract

## V0.37 ownership and identity

The standalone shell and PS3 core belong to gr33k/ARMSX3, branch ios-core.
Integration adapters, server/admin/authentication and Docker config do not.
Shared controller media is permitted; retain attribution and original files.
Do not replace the source images to change branding or silently import a
different consumer app's control implementation.

Accepted rails are 853x1844 RGBA PNGs, displayed at 853/1844 aspect:

- Left SHA-256: `7f90c6627f4cd3752f87c73553dd6e5981973039573f5b26ed1ed2ac214dadf4`.
- Right SHA-256: `f070d2e7dea0fbef08a8feeef16a4533b186090616c66a26bfdfad84af8bc176`.

All 14 existing normalized input rectangles remain unchanged in
ARMSX3ViewController.mm. The two analog axes retain their accepted circular
activation area, radial clamp and 0.07 deadzone. No image is regenerated,
stretched or cropped for V0.37.

## PS and branding

The new native PS button is an opaque, rounded, dark-metal plate using the
existing app-icon rendition of docs/images/armsx3-app-icon.png plus a sharp
native PS label. The shared PNG's old wordmark remains preserved in the source
file but is fully covered in the standalone UI. This is a deliberate native
control, not an edited/claimed replacement PNG. Its background must stay opaque
and it must not shrink on press, or the old wordmark could become visible.

Production formulas live in app/ARMSX3ControllerLayout.h, not a test-only copy:

- Landscape rail width = stage height * 853 / 1844. Existing Start ends at
  normalized x=0.435; the right stick ends at y=0.804.
- PS width = max(66 pt, 0.415 * right-rail width), height = max(44 pt, 0.112 *
  rail height); right edge = 0.915 * rail width, bottom = 0.949 * rail height.
  Thus normal-size left/top edges are x=0.500/y=0.837. It does not overlap Start
  or the right stick, and covers the wordmark including antialiasing margin.
- Portrait retains video width and floor(width*9/16) height. A separate 56-point
  footer places Select (x=8,w=72), Start (x=88,w=72), PS (right inset=8,w=88),
  all y=video bottom+6, h=44. No footer button overlays video or face controls.
- Touch-controls off hides PS and removes the footer/landscape rails. Landscape
  retains a separate app Menu. PS must never invoke the app's settings menu.

PS is RPCS3_IOS_PAD_BUTTON_PS (bit 16) through the existing state registry and
IOSPadHandler, with minimum 120-ms tap visibility. Held touch stays pressed;
up/outside/cancel/drag-exit use token-guarded release. The full rounded plate is
the hit contour, with no invisible expansion. Background and controls-off
clear touch state. A real guest's response depends on its PS/system-menu state.

## Stick clicks

Physical GameController left/rightThumbstickButton already map to L3/R3 bits
12/13. No button was added for touchscreen L3/R3 in V0.37. Proposed opt-in
gesture: short center tap, then tap-and-hold while steering. It must not delay
normal motion; moving/long first touches must not prime a click; release,
cancellation, rotation, background and hiding controls must clear state.
Ordinary long-press would conflict with holding a direction.

iPhone 13 Pro Max uses Haptic Touch, not pressure-sensitive 3D Touch:
[Apple device specs](https://support.apple.com/en-gb/111870).
UITouch force is only meaningful with supported 3D Touch/Pencil hardware:
[Apple touch-force API](https://developer.apple.com/documentation/uikit/uitouch/force).
Do not use force or thumb contact area as a substitute for stick clicking.

## Verification

Run settings and standalone-boundary Python tests, then compile/run
scripts/test-controller-layout.cpp with clang++ -std=c++20 -framework CoreGraphics.
These exercise the production geometry at 10 landscape heights (320..1024 pt),
10 portrait widths (296..1000 pt), coverage/non-overlap, PS/L3/R3 registry updates,
source wiring and unchanged PNG hashes. They are not device gameplay evidence.

Build only with scripts/build-accepted-core-ipa.sh. Confirm app/plist version,
strict signing, ZIP and exact core SHA against V0.35. Physical gates are in
TEST_STATUS.md; no public release/promotion until the relevant device gates pass.
