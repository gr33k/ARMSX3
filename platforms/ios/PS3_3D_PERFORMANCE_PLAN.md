# PS3 3D Performance Plan

## Product gate

The target is sustained real 3D gameplay on a physical iPhone14,3 (A15,
iOS 15.3), not menus, prerendered video, compilation screens, or a successful
boot. Red Dead Redemption, Uncharted 1, and Uncharted 3 are the first controlled
set. GTA V and Uncharted 2 follow after the first set is stable. A title passes
only when gameplay reaches its intended frame rate without visual corruption,
audio breakup, memory warnings, or a process crash.

V0.19 established the current floor:

- U1 can hold 60 FPS in startup video and menus, then collapses in live 3D and
  can terminate the app.
- U3's persistent green/pink cast is fixed, but live rendering still produces
  warped content and transient green, white, and stale-image rectangles.
- RDR reached live gameplay at 2.0 FPS, 3389 MiB process footprint, and an iOS
  memory warning.

These results prove presentation alone is not the bottleneck and do not prove
that a Metal backend alone can reach the target.

Two symbolized v0.19 iOS resource reports also establish a CPU/JIT floor:

- iOS measured 781 and 897 wakeups/sec against its reported 150/sec limit.
- The hottest sampled chain ran from `ios_thread_worker::run` through the PPU
  LLVM/MCJIT object-emission, machine-scheduling, and register-allocation path.
- The reports prove that expensive PPU compilation remained active during the
  sampled gameplay interval, but do not attribute every wakeup to LLVM.

V0.21 is accepted only if a same-title physical comparison lowers live-gameplay
LLVM compile time and wake pressure while improving sustained FPS and audio
pacing. A successful build, faster menu, or shorter launch is insufficient.

## V0.20 measurement boundary

ABI 33 adds one-second, low-overhead measurements without changing title
profiles, resolution, JIT mode, shader policy, or cache behavior:

- `CPU P/S/R/O`: logical-core-normalized PPU, SPU, RSX, and other process CPU.
- `MVK E/W/Q/G`: MoltenVK command encoding, queue/display waits, queue submit,
  and actual Metal command-buffer execution in aggregate milliseconds over the
  sample interval. Submit can include encoding and must not be summed with it.
- `MVK F C`: measured frame interval and encoded/executed command-buffer counts.
- `SH`: SPIR-V-to-MSL, MSL compile, and Metal pipeline compile counts and
  aggregate milliseconds during the interval.
- `RSX D/S U/X/F`: draw/submit counts; setup, vertex-upload, texture-upload,
  draw-execution, and flip microseconds for the sampled frame.
- `H`: `os_proc_available_memory()` headroom, separate from process footprint.

Capture a stable menu window and the first 30 seconds of real gameplay for each
title. The transition matters more than a session-wide average.

## Decision gates

1. If MoltenVK encoding/submit/wait or Metal execution dominates gameplay,
   begin the direct Metal RSX path immediately.
2. If PPU/SPU dominates, first port or adapt applicable upstream ARM64 JIT,
   scheduler, reservation, and block-cache improvements. Do not expect a
   renderer rewrite to fix a CPU ceiling.
3. If RSX uploads, resolves, barriers, or transient allocation dominate, fix
   command construction and resource lifetime before replacing the backend.
4. If shader/pipeline compilation occurs during settled gameplay, move it out
   of the frame path and strengthen persistent cache reuse.
5. If headroom falls sharply across U3 stop followed by U1 boot, audit teardown
   and destroy retained renderer/device/transient state. Requiring an app
   restart between games is not acceptable.

Several lanes can be dominant at once. A direct Metal backend and PPU/SPU work
are parallel tracks when the measurements justify both.

## ARMSX2 donor audit

The iOS Metal implementation in upstream ARMSX2 commit
`1024c3538ee2ff27fc0f9d5272d76202b8b1c03b` was inspected directly. Reusable
patterns include:

- Direct `CAMetalLayer`, `MTLDevice`, queue, drawable, and GPU timing.
- Unified-memory upload rings with explicit draw-lifetime tracking.
- Private untracked resources with explicit `MTLFence` synchronization.
- Separate texture, vertex, late-upload, and draw command buffers.
- Compact persistent Metal pipeline-state keys and caches.
- Apple framebuffer-fetch and memoryless-attachment paths.
- Bounded deferred submission for frame-capped or skipped frames.

The ARMSX2 EE/VU ARM64 recompilers target PS2 architecture and cannot be copied
into RPCS3's PPU/SPU JIT. Donor code reused from GPL-3.0-or-later ARMSX2 must
retain source provenance and attribution.

## Direct Metal RSX phases

1. Add an iOS-only backend scaffold that owns the existing `CAMetalLayer`,
   `MTLDevice`, command queue, drawable lifecycle, and timing. Keep Vulkan as a
   selectable rollback until physical parity exists.
2. Establish RSX shader translation to MSL and a persistent pipeline cache.
   Validate precision, swizzle, depth/stencil, sampling, and specialization
   before performance claims.
3. Implement unified-memory buffer rings, texture upload/copy, render targets,
   clears, blits, barriers/fences, and presentation with bounded in-flight work.
4. Implement MSAA resolve/unresolve and attachment lifetime correctly, using U3
   transient boxes and warping as the correctness gate.
5. Profile and reduce allocations, copies, synchronization, and CPU encoding.
6. Re-run RDR/U1/U3 gameplay, memory-pressure, background/foreground, stop,
   and sequential-title tests on physical hardware before promotion.

## CPU and runtime track

- Compare this fork against current upstream and Android ARM64 PPU/SPU JIT,
  scheduler, LLVM, reservation, and memory-mapping paths using narrow diffs.
- Preserve executable-code caches and avoid recompiling valid PPU/SPU modules.
- Precompile cacheable static PPU modules before gameplay and persist their
  valid ARM64 output. Dynamic SPU/self-modifying paths may still require JIT,
  but compilation must not monopolize render or audio-critical intervals.
- Keep compilation bounded and parallel only while headroom permits; gameplay
  threads retain priority.
- Move noncritical cache serialization, NETISO reads, and shader/pipeline work
  off latency-sensitive emulator threads without weakening correctness.
- Use resolution reduction only as a diagnostic. Production must retain a
  reasonable image while sustaining the title's intended frame rate.

## Required evidence

Every candidate records source commit, IPA SHA-256, bundle version/build,
device/OS, title ID, fresh-versus-warm cache state, FPS, CPU split, MoltenVK and
RSX timings, memory footprint/headroom, visual/audio result, and crash or clean
stop. A build or launch is never gameplay proof.
