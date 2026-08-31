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

V0.20 isolated the first stability lane on the same physical device:

- A warm U1 launch reused its cached PPU object and held 60 FPS in menus, while
  NETISO remained idle and shader/pipeline compile counters stayed at zero.
- Live 3D still terminated twice after process memory rose above 3.3 GiB.
  Immediately before failure, process headroom fell to 723-729 MiB and UIKit
  issued memory warnings.
- A representative gameplay sample measured normalized SPU CPU at 66% of six
  logical cores and actual Metal execution at 1129 ms per one-second interval.
  RSX rendered roughly 1876 draws in that frame and the Vulkan allocator later
  reported 164% pressure.
- The exact v0.20 wake report measured 1042 wakeups/sec and symbolized to the
  PPU LLVM/MCJIT scheduler, but its interval primarily covers boot compilation;
  it is not a measured warm-gameplay wake rate.

V0.21 must first keep that same U1 scene alive with bounded memory. It may not
restore V0.10/V0.11's repeated synchronized eviction loop. Once stable, the
same profiler will determine the independent SPU and renderer gains; neither
track is allowed to hide behind menu FPS.

The V0.21 comparison is device-adaptive rather than A15-hardcoded. MoltenVK's
soft pressure budget is 20% of reported unified memory, bounded to 1-3 GiB,
while live process headroom retains fixed safety reserves. Test the exact same
U1 scene first on iPhone14,3/A15/6 GiB and then iPad14,3/M2/8 GiB. Record the
effective budget printed at renderer creation and never compare different
resolution, title profile, cache state, or gameplay segments.

The M2 comparison currently has a hard provisioning prerequisite. A physical
LLDB/debugserver run successfully prepared the complete 448-MiB Universal-JIT
arena on the connected iPad14,3, but RPCS3 then aborted while reserving its
24-GiB VM layout. The free personal-team profile does not grant Extended
Virtual Addressing, and adding that entitlement only to the signature correctly
fails profile validation. Do not weaken the VM reservation or treat the JIT
bridge as gameplay proof. Resume the tablet comparison only after installed-app
entitlement readback proves EVA is present and the process reaches core boot.

The current iPhone observations also strengthen the renderer correctness gate:
Uncharted 2 reaches its live-3D transition, produces severe green/white
corruption, and then reports 0 FPS while audio continues. Uncharted 3 instead
retains transient block and white-square artifacts without its former
persistent green/pink cast. These are separate title failures and must not be
collapsed into one cache or color workaround. God of War's repeatable 0-FPS
transition after four 60-FPS logos is a third, post-boot runtime failure.

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
- Current source-audit hypothesis: normal PPU initialization adds every
  `Emu.GetGameDirs()` path to `ppu_precompile()` only when the main executable
  cache is missing. A warm launch with a valid EBOOT cache but an uncached
  late PRX can therefore skip the related-directory scan and compile that PRX
  after boot. Before changing policy, correlate v0.20 timestamps for
  `LLVM: Compiling module`, PPU progress state, cache hit/miss paths, and the
  U1 menu-to-gameplay transition. A fix must use a per-title completeness
  record or targeted missing-module scan; recursively rescanning a remote
  NETISO tree on every launch is not acceptable.
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

### Mobile wait-policy experiment

The post-V0.22 candidate removes four sources of avoidable CPU contention while
preserving a short hot-spin path: Vulkan fence waits, Vulkan event readbacks,
RSX offload drains, and mobile occlusion-query polling. Asynchronous Vulkan
pipeline workers also use Utility QoS on iOS. These changes are independently
reversible and do not alter renderer output or cache identity.

This is a scheduling experiment, not the direct-Metal backend and not an FPS
claim. Compare the same U1/RDR warm-cache scenes against V0.20 telemetry. Keep
the batch only if it reduces wait/other CPU and thermal pressure without adding
latency, stalls, or renderer regressions. If Metal execution remains dominant,
continue the clean-room direct-Metal RSX phases above rather than stacking more
unmeasured scheduling tweaks.

### Command-buffer ring-lifetime candidate

Post-V0.24 commit `1fd3c9401` separates upload-ring lifetime from presentation:
a tagged primary Vulkan command buffer captures managed ring boundaries, and a
proven successful fence completion can return those ranges even when a title
does not present during a long load. Monotonic snapshot IDs reject older
completion observations, while process-unique heap generations reject snapshots
captured before grow or renderer recreation. Timeout paths never authorize
reclamation.

