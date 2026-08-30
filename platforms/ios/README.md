# ARMSX3 iOS core lane

This directory contains the public, device-first iOS port harness for the
RPCS3-derived ARMSX3 core. It does not contain PlayStation firmware, games,
signing keys, device identifiers, or private server paths.

## What the test app does

The UIKit app links the real ABI 29 `libRPCS3Core.dylib`. It initializes and
seals the iOS JIT arena, runs an LLVM-generated AArch64 self-test, attaches a
`CAMetalLayer` to RPCS3's Vulkan renderer through MoltenVK, imports firmware and
games through the Files picker, enumerates installed titles, and boots a chosen
title. It also exposes live boot stage, FPS, and memory telemetry plus basic
touch and external GameController input.

Firmware and game files stay outside the source tree and IPA. Select them from
Files after installing the app.

## Reproducible build

Requirements:

- Apple Silicon Mac with Xcode and the iPhoneOS SDK
- CMake 3.28 or newer and Ninja
- At least 10 GiB free for a clean core build
- Physical arm64 iPhone or iPad with TrollStore or equivalent JIT entitlements

The scripts pin and hash-check MoltenVK 1.4.2, the XITRIX iOS 15 LLVM SDK, and
FFmpeg 8.1.1. LLVM source is intentionally not initialized or rebuilt.

```sh
JOBS=2 platforms/ios/scripts/build-core-ios15.sh

OUTPUT_IPA="$HOME/Desktop/ARMSX3-iOS-Core-Test.ipa" \
  platforms/ios/scripts/build-core-ipa.sh
```

Both scripts enforce free-space floors. The core build defaults to two jobs;
the Xcode app build uses one. The IPA is ad-hoc signed with explicit TrollStore
JIT and memory entitlements, so normal App Store installation services are
expected to reject it.

## Acceptance gates

An IPA, menu, simulator, or successful static build is not PS3 feasibility
proof. The physical sequence is:

1. Install with TrollStore and launch on the target device.
2. Confirm the on-screen core initialization and LLVM JIT result is `133`.
3. Import an official `PS3UPDAT.PUP` and confirm the detected version.
4. Import a small legal PS3 title and confirm it appears by clean title and ID.
5. Boot to rendered gameplay with audio and working input.
6. Record sustained FPS, frame pacing, memory, heat, and clean stop behavior.

Any JIT, renderer, firmware, or boot failure remains a failed gate even when
the package itself builds successfully.
