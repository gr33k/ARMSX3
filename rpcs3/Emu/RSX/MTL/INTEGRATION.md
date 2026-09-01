# Native Metal RSX Integration

`MTLGSRender` and `MTLGuestBackend` are an isolated, fail-closed native renderer
lane. The iOS core compiles both as API-drift gates, but there is no renderer
enum, frontend factory switch, or public selector. The unreferenced objects are
not linked into the selectable core path. This lane is not advertised and does
not claim to render a game. `MTLGSRender` owns a real `CAMetalLayer`,
`MTLDevice`, command queue, one command buffer per guest frame, late drawable
acquisition, commit, and presentation. There is no probe triangle and no
Vulkan or CPU rendering fallback.

This work replaces the MoltenVK gameplay-command path with direct RSX-to-Metal
encoding; it is not a port of MoltenVK itself. The only retained MoltenVK
component is its pinned SPIR-V-to-MSL converter ABI, reused to translate the
existing RSX shader output. Native draws do not create Vulkan command buffers,
pipelines, render passes, images, or synchronization objects.

## Implemented boundary

- RSX `begin`/`end` and subdraw iteration follow the existing GL/Vulkan shape.
- Framebuffer layout, scaled viewport, clipped scissor, clear values, current
  guest programs, draw ranges, and display-buffer presentation metadata cross a
  typed `mtl::guest_backend` boundary.
- A backend must encode guest framebuffer preparation, clears, draws, and the
  final guest-surface-to-drawable presentation copy. It must close every Metal
  encoder before returning.
- Command-buffer failures are captured asynchronously and fail the next RSX
  operation. A missing backend or failed operation throws immediately.
- The independently implemented native guest backend allocates private Metal
  color and depth/stencil targets keyed by guest address and exact RSX layout.
  It supports Apple-supported 1x/2x/4x sample counts and resolves multisampled
  color targets to sampleable textures.
- Full-channel, full-surface color/depth/stencil clears are encoded as real
  Metal render passes. Partial-channel or scissored clears fail closed until a
  clear pipeline exists.
- The presentation pass samples the selected guest render target, preserves its
  aspect ratio in the drawable, and clears uncovered output to black. The
  target cache retires entries after 180 frames and is capped at 96 entries.
- Packed 16-bit color targets are temporarily promoted to `BGRA8Unorm` for
  rendering. Guest-memory export and exact packed conversion remain missing
  and therefore must not be inferred from successful target allocation.
- The first real draw subset is encoded end to end: native non-indexed RSX
  array draws using points, lines, line strips, triangles, or triangle strips;
  analyzed persistent/volatile vertex streams; draw parameters; vertex and
  fragment constants/state; native MSL functions; cached render pipelines;
  and load/store render passes. The backend factory remains deliberately
  unregistered.
- Standard RSX blend factors/equations, per-target blending and packed-format
  color masks, depth testing/writes, one- or two-sided stencil, culling,
  winding, fill/line rasterization, depth clip/clamp, and filled-triangle depth
  bias are mapped to native Metal state. Depth/stencil objects use a bounded
  128-entry cache; encoder-dynamic state is rebound for every draw because each
  draw owns a fresh render encoder.
- Indexed, inline, instanced, emulated-topology, textured, logic-op, signed
  blend-equation, depth-bounds, depth-clip-ignore-W, point-polygon, wide-line,
  point/line-depth-bias, non-full-sample-mask, smoothed, stippled,
  auxiliary-SPIRV-Cross-resource, and last-vertex-provoking draws all return a
  specific fail-closed error rather than silently taking an incomplete path.
- The existing RSX GLSL decompilers now accept explicit device-capability
  records. Their normal Vulkan entry points preserve the prior live Vulkan
  queries, while `MTLRSXShaderProgram` supplies deterministic Metal choices,
  compiles the resulting GLSL to Vulkan-semantics SPIR-V without creating a
  Vulkan object, and preserves vertex/fragment constant metadata.
- `MTLRSXShaderProgram` converts every decompiler descriptor into explicit,
  collision-checked Metal buffer/texture/sampler slots while reserving the
  translator's auxiliary buffer indices. Unsupported resource classes or an
  exhausted binding namespace fail closed before MSL translation.