The candidate deliberately adds no new fence polling and does not restore the
driver-sensitive zero-timeout polling experiment. A no-present workload can
therefore retain completed ranges until an existing observation or the
512-command-buffer reuse fallback, but it must stop growing indefinitely. Use
the new named heap-growth lines plus process memory/headroom to decide whether a
future low-frequency retirement queue is justified on Apple/MoltenVK.

This is a transient-memory lifetime repair, not native Metal, a shader fix, or
an FPS claim. Physical acceptance requires the Sonic Generations no-present
load and, if available, the measured Ratchet index-ring load, followed by the
same U1/RDR gameplay and U3 correctness gates. Preserve V0.24 as rollback.

### Global range-lock wake candidate

Post-V0.26 commit `65758e455` keeps the existing PPU/SPU memory-protection
barrier intact but replaces passive PPUs' blind scheduler yield with a wait on
the exclusive range-lock word. Writer release notifies only when the whole word
reaches zero; the 50-microsecond timeout is a safety poll rather than a guessed
backoff. This targets measured barrier amplification without weakening DATA or
PROTECTION exclusion.

Treat it as a CPU-contention candidate, not a renderer or FPS fix. On the same
warm U1/RDR scenes, compare PPU/SPU load, frame-time distribution, thermals,
audio, and Stop behavior to V0.26. Retain it only if synchronization pressure
falls without page-protection faults, new stalls, or gameplay regressions.

### Post-stall audio refill candidate

Post-V0.26 commit `e1d70c9f4` increases callback-ring capacity from 20 ms to
60 ms above the unchanged configured target and counts whole-block push
failures. This preserves up to 40 ms more recovery burst after an RSX or JIT
stall without deliberately raising normal queued latency. At 48 kHz, each
formerly silent 256-sample loss is 5.33 ms and can explain the reported
periodic knock.

Treat the new warning as telemetry, not a cosmetic suppression mechanism.
Capture it beside frame, compiler, and queue timings in U1/RDR/U2/U3. If drops
continue, fix the producer stall; do not keep enlarging the ring. Reject the
candidate if steady-state latency, drift, fast audio, or Stop behavior worsens.

### Tiled blit-bound renderer candidate

Post-V0.26 commit `8bb0deb0f` isolates and hardens upstream `37848abbc` so a
heuristic destination cache rectangle cannot straddle a GCM tile. The local
version uses a floor full-row cap, carries that cap through every later height
expansion, and falls back before cache mutation when a partial-row payload
cannot be represented safely. Focused contracts cover the two boundary defects
found during independent review of the donor patch.

This is a renderer-correctness candidate for U2/U3 transient rectangles and
warping, not a broad performance claim. Compare fresh graphics-cache and warm
launches against V0.26, record whether the CPU/tile fallback is exercised, and
reject any missing transfer, color regression, crash, or teardown slowdown.
Only after this isolated result is physically attributable should the larger
pitch-compatibility or interpolation candidates be layered on it.

### Full-queue vblank liveness candidate

Post-V0.26 commit `f8fd9dae1` prevents a full 32-event guest queue from
stranding the periodic vblank producer. Only primary/secondary vblank-only
events can be dropped; all flip, queue, user, unmapped-memory, and mixed events
keep their original retry semantics. The first and every 1024th drop provide a
low-volume runtime marker.

This is a zero-FPS recovery guard, not a fix for the guest interrupt-thread
mutex and not a settled-performance claim. Exercise a reproducible full-queue
path, correlate the warning with resumed vblank/FPS, then verify Stop,
immediate relaunch, and a second title. Any lost non-vblank behavior rejects the
candidate.

### One-to-one blit interpolation candidate

Post-V0.26 commit `8a729951e` disables linear interpolation only for exact 1:1
memory-source copies, matching upstream `32b711cdb`. Guest-scaled operations
and render-target sources retain filtering. This directly targets the reported
RDR moving-car/train blur without changing shaders, formats, cache identity, or
the direct-Metal roadmap.

Use the same RDR sequence for V0.26 versus candidate A/B, with U1 and U3 as
visual controls. Retain only if 1:1 motion is sharper without pixel shimmer or
degrading legitimately scaled content. Do not report an FPS improvement from a
sampling correction.

## Required evidence

Every candidate records source commit, IPA SHA-256, bundle version/build,
device/OS, title ID, fresh-versus-warm cache state, FPS, CPU split, MoltenVK and
RSX timings, memory footprint/headroom, visual/audio result, and crash or clean
stop. A build or launch is never gameplay proof.
