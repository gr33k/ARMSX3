# ARMSX3 iOS test status

## 2026-08-29 smoke IPA checkpoint

Source:

- Fork branch: `gr33k/ARMSX3`, `ios-feasibility`
- Upstream base: `ARMSX2/ARMSX3` revision
  `a74a0f3e045f064515a5fa48643e66ab386577d3`
- MoltenVK: official iOS package `v1.4.2`
- MoltenVK package SHA-256:
  `b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1`

Static gates:

- PASS: Xcode 26.6 / Apple Clang 21 compiled the app serially with the
  `iphoneos26.5` SDK.
- PASS: executable is arm64 Mach-O with minimum iOS 15.0.
- PASS: MoltenVK is statically linked; package readback has no non-system
  dynamic framework dependency.
- PASS: packaged app has `allow-jit`, `allow-unsigned-executable-memory`,
  `extended-virtual-addressing`, `increased-memory-limit`, and
  `get-task-allow` entitlements.
- PASS: strict code-signature verification and ZIP readback passed.
- PASS: executable privacy scan found no local username, NAS path, or private
  server address.

Artifact:

- Name: `ARMSX3-iOS-Feasibility-Smoke-v0.1.ipa`
- Size: `1,482,707` bytes
- SHA-256:
  `c88d0d7c92c196e69dee7f770e2d5af6b0ba3cfc9e0a1ab21cc0d9de83e35618`

Physical gates:

- PENDING: install through TrollStore on an iOS 15 JIT-capable physical device.
- PENDING: on-screen `[JIT] PASS` from emitted AArch64 code returning `42`.
- PENDING: on-screen `[Vulkan] PASS` after Metal surface, physical GPU,
  graphics/present queue, and logical device creation.

Core gates:

- NOT STARTED: core-only `rpcs3_emu` iOS library without Qt or Android JNI.
- NOT STARTED: firmware import/install and sandbox VFS.
- NOT STARTED: PS3 title boot, frames, audio, controls, performance, thermals,
  and clean shutdown.

Important implementation finding:

- Apple declares `pthread_jit_write_protect_np` unavailable to iOS SDK callers.
  The smoke test therefore uses strict W^X transitions: map writable `MAP_JIT`
  memory, emit code, invalidate the instruction cache, change the page to
  read/execute with `mprotect`, and only then call it. Full-core JIT allocators
  must preserve that invariant and cannot copy the macOS API call unchanged.

An IPA build or menu is not PS3 feasibility proof. Promotion requires the
physical gates above, followed by a real firmware and game boot.