- Production translation uses MoltenVK v1.4.2's already-linked
  `SPIRVToMSLConverter` ABI with the exact pinned converter header and the
  matching `MVK_spirv_cross` namespace. Native Metal shader/function/pipeline
  objects are retained in one-device bounded caches; RSX-to-SPIR-V programs
  are separately capped at 512 vertex and 512 fragment entries.
- An independently implemented shared/write-combined upload arena allocates
  lazy 4 MiB pages, retires them from command-buffer completion handlers,
  never waits for the GPU, limits a single allocation to 16 MiB, and hard-caps
  retained upload memory at 64 MiB. Abandoned frames reclaim their pages.
- Memory coherency, tiled-resource invalidation, scaled blits, host labels,
  semaphores, and occlusion queries deliberately fail closed until implemented.

## Required new modules before selection

1. Expand the first real array draw to sampled textures, logic operations,
   remaining polygon/MSAA state, provoking-vertex parity, and any required
   translator auxiliary resources. The first texture slice must upload
   CPU-backed color textures per draw and reject render-target aliases until
   coherency and invalidation are real; persistent address-only caching is not
   correct.
2. Add index uploads plus indexed, inline, instanced, restart, emulated
   topology, and multidraw handling on the existing bounded upload arena.
3. Complete the current guest color/depth target cache with sampled texture
   resources, tiling, exact memory-format conversion, invalidation, barriers,
   and fault recovery.
4. Blit/copy/resolve, MSAA, conditional/occlusion query, GCM label, and guest
   semaphore implementations.
5. Complete the existing aspect-preserving presentation pass with stereo,
   gamma, exact guest-format conversion, and output-scaling parity.

## Existing files the integration lane must modify

- `rpcs3/Emu/CMakeLists.txt`: compile-only integration is complete for the iOS
  frontend with ARC for the Metal Objective-C++ modules, the independently
  implemented upload arena, exact MoltenVK converter bridge, native cache,
  backend-independent RSX-to-SPIR-V adapter, and metadata validation; do not
  remove the Vulkan sources.
- `rpcs3/Emu/system_config_types.h`: add a distinct native-Metal renderer enum.
- `rpcs3/Emu/system_config_types.cpp`: add its stable configuration string.
- `rpcs3/ios/RPCS3IOS.cpp`: include the renderer, register a complete
  `mtl::guest_backend_factory`, add the factory switch case, and expose Metal
  only behind an explicit test selector while Vulkan remains rollback.
- `rpcs3/Emu/title.cpp`: add the native-Metal device label to renderer title
  formatting instead of falling through an incomplete enum switch.
- `rpcs3/Emu/RSX/RSXThread.cpp`: include native Metal in renderer-gated native
  overlay handling only after the overlay pass exists.
- `rpcs3/Emu/RSX/rsx_cache.h`: decide shader-cache worker policy explicitly for
  Metal rather than inheriting the non-Vulkan single-worker branch by accident.
- `rpcs3/ios/RPCS3IOSBuildInfo.h`: advertise native-Metal gameplay only after
  the integration and physical gates pass, never for this skeleton alone.
- `platforms/ios/PS3_3D_PERFORMANCE_PLAN.md` and
  `platforms/ios/TEST_STATUS.md`: record source/build/device evidence in the
  main lane without promoting compile or package evidence to gameplay proof.

The integration lane must not select this renderer until every fail-closed
operation above has a real implementation and controlled Vulkan-vs-Metal pixel
comparisons pass. A successful compile or clear is not gameplay evidence.

## License boundary

`MTLRuntime.h` and `MTLRuntime.mm` retain GPL-3.0-or-later provenance from the
ARMSX2 command-lifetime and upload-ring architecture. Most RPCS3 source is
GPL-2.0-only. They remain excluded from the production core path; the linked
upload arena is an independent implementation. Do not link the GPL-3 runtime
into a distributed RPCS3/ARMSX3 binary unless project counsel or the relevant
copyright holders approve a compatible boundary. MoltenVK/SPIRV-Cross
provenance and exact-version requirements are documented in
`rpcs3/ios/SPIRVCrossDependency.md`.
