# ARMSX3 iOS feasibility lane

This directory contains the public, device-first iOS port work. It is deliberately
separate from the Android application and does not contain firmware, games, signing
keys, device identifiers, or private server paths.

## Current gate

The first IPA is a runtime feasibility probe, not yet a PS3 emulator build. It must
pass both of these checks on a physical JIT-capable iOS device before the full core is
linked:

1. Allocate `MAP_JIT` memory, emit AArch64 machine code, execute it, and receive the
   expected return value.
2. Create a Vulkan instance, Metal surface, physical device, graphics/present queue,
   and logical device through MoltenVK.

This catches entitlement, executable-memory, Vulkan portability, Metal surface, and
basic GPU compatibility failures with a small build instead of hiding them inside a
multi-gigabyte RPCS3 build.

## Build

Requirements:

- Apple Silicon Mac with Xcode and the iPhoneOS SDK
- CMake 3.28 or newer
- A physical arm64 iPhone or iPad with iOS 15 or newer
- TrollStore or another setup that preserves the required JIT entitlements

Run:

```sh
OUTPUT_IPA="$HOME/Desktop/ARMSX3-iOS-Feasibility-Smoke.ipa" \
  platforms/ios/scripts/build-smoke-ipa.sh
```

The dependency script downloads the official MoltenVK iOS package, verifies the
pinned SHA-256, and keeps it under the ignored `.deps` directory. The build is
unsigned until packaging, uses one Xcode job, enforces a 10 GiB free-space floor,
and ad-hoc signs the IPA with explicit TrollStore JIT and memory entitlements.

## Next core gates

After the physical smoke gate passes:

1. Build `rpcs3_emu` as a core-only iOS static library without Qt or Android JNI.
2. Adapt RPCS3 virtual-memory/JIT write protection to iOS.
3. Feed a `CAMetalLayer` into the existing Vulkan RSX renderer through MoltenVK.
4. Add UIKit file import and firmware installation into the app sandbox.
5. Boot a small legal test title and capture frame rate, frame pacing, memory, heat,
   audio, and shutdown evidence on real hardware.

Build/package success is not gameplay or performance proof.
