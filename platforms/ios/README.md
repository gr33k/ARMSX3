# ARMSX3 iOS core lane

This directory contains the public, device-first iOS port harness for the
RPCS3-derived ARMSX3 core. It does not contain PlayStation firmware, games,
signing keys, device identifiers, or private server paths.

## What the test app does

The UIKit app links the real ABI 30 `libRPCS3Core.dylib`. It initializes and
seals the iOS JIT arena, runs an LLVM-generated AArch64 self-test, attaches a
`CAMetalLayer` to RPCS3's Vulkan renderer through MoltenVK, imports firmware and
games through the Files picker, enumerates installed titles, and boots a chosen
title. It can also connect to a user-selected standard `ps3netsrv` host,
enumerate `/PS3ISO` and `/GAMES`, and boot through a read-only streamed virtual
disc without copying the complete image to the phone. It exposes live boot
stage, FPS, memory, NETISO throughput/reconnect telemetry, plus basic touch and
external GameController input.

Firmware and game files stay outside the source tree and IPA. Select local
content from Files or enter a NETISO host and port after installing the app.
`Import Local Copy` always consumes iPhone storage; rows prefixed `[NAS]` stream
through NETISO and do not copy the full game. No server address is compiled into
the binary.

Only one externally launched guest session may be active. RPCS3 can replace a
title's boot executable with a child SELF without ending that session, so the
app retains ownership across those handoffs and rejects another title until
`Stop Emulation` completes. This prevents a transient internal `stopped` state
from mounting a second remote game over a running guest.

The current test overlay intentionally uses plain transparent controls so input
behavior is easy to isolate. The production standalone controller will reuse
EmuHub's accepted PS2 visual language, continuous analog sticks, exact artwork
hit geometry, pressed-state feedback, and an accessible in-game menu overlay.

The standalone app remains a maintained iPhone emulator surface. EmuHub will
consume this same public core ABI after physical feasibility passes; it must not
fork the emulator, filesystem, or title-boot behavior.

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
4. Connect a standard `ps3netsrv`, confirm both ISO and extracted-folder rows,
   and boot a title larger than available local phone storage.
5. Confirm adaptive PPU compilation reaches linking and gameplay without the
   former iOS named-thread completion stall; compare elapsed time with v0.3.
6. Boot a demanding 3D title with audio and working input.
7. Verify START, face buttons, D-pad, both analog sticks, multi-touch chords,
   menu access, and a connected GameController against their PS3 mappings.
8. Record sustained FPS, frame pacing, CPU/RSX load, memory, heat, NETISO Mbps,
   reconnect count, and clean Stop/relaunch behavior.
9. Repeat the title to prove PPU/shader cache reuse while disc reads stay remote.

Any JIT, renderer, firmware, or boot failure remains a failed gate even when
the package itself builds successfully.
