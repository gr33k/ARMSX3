# ARMSX3 iOS core lane

This directory contains the public, device-first iOS port harness for the
RPCS3-derived ARMSX3 core. It does not contain PlayStation firmware, games,
signing keys, device identifiers, or private server paths.

## What the test app does

The UIKit app links the real ABI 34 `libRPCS3Core.dylib`. It initializes and
seals the iOS JIT arena, runs an LLVM-generated AArch64 self-test, attaches a
`CAMetalLayer` to RPCS3's Vulkan renderer through MoltenVK, imports firmware and
games through the Files picker, enumerates installed titles, and boots a chosen
title. It can also connect to a user-selected standard `ps3netsrv` host,
enumerate `/PS3ISO` and `/GAMES`, and boot through a read-only streamed virtual
disc without copying the complete image to the phone. It exposes live boot
stage, FPS, memory, NETISO throughput/reconnect telemetry, plus basic touch and
external GameController input.

The stopped-core `Metal Probe` is a clean-room direct-Metal foundation test.
It compiles native MSL, builds a Metal pipeline, draws one diagnostic triangle,
and presents it through the attached `CAMetalLayer` with device and GPU timing
readback. It does not select a PS3 renderer and is not evidence that RSX
commands, shaders, render targets, or games run through direct Metal.

`Rebuild Graphics Caches` is an explicit stopped-session recovery control. It
clears every title's derived shader records and the Vulkan driver pipeline
caches, then forces reconstruction on the next launch. It never removes
firmware, PPU/SPU modules, saves, trophies, imported games, or NETISO metadata.

The physical-A15 Uncharted 3 accuracy profile is deliberately title-scoped to
`BCES01175` and `BCUS98233`: native 100% resolution, one shader compiler worker,
Multithreaded RSX and asynchronous texture streaming off, and color-buffer
read/write plus accurate RSX reservation access on. Other title profiles retain
their existing settings. Because this diagnostic profile can increase memory,
qualify its first menu frame before entering gameplay. Each profiled boot emits
both the prepared database profile and the effective post-boot settings so a
saved custom configuration cannot silently invalidate the comparison.

Firmware and game files stay outside the source tree and IPA. Select local
content from Files or enter a NETISO host and port after installing the app.
`Import Local Copy` always consumes iPhone storage; rows prefixed `[NAS]` stream
through NETISO and do not copy the full game. No server address is compiled into
the binary.

Streamed titles use a split-storage contract that EmuHub's own ISO service must
preserve: immutable disc/game payloads are read through the active remote
virtual device, while firmware, caches, patches, saves, trophies, and small
writable title metadata remain in the app container. Title-specific guest-path
compatibility mounts must be read-only in effect, owned by the active session
generation, fail closed for every other title/source, and be removed before the
remote device is cancelled. This contract is independent of whether the bytes
come from standard `ps3netsrv` or a future EmuHub streaming backend.

For local firmware/game writes and guest free-space queries, iOS capacity is
the greater of immediate `statfs` availability and Foundation's
`NSURLVolumeAvailableCapacityForImportantUsageKey`. A failed Foundation query
falls back to `statfs`; it never invents capacity. Local writes retain a 1-GiB
safety reserve, and guest-visible free space retains the RPCS3 compatibility
cap just below 40 GiB even when the device can reclaim more. This avoids false
low-space failures on purgeable iOS storage without promising the guest the
phone's entire physical capacity.

Only one externally launched guest session may be active. RPCS3 can replace a
title's boot executable with a child SELF without ending that session, so the
app retains ownership across those handoffs and rejects another title until
`Stop Emulation` completes. This prevents a transient internal `stopped` state
from mounting a second remote game over a running guest.

Portrait retains the compact transparent test controls. Landscape uses the
accepted true-alpha EmuHub PlayStation controller rails at their native aspect,
eight exact D-pad sectors, continuous dual analog sticks, the documented
artwork hit geometry, pressed-state feedback, and an in-game EmuHub menu. The
landscape stage is edge-to-edge; the game surface is aspect-fit in the complete
center slot and neither video nor controller artwork is stretched.

Landscape displays transient `PAD OK`/`PAD REJECT` telemetry with digital and
analog values, plus compact runtime/last-operation state. The EmuHub menu can
show the complete current diagnostic summary. Each run also writes
`ARMSX3-last-session.log` to the app's file-sharing Documents directory so a
launch failure remains inspectable after disconnecting the device.

The standalone app remains a maintained iPhone emulator surface. EmuHub will
consume this same public core ABI after physical feasibility passes; it must not
fork the emulator, filesystem, or title-boot behavior.

PlayStation 3 is an official EmuHub Beta lane. Native iPhone and desktop clients
are the supported targets; no browser/WebAssembly runtime is claimed. The iOS
harness remains fail-closed and must qualify real device gameplay before a title
or feature is promoted beyond Beta.

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

## Modern iOS development lane

Current iOS requires two independent capabilities before the core can boot:

- The installed provisioning profile must grant Extended Virtual Addressing
  and the increased-memory limit. RPCS3 reserves a 24-GiB virtual direct-map;
  adding these keys only to a code signature is invalid and iOS rejects it.
- The process must receive Universal-JIT page preparation. LocalDevVPN provides
  transport for compatible sideload/JIT tools but does not grant EVA by itself.

Always read back the entitlements from the installed profile. The connected
iPad14,3 proved that a free personal-team Xcode profile can install the app but
does not grant EVA. Do not work around the resulting VM reservation failure by
returning an unreserved address or weakening fail-closed startup.

For an eligible development profile, launch the app stopped, attach LLDB, and
install the repository bridge before continuing:

```sh
xcrun devicectl device process launch \
  --device <CORE_DEVICE_ID> --start-stopped com.thec0de.armsx3ios

xcrun lldb <path-to-app>/ARMSX3iOS
```

```text
(lldb) device select <CORE_DEVICE_ID>
(lldb) device process attach --name ARMSX3iOS
(lldb) command script import platforms/ios/scripts/lldb_universal_jit.py
(lldb) armsx3-jit-install
(lldb) continue
```

Keep LLDB attached after the arena seals. On the physical M2 iPad, this path
prepared all 28 16-MiB regions (448 MiB) before startup reached the separate
EVA gate. A successful page-preparation run is not game or core-boot proof.

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
