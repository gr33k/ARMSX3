# ARMSX3 iOS test status

## 2026-08-29 real-core IPA checkpoint

Source:

- Public fork: `gr33k/ARMSX3`, branch `ios-core`
- iOS base: `XITRIX/rpcs3` `ios-port` revision
  `e422589696e480b52c3e083e34e18ccd5a74cc0f`
- ARMSX3 comparison revision:
  `a74a0f3e045f064515a5fa48643e66ab386577d3`
- Core ABI: `30`

Pinned dependencies:

- MoltenVK `1.4.2`, SHA-256
  `b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1`
- iOS 15 LLVM SDK revision `ca7933e47d3a3451-ec81b2304bcb`, SHA-256
  `138446dbbd497f1c18a741aab85b27982ec62099f13e39f81abfbdc901160583`
- FFmpeg `8.1.1`, SHA-256
  `b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3`

Static core gates:

- PASS: all `1,292` Ninja edges built with `-j2` for arm64 iOS 15.0.
- PASS: the current `libRPCS3Core.dylib` is a 77,454,672-byte arm64 Mach-O with
  minimum iOS 15.0 and the expected ABI 30 C exports, including all five
  NETISO entry points.
- PASS: Vulkan/RSX, MoltenVK Metal surface, iOS audio, iOS pad input, firmware
  installer, ISO/ZIP/folder/package import, game library, and LLVM recompilers
  are present in the real core.
- PASS: MetalFX is a weak framework dependency; iOS 15 falls back to RPCS3's
  Vulkan scaling path.
- PASS: the iOS binary does not import the `os_sync_wait_on_address` APIs that
  require iOS 17.4. The iOS frontend uses RPCS3's condition-variable futex.
- PASS: the iOS config path uses yaml-cpp's bundled Dragonbox formatter rather
  than libc++ floating `to_chars`, which requires iOS 16.3.
- PASS: full core build took 338.67 seconds, peaked below 1 GiB resident, and
  recorded zero swaps.

Static app/package gates:

- PASS: UIKit app compiled and linked serially against the real core.
- PASS: app and nested core are arm64 with minimum iOS 15.0.
- PASS: app loads `@rpath/libRPCS3Core.dylib`; the nested dylib is signed before
  the containing app.
- PASS: strict deep code-signature verification and ZIP readback passed.
- PASS: packaged app has `allow-jit`, `allow-unsigned-executable-memory`,
  `extended-virtual-addressing`, `increased-memory-limit`, and `get-task-allow`.
- PASS: packaged binary scan found no private Mac path, NAS path, or private
  server address.
- PASS: app version `0.3.0`/build `2` added an explicit native
  `Open XMB` action through the existing `rpcs3_ios_boot_vsh()` export.

V0.4 NETISO feasibility artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.4.ipa`
- Compressed size: `27,969,563` bytes
- SHA-256:
  `aac015054a66c459d99947e4a6968607f640d19e9abfd69ef2c02039d5478b6f`
- PASS: incremental two-job core compilation and one-job UIKit compilation
  completed for arm64 iOS 15.0. The adaptive iOS PPU path also compiled: it
  uses up to three direct short-lived workers with healthy process headroom,
  two under moderate pressure, and one under severe pressure, then joins every
  worker before linking or gameplay. It does not alter live-game scheduling.
- PASS: the ABI 30 core exports connect, disconnect, enumerate, direct boot,
  and lock-independent NETISO metrics. The read-only virtual device implements
  standard ps3netsrv list/stat/open/offset-read, finite timeouts, reconnect-once
  identity checking, split/ordinary PS3 ISO enumeration, and server-generated
  virtual ISO paths for extracted `/GAMES` folders.
- PASS: the standalone app takes a user-entered host and port, persists them in
  `NSUserDefaults`, merges remote and local title rows, directly boots a remote
  row, and reports NETISO Mbps, transferred MiB, and reconnect count next to
  FPS and process memory. No private host is compiled into the artifact.
- PASS: independent archive readback verified ZIP integrity, deep strict
  signing, TrollStore JIT/memory entitlements, bundle
  `com.thec0de.armsx3ios`, version `0.4.0` build `3`, local-network usage text,
  arm64/iOS 15.0 app and core, all five ABI exports, and zero private Mac, NAS,
  or `192.168.10.*` strings in either executable.
- PASS PHYSICAL: exact v0.4 bytes connected from the iOS 15.3 phone to the
  user-selected standard ps3netsrv endpoint, enumerated remote titles, and
  directly booted both extracted `/GAMES` content and ISO content without a
  full-disc local import.
- PASS PHYSICAL: `The Walking Dead` cold-compiled all 100 PPU modules with
  three workers and about 3.8 GiB headroom, crossed linking, and reached a
  live guest loop. Syscall counters continued increasing with no NETISO fatal,
  crash, or Jetsam event.
- FAIL PHYSICAL / INPUT: the v0.4 on-screen `START` tap did not advance `The
  Walking Dead`. Pad 0 was bound to `iOS Game Controller 1`, and the ABI bit is
  mapped correctly, so v0.5 holds every short touch pulse for at least 120 ms
  across multiple guest pad polls. This fix is not physically qualified yet.
- PARTIAL PHYSICAL / GTA V: remote title `BLES01807` reached the Duplex logo,
  loaded its child SELF, and used RPCS3's continuous executable handoff. It
  did not yet prove sustained demanding 3D gameplay.
- FAIL PHYSICAL / UNCHARTED 1 MEDIA: `BCES00065` mounted remotely but its
  `/PS3_GAME/USRDIR/EBOOT.BIN` was rejected as invalid or unsupported. This is
  title/release executable compatibility or encryption, not proof of a NETISO
  transport failure.
- PARTIAL PHYSICAL / UNCHARTED 2: `BCUS98123` mounted, scanned, and began a
  cold 111-module PPU compilation with three workers and about 3.5 GiB
  headroom. Gameplay has not yet been reported.
- OPEN TRANSPORT/CORE ERROR: the user saw a resource/NETISO temporarily
  unavailable message several times before Uncharted 2 proceeded. No matching
  socket failure has yet been isolated, so reconnect exhaustion and guest
  `0x80010001` must both remain open rather than guessing at the source.
- FAIL PHYSICAL / SESSION RACE: v0.4 briefly exposed `stopped` during GTA's
  child SELF handoff, allowing another external boot to collide with the live
  title. V0.5 owns one guest session across executable transitions and rejects
  another boot until explicit Stop; physical retest remains pending.
- PRIMARY FEASIBILITY GATE: run Red Dead Redemption and at least one GTA-class
  or comparably demanding 3D title long enough to measure sustained FPS/frame
  pacing, CPU/RSX utilization, process memory, thermals, NETISO throughput and
  reconnects, compile time, audio, input, Stop latency, and second-boot cache
  reuse. Do not integrate this core into EmuHub based on package or menu proof.
- PRODUCT BOUNDARY: retain this standalone iPhone emulator as a supported
  harness/product and integrate EmuHub later through the same ABI 30 core,
  avoiding separate emulator behavior or a second NETISO implementation.

V0.5 input/session candidate:

- Name: `ARMSX3-iOS-Core-Test-v0.5.ipa`
- Compressed size: `27,973,081` bytes
- SHA-256:
  `9e411d4f83ad4c1604e878a617f7d1b223baaddfdb192136f600608826abe7cd`
- PASS: the unsigned source core and app-embedded core matched SHA-256
  `a46b62f69ca8560fc00ca8c3bd98e90d67755e8c03b3a23d8995f5eeddfa0214`
  before signing. A build-time Xcode target-directory embed script prevents a
  newly labeled app from silently retaining a stale core dylib.
- PASS: ZIP readback, deep strict signing, arm64 app/core, iOS 15.0 minimum,
  version `0.5.0` build `4`, local-network privacy text, all five NETISO ABI
  exports, and executable path-leak scans passed.
- FIX READY / PHYSICAL PENDING: short touch pulses remain asserted for at least
  120 ms, with tokenized delayed releases so a stale release cannot cancel a
  newer press. Retest `START`, face buttons, D-pad chords, and rapid re-presses.
- FIX READY / PHYSICAL PENDING: one externally launched guest session remains
  claimed across continuous child executable handoffs. A second title must be
  rejected until explicit Stop, and Stop must make the library bootable again.
- UI FOLLOW-UP: the production standalone landscape controller will reuse the
  accepted EmuHub PS2 visual language, continuous analog sticks, exact artwork
  hit geometry, and an accessible menu overlay. V0.5 intentionally retains the
  transparent debug controls so the input/session fix can be isolated first.

V0.6 NETISO mount/Uncharted compatibility candidate:

- Name: `ARMSX3-iOS-Core-Test-v0.6.ipa`
- Compressed size: `27,974,158` bytes
- SHA-256:
  `24d4fee423963f9489bd62fd981ba9680fd91bc32deef1d76e459632ac01c702`
- PASS: the unsigned source core and app-embedded core matched SHA-256
  `9710c8ed0fa92e596bf9daf398eb633114b3d861c357463b12f46f27be5f226c`
  before signing. The incremental core build used `-j2`; the app build used one
  Xcode job and completed without an OOM event.
- PASS: ZIP readback, deep strict signing, TrollStore JIT/memory entitlements,
  arm64 app/core, iOS 15.0 minimum, bundle `com.thec0de.armsx3ios`, version
  `0.6.0` build `5`, all five NETISO ABI exports, and executable private-path
  and private-address scans passed.
- ROOT CAUSE / V0.5 TRANSPORT: each `iso_file` opened its own stateful NETISO
  connection to the same extracted `/GAMES` folder. `ps3netsrv` therefore
  regenerated the complete virtual ISO for every ISO-backed guest file. The
  NAS log showed many same-timestamp `open ...` / `building virtual iso...`
  entries for `BCES00065`, followed by the same pattern for `BCES01175`; this
  could wedge the service until its container was restarted.
- FIX READY / PHYSICAL PENDING: V0.6 retains one strong, persistent backing for
  the currently mounted `/***PS3***/` extracted game. All guest ISO file handles
  keep independent positions but share one serialized protocol connection and
  one 1 MiB read-ahead cache. A real transport failure reconnects and verifies
  image identity once. Selecting a different extracted game replaces the
  retained mount; ordinary `/PS3ISO` files keep independent connections.
- FIX READY / PHYSICAL PENDING: synthesized extracted-folder images reject the
  automatic sibling `.dkey` and `.key` existence probes locally. Extracted game
  folders are already decrypted; sending these probes to `ps3netsrv` caused two
  additional pointless virtual-ISO builds per archive inspection.
- PARTIAL PHYSICAL / V0.5 UNCHARTED 3: `BCES01175` reached its language screen
  and then live gameplay over NETISO. Cross initially appeared unresponsive but
  eventually advanced; its ABI bit and iOS pad-handler mapping are correct.
  The user reports visible graphical glitches, so this is positive feasibility
  evidence but not a renderer-quality or input-latency pass.
- USER-REPORTED FAIL / V0.5: the user also reported a V0.5 app exit. A device
  stack report at `23:36:52` showed the process live rather than a new formal
  crash report, so the precise exit cause remains open and is not attributed to
  NETISO without evidence.
- FIX READY / PHYSICAL PENDING: exact title `BCUS98123` receives RPCS3's stated
  first-line workaround `Stub PPU Traps = 1` through the database-config layer
  after V0.5 reached fatal PPU trap `0x00068be4`. User custom title settings keep
  precedence. Other titles remain unchanged, and the setting is exposed as a
  bounded per-game integer for diagnosis.
- PASS: a fatal guest-thread log now changes the visible state to a red stopped
  message and hides compilation progress, instead of leaving a completed or
  apparently frozen progress bar after the guest has already terminated.
- REQUIRED PHYSICAL COMPARISON: after V0.5 stops, install these exact V0.6 bytes,
  restart only `ps3netsrv` if the old client left it wedged, then launch one
  extracted Uncharted title. The NAS log must show one initial virtual-ISO build
  rather than a same-path flood; verify list latency, Cross/D-pad/START response,
  compile progress, NETISO reconnect count, sustained gameplay, renderer output,
  Stop, and a second cached launch. Package/build proof does not close these gates.

V0.7 scene-watchdog/controller candidate:

- Name: `ARMSX3-iOS-Core-Test-v0.7.ipa`
- Compressed size: `31,761,065` bytes
- SHA-256:
  `cfc1b4df912d1da81ae5b029459e36c7d6f2ac559be32d52f27cd6408b3cc85f`
- ROOT CAUSE / V0.6 PHYSICAL CRASH: the installed app was independently read
  back as version `0.6.0` build `5`. Its `2026-08-29 23:56:25` device report is
  a foreground `scene-update` watchdog termination with exception `0x8badf00d`:
  the app exceeded iOS's 10-second wall-clock allowance during rotation while
  still running. This is not evidence that the guest or renderer thread crashed.
- SYMBOLICATED EVIDENCE: the V0.6 app image UUID in that stackshot matches the
  packaged executable. Its main thread had accumulated about 164 seconds of CPU,
  and its app frames resolve exactly to `appendLog:`, `handleCoreLog:`, and the
  core-log callback block. The frontend was dispatching every RPCS3 notice/trace
  line to the main queue, rewriting the complete `UITextView`, and scrolling it
  once per line while demanding titles emitted thousands of lines.
- SEPARATE HISTORICAL EVENT: the formal `23:47:38` report belongs to V0.5 build
  `4`, not V0.6. It records an emergency-exit/Stop-watchdog mutex failure and
  must not be conflated with the V0.6 scene-update watchdog.
- FIX READY / PHYSICAL PENDING: V0.7 preserves levels 1-4 and explicit fatal/PPU
  milestones, but coalesces levels 5-6 to at most one diagnostic update per 500
  ms. The log view now appends through `NSTextStorage` instead of rebuilding its
  complete string, and it does not force scrolling while hidden in landscape.
- FIX READY / PHYSICAL PENDING: display attachment is coalesced onto one main-run
  loop update and skipped when the physical drawable dimensions and refresh rate
  are unchanged. Rotation still updates the Metal surface, but repeated UIKit
  layout passes no longer submit identical display surfaces.
- PASS STATIC: this is an app-only build over the unchanged V0.6 core dylib; the
  unsigned core remains SHA-256
  `9710c8ed0fa92e596bf9daf398eb633114b3d861c357463b12f46f27be5f226c`.
  Serial Xcode compilation, archive integrity, deep strict signing, TrollStore
  JIT/memory entitlements, arm64/iOS 15.0 binaries, version `0.7.0` build `6`,
  `@rpath` loading, and private-path/address scans all passed.
- PASS STATIC / ARTWORK IDENTITY: landscape embeds the accepted true-alpha
  853x1844 EmuHub PlayStation rails without resampling their source files. Left
  SHA-256 is `7f90c6627f4cd3752f87c73553dd6e5981973039573f5b26ed1ed2ac214dadf4`;
  right is `f070d2e7dea0fbef08a8feeef16a4533b186090616c66a26bfdfad84af8bc176`.
  Each rail is aspect-fit at `853/1844`; the 16:9 game surface is independently
  aspect-fit between them and is never stretched.
- FIX READY / PHYSICAL PENDING: landscape uses the accepted normalized hit map
  for L1/L2, R1/R2, D-pad, Triangle/Square/Circle/Cross, Start, Select, both
  analog sticks, and the EmuHub menu. The D-pad supports diagonals, both sticks
  emit continuous normalized axes with a 7% dead zone, triggers emit full analog
  pressure, and graphical buttons retain the 120 ms minimum guest-visible pulse.
  Circular and rounded controls also use shape-aware hit tests, so the tiny
  corners of diagonal bounding rectangles cannot steal an adjacent button.
  Portrait intentionally retains the compact debug controls.
- REQUIRED PHYSICAL GATES: install these exact bytes, relaunch Uncharted 3,
  rotate portrait-landscape-portrait repeatedly during gameplay, and confirm no
  scene watchdog. Verify both sticks across the full circle, every D-pad diagonal,
  simultaneous stick plus face-button chords, shoulders/triggers, Start/Select,
  menu/PS/Stop, visual hit alignment, display centering, compile/load time, FPS,
  NETISO throughput, renderer glitches, and clean second launch. Reduced main
  thread and log overhead is expected to improve loading and frame pacing, but
  no speed or stability pass is claimed until that physical run succeeds.
- PRODUCT STATUS: PlayStation 3 is now an official EmuHub Beta lane targeting
  native iPhone and desktop clients. This standalone app remains the iPhone
  qualification harness; EmuHub must consume the same core ABI. No web runtime
  is claimed, and Beta does not waive the physical gameplay gates above.

V0.8 fullscreen/input/diagnostic candidate:

- Source revision: `f0c0448539aef2b336d85bac57404f6346b4b9f3`
- Name: `ARMSX3-iOS-Core-Test-v0.8.ipa`
- Compressed size: `31,767,416` bytes
- SHA-256:
  `c2f6722c0c0e10c6194499503a5048237f03a8a76020eda359e35a18f10b4fb1`
- PASS STATIC: this remains an app-only build over the unchanged V0.6/V0.7 core
  dylib, SHA-256
  `9710c8ed0fa92e596bf9daf398eb633114b3d861c357463b12f46f27be5f226c`.
  Serial Xcode compilation, ZIP readback, deep strict signing, TrollStore JIT
  and memory entitlements, arm64/iOS 15.0, version `0.8.0` build `7`, required
  NETISO/input exports, and private-path/address scans passed.
- PASS STATIC / ARTWORK PRESERVED: the exact accepted PlayStation rail bytes are
  unchanged. Left remains
  `7f90c6627f4cd3752f87c73553dd6e5981973039573f5b26ed1ed2ac214dadf4`;
  right remains
  `f070d2e7dea0fbef08a8feeef16a4533b186090616c66a26bfdfad84af8bc176`.
- FIX READY / PHYSICAL PENDING: landscape now removes the safe-area wrapper,
  stack margins, vertical gap, stage corner clipping, and the 28-point height
  subtraction. The controller rails occupy the complete device height at native
  `853/1844` aspect, and the independent 16:9 game surface consumes the complete
  center slot without stretching either artwork or video.
- ROOT CAUSE / V0.7 INPUT: face buttons and Start used ordinary `UIButton`
  target/action events and worked physically, while the D-pad and both sticks
  used custom `UIControl` tracking overrides and emitted no usable input. V0.8
  replaces the D-pad with eight non-overlapping circular sectors carried by the
  proven button event path. Cardinal sectors emit one bit and diagonal sectors
  emit the exact two-bit chord; the center 18% remains a dead zone. Both analog
  sticks now use direct `UIView` touch begin/move/end/cancel handling while
  retaining continuous normalized axes and the 7% analog dead zone.
- FIX READY / PHYSICAL PENDING: every touch update displays a temporary `PAD OK`
  or `PAD REJECT` readout with D-pad and both-stick values. Landscape also keeps
  runtime state plus the last operation visible, the EmuHub menu exposes full
  current/last-line diagnostics, and each run writes the coalesced event
  stream to the file-sharing document `ARMSX3-last-session.log`. This is
  diagnostic evidence, not proof that the guest consumed the input.
- PASS: the complete lightweight iOS contract suite passes. Its stale ABI 29
  expectations now match shipped ABI 30, and the GPU-default assertion now
  matches the existing `async_recompiler` source default; runtime behavior was
  not changed by those test corrections.
- PASS PHYSICAL BOOT / FAIL SUSTAINED 3D: the extracted Uncharted 1 `BCES00065`
  folder was using a modified debug/FSELF `EBOOT.BIN` (SHA-256
  `1d97d8e3ab6ff860df418dc664876dd54b6fb98f6fa8e2a4b5e0f0721d0a6355`).
  It is preserved as `EBOOT.BIN_EMUHUB_BACKUP_20260830_0800`; the folder's
  preserved retail `EBOOT.BIN_CEX` is now active as `EBOOT.BIN` (SHA-256
  `bcbd125bc0614fb5994d30f2e82c6510aaaf2fc6c51f917c4953d4a210b32bd4`).
  After restarting only `ps3netsrv`, a NAS-local protocol probe enumerated 60
  extracted titles and passed an ISO PVD random read on the rebuilt Uncharted
  virtual image at `22,654,615,552` bytes. The repaired title physically reached
  menus, prerendered scenes, and live 3D gameplay without a NETISO fatal, but FPS
  collapsed as real gameplay began. The exact installed TrollStore IPA bytes
  could not be read back through Installation Proxy, so this is positive title
  evidence rather than qualification of a named package.
- MEDIA REPAIR READY / PHYSICAL PENDING: Uncharted 2 `BCUS98123` had no runtime
  `pak22.psarc`; its `5,596,444,529` bytes were split across `.part00` through
  `.part02`, while an identical complete copy was hidden as
  `ORIGINALpak22.psarcbak`. The three fragments and hidden complete copy are
  preserved outside `/GAMES` at
  `EMUHUB_MEDIA_BACKUPS/BCUS98123-Uncharted_2-20260830`; the byte-identical
  reconstructed `pak22.psarc` is now active with SHA-256
  `68a2e164225c1f80a760443476bc6f39d025ff6d8a31ec46ab7aedb8f27fe9a9`.
  A fresh NAS-local `/***PS3***/GAMES/...` VISO probe passed open and ISO PVD
  random read at `21,920,808,960` bytes. A launch started before this repair
  must be stopped and relaunched to rebuild the VISO; gameplay remains unverified.
- SOURCE READY / NEXT CORE BUILD: invalid read-length errors now include both
  the server-returned and requested byte counts, and the independent probe
  reports the opened remote image size before its random read. The contract
  suite passes, but this post-V0.8 core-source diagnostic is not in the V0.8
  IPA. Folder probes must include the standard `/***PS3***/` marker; plain
  `/GAMES/...` opens the directory itself and is not a VISO transport test.
- PASS SERVER / NO UPDATE AVAILABLE: the running container already uses
  `ps3netsrv` build `20250501`, current image digest
  `sha256:f23497ba5c34099e65c3a0590f5dfd0ee21c5c66f592a644aafb2d88f3d60e1e`.
  Pulling `shawly/ps3netsrv:latest` confirmed it is current, so no image or
  Compose replacement was performed.
- MEDIA REPAIR READY / PHYSICAL PENDING: V0.7 title `BCES01741` reached the
  Duplex screen and looped because its active `EBOOT.BIN` was a modified wrapper
  containing `6,125` `DUPLEX` markers (SHA-256
  `f712c86158256a228932a00b544c11e10c477e10f17af2cf3b02d570c548b410`).
  It is preserved as `EBOOT.BIN_EMUHUB_DUPLEX_BACKUP_20260830_0830UTC`.
  The title's clean `ORIG/EBOOT.BIN`, which contains no Duplex marker, is now
  active at `PS3_GAME/USRDIR/EBOOT.BIN` (SHA-256
  `0ecbc9c0cd0bf4a493611148e7d7d4a3ba48d7948ecb7969c6e735fca9bb0b9f`).
  A fresh NAS-local VISO probe passed open and ISO PVD random read at
  `37,665,964,032` bytes. The next physical launch must bypass the Duplex screen
  and reach the retail executable before this repair is accepted.
- REQUIRED PHYSICAL GATES: install the exact V0.8 bytes and first tap every
  D-pad cardinal/diagonal plus sweep both analog sticks while confirming `PAD
  OK` and live values. Then verify guest response, edge-to-edge landscape,
  simultaneous stick/face input, Stop/relaunch, repaired Uncharted 1 boot,
  Uncharted 2, and the God of War loop. Preserve `ARMSX3-last-session.log` after
  any failure. Package/static checks do not close these gates.

V0.9 live-3D pressure candidate:

- Source revision: `d947a6da25d901d16f36091fbb9be09ff1743f56`
- Name: `ARMSX3-iOS-Core-Test-v0.9.ipa`
- Compressed size: `31,768,673` bytes
- SHA-256:
  `7cdd0911c110f8bc6dcc4dbc0252a2f89c96b6c6f1bc9a1a334f0c2eed9a797c`
- ROOT CAUSE PHYSICAL: a USB syslog sample from live Uncharted 1 gameplay on
  iPhone `iPhone14,3`, iOS 15.3, showed the renderer at `183%` of its deliberately
  soft unified-memory target with only `565 MiB` process headroom. The old policy
  incorrectly promoted that soft ratio to `fatal` every frame. Fatal recovery
  hard-synchronized the GPU, drained the Metal driver, and purged reusable
  resources repeatedly, creating self-amplifying FPS and cache thrash. Earlier
  samples at `634-637 MiB` headroom also included iOS memory warnings, active
  PSARC reads, SPU compilation, and Metal shader compilation. No crash, Jetsam,
  NETISO fatal, or server OOM was present in the captured interval.
- FIX READY / PHYSICAL PENDING: a soft iOS VRAM target can now reach at most
  `severe`; only critically low process headroom or a real allocation failure can
  invoke fatal recovery. Proactive reclaim remains immediate on escalation but
  is bounded to once per 1000 ms at moderate, 500 ms at severe, and 250 ms at
  fatal instead of once per frame. Direct allocation-failure recovery bypasses
  this frame-boundary throttle, preserving the safety path.
- FIX READY / PHYSICAL PENDING: exact title `BCES00065` receives a reversible
  `75%` internal resolution scale through the database layer. The full iOS output
  surface and controller geometry are unchanged, and a user per-game setting
  retains precedence. Other titles remain at their existing scale.
- PASS STATIC: the complete lightweight iOS contract suite, focused memory
  policy assertions including the observed `183%` case, incremental two-worker
  arm64 core build, serial app build, ZIP readback, strict deep signing, iOS 15.0
  load commands, TrollStore JIT/unsigned-memory/extended-address/increased-memory
  entitlements, version `0.9.0` build `8`, and private path/address scans passed.
  The unsigned checkpoint core SHA-256 is
  `b25596b075085fbcb7f968ca6445943a8c4defdfaaed4fffa37a4d64444e7e60`;
  the packaged ad-hoc signed core SHA-256 is
  `e25478f2b284e1445601a522ed326b17317f5068723faa453c4276133c0e78d1`.
- FAIL PHYSICAL / JETSAM: the exact V0.9 package was installed and reached the
  Uncharted 1 live-3D scene twice. The first failure report at
  `2026-08-30 08:40:45 -0700` names `ARMSX3iOS` as `largestProcess`, records
  `rpages=255556` with 16 KiB pages (approximately `3.90 GiB` resident), and
  terminates PID `11088` for `vm-pageshortage` with only `2005` system pages
  free. An immediately preceding Jetsam snapshot recorded approximately
  `3.47 GiB` resident while iOS killed background daemons for
  `vm-pageshortage` and `compressor-thrashing`.
- FAIL PHYSICAL / REPRODUCED: the second exact-package run reached the same
  streamed gameplay path as PID `11352`. USB syslog captured UIKit memory
  warnings at `08:42:35.850544` and `08:42:42.028695`, repeated texture-cache
  eviction warnings, interruption/reconnection of the GameController daemon
  under system pressure, and then device-log disconnection at termination.
  This disproves the V0.9 assumption that 500 ms severe reclaim alone could
  bound the active 3D working set. V0.9 must not be promoted.

V0.10 Jetsam-resistance candidate:

- Source revision: `fb59ab7654b8705c0ada40142cd08dacaaf660d5`
- Name: `ARMSX3-iOS-Core-Test-v0.10.ipa`
- Compressed size: `31,769,396` bytes
- SHA-256:
  `cd023265a4ca8a709576207b04f3922505198fe6235182e3294da42421f19ebb`
- FIX READY / PHYSICAL PENDING: the extreme soft-VRAM boundary is now `150%`,
  so the measured `183%` Uncharted condition receives fatal recovery while the
  ordinary `95-149%` overshoot remains severe. Process headroom enters fatal at
  `768 MiB` and remains there until it recovers above `1024 MiB`; this responds
  before the prior `565 MiB` sample without restoring the old every-frame fatal
  policy. Fatal frame-boundary reclaim remains capped at four passes per second.
- FIX READY / PHYSICAL PENDING: UIKit memory warnings now cross an ABI 31,
  lock-free core notification and force one immediate fatal RSX reclaim pass.
  Fatal recovery can return unused malloc-zone pages to iOS no more than once
  per second. This directly covers the two warnings captured before the V0.9
  Jetsam while retaining direct allocation-failure recovery.
- FIX READY / PHYSICAL PENDING: exact title `BCES00065` now receives a `50%`
  internal resolution scale through the same reversible database profile. The
  full output surface, aspect ratio, and controls remain unchanged; a user
  title-specific configuration continues to take precedence.
- PASS STATIC/PACKAGE: the complete lightweight iOS contract suite, focused
  pressure thresholds, incremental two-worker arm64 core build, serial app
  build, ABI export, ZIP readback, strict signatures, iOS 15.0 load command,
  TrollStore JIT/unsigned-memory/extended-address/increased-memory entitlements,
  version `0.10.0` build `9`, and private path/address scans passed. The
  unsigned checkpoint core SHA-256 is
  `1c096d4ca1bb5fae7e34490943b3d8fa43892e137a904b385deda4a98ae32d9a`;
  the packaged ad-hoc signed core SHA-256 is
  `cf59eba373fe35659c78bfe7d92723b205acda2ede980beb5d9bce07ccc31821`.
- PASS DISTRIBUTION: the exact audited IPA was copied to iCloud Drive as
  `ARMSX3-iOS-Core-Test-v0.10.ipa`; destination SHA-256 readback is identical to
  the package hash above. TrollStore installation and launch remain physical
  gates rather than consequences of this file transfer.
- PASS PARTIAL PHYSICAL / STABILITY IMPROVED: the exact V0.10 package reached
  Uncharted 1 live 3D and the user completed the first gameplay section despite
  very low FPS. Unlike both V0.9 attempts, the observed run remained alive
  through two UIKit memory warnings. This is positive Jetsam resistance, not a
  complete stability pass.
- FAIL PHYSICAL / PERFORMANCE: a USB sample from `09:53:10` through `09:56:40`
  captured 66 first-use Metal shader compiles, 22 SPU block compiles, 119
  fatal-style texture eviction warnings, and two UIKit memory warnings. Seven
  CPU samples ranged from `46.7%` to `69.0%`; NETISO was idle. Physical overlay
  screenshots measured `2.6 FPS` at `3192 MiB` resident and later `0.0 FPS` at
  `3211 MiB`. The allocator reported severe pressure at `146%`, `665 MiB`
  internal allocations, and `1141 MiB` process headroom. V0.10 therefore trades
  the prior Jetsam for excessive cache churn and is not a performance pass.
- REQUIRED PHYSICAL GATE: a revised candidate must remove the sustained
  eviction loop, approach the title's approximately 30 FPS target after shader
  warmup, retain responsive controls, and remain below Jetsam pressure. Stop and
  relaunch must also prove pipeline/SPU cache persistence rather than judging
  only the first-use compilation path.

V0.11 cache-thrash correction candidate:

- Source revision: `3d289b765c778424da9c8a98bbb309baeb9e70cf`
- Name: `ARMSX3-iOS-Core-Test-v0.11.ipa`
- Compressed size: `31,769,379` bytes
- SHA-256:
  `afee2be8447abd8cd6273ec520eaa9a3dbf778d0ae88c9471e0c848256108568`
- FIX READY / PHYSICAL PENDING: soft Vulkan-budget overshoot can now reach
  only severe pressure; fatal recovery remains reserved for `<=768 MiB` process
  headroom, UIKit memory warnings, and direct allocation failure. This removes
  the exact 150% threshold that produced 119 destructive texture evictions in
  the V0.10 physical sample without removing its successful Jetsam safeguards.
- FIX READY / PHYSICAL PENDING: nonfatal frame-boundary reclaim is paced at
  two seconds for severe pressure and five seconds for moderate pressure;
  genuine fatal recovery remains at 250 ms. Focused policy assertions lock all
  four intervals and the nonfatal soft-budget behavior.
- FIX READY / PHYSICAL PENDING: exact title `BCES00065` retains 50% internal
  resolution and now uses two asynchronous shader compiler workers instead of
  the six-thread device's automatic single worker. This is intentionally capped
  at two to reduce first-use stalls without multiplying compiler memory enough
  to undo V0.10's stability gain.
- FIX READY / PHYSICAL PENDING: the diagnostic status no longer displays
  completed boot-module progress after the emulator reaches running state.
- PASS STATIC/PACKAGE: the complete lightweight iOS contract suite, focused
  reclaim-policy assertions, incremental two-worker arm64 core build, serial app
  build, ZIP readback, strict deep signing, iOS 15.0 load commands, TrollStore
  JIT/unsigned-memory/extended-address/increased-memory entitlements, version
  `0.11.0` build `10`, and private path scans passed. The unsigned checkpoint
  core SHA-256 is
  `29dacb9ab81ffe15f44b4ca52481cd123e6f4a375e9d84faaf4d6f8b4ee4a7df`;
  the packaged ad-hoc signed core SHA-256 is
  `dc1c8bb1818ca0833b2ecba3cacdf82ac21f860dfc6fec4784ec40c91c8b6aea`.
- PASS DISTRIBUTION: the audited IPA was copied to iCloud Drive as
  `ARMSX3-iOS-Core-Test-v0.11.ipa`; Desktop and destination SHA-256 readback are
  identical. Installation, launch, and gameplay remain physical gates.
- FAIL PHYSICAL / PERFORMANCE: device inventory confirmed the installed package
  as version `0.11.0` build `10`. In the Uncharted 1 live-3D scene, the overlay
  measured `0.0 FPS` at `3351 MiB` with NETISO idle. A USB syslog capture from
  `10:24:39` through `10:31:22` recorded 389 coalesced texture-cache eviction
  warning batches, CPU samples mostly between `44%` and `69%`, and 23
  GameController-daemon interruptions. V0.11 removed the stale progress display
  but did not remove the fatal RSX synchronization loop and must not be promoted.

V0.12 bounded texture-recovery candidate:

- Source revision: `8c371380ed596c6167c56a9e15e463da72b5e355`
- Name: `ARMSX3-iOS-Core-Test-v0.12.ipa`
- Compressed size: `31,769,254` bytes
- SHA-256:
  `607e59c2511ac2a5383ea29e301d5b9d30580b44691dc6ccb0f1dfa707cf0320`
- FIX READY / PHYSICAL PENDING: persistent fatal process pressure now runs a
  hard frame-boundary cache reclaim no more than once every five seconds instead
  of four times per second. Entering fatal pressure and every UIKit memory
  warning still force an immediate pass; malloc-zone heap relief remains
  independently eligible once per second while hard reclaim is gated.
- FIX READY / PHYSICAL PENDING: a nullable temporary-texture allocation miss
  no longer escalates from its allocator-level severe retry into an unbounded
  fatal bind retry on iOS. The draw advances with its already-bound null texture
  for that miss. Non-nullable Vulkan allocation failures retain immediate fatal
  recovery, preserving the crash-safety path.
- PASS STATIC/PACKAGE: the lightweight iOS contracts, focused fatal-cadence
  assertion, incremental two-worker core build, serial app build, ZIP readback,
  strict deep signing, iOS 15.0 load commands, TrollStore JIT/unsigned-memory/
  extended-address/increased-memory entitlements, and version `0.12.0` build
  `11` passed. The unsigned checkpoint core SHA-256 is
  `260133096e4e340cbd64ed97fc441b51720be77882f83ad2fa2592a0afed253f`;
  the packaged ad-hoc signed core SHA-256 is
  `461acc2a017e8f547d57ad6b5311f5241ab7bc2e46ccec469e16e3defcc9f222`.
- PASS DISTRIBUTION: the audited IPA was copied to iCloud Drive as
  `ARMSX3-iOS-Core-Test-v0.12.ipa`; Desktop and destination SHA-256 readback are
  identical. Installation, launch, and gameplay remain physical gates.
- PASS PHYSICAL / EVICTION CADENCE: device inventory confirmed exact version
  `0.12.0` build `11`. A 101-second USB sample from the same Uncharted 1
  live-3D run recorded 13 texture-eviction batches, versus 389 batches in 403
  seconds on V0.11. The first overlay sample measured `0.0 FPS` at `2734 MiB`,
  a later sample measured `4.0 FPS` at `3312 MiB`, and a denser jungle scene
  measured `6.9 FPS` at `3074 MiB`. The user could move through that scene and
  observed brief peaks near `12 FPS`, where previous builds could not progress.
- FAIL PHYSICAL / SUSTAINED PERFORMANCE: V0.12 still intermittently returned to
  `0 FPS` and is not playable or promotable. A later 37-second USB sample
  measured normalized CPU between `71.0%` and `79.3%`, stable severe memory
  pressure near `1022-1029 MiB` process headroom, and repeated guest
  `BATCHJOB: Waiting for batch job list 0 to finish` messages. NETISO remained
  idle. This isolates the next candidate to SPU execution/compile scheduling
  rather than transport or another unbounded texture-eviction loop.

V0.13 Uncharted SPU-scheduling candidate:

- Source revision: `8696f054f8f31fde47478364ed633a95ff7fd8bf`
- Name: `ARMSX3-iOS-Core-Test-v0.13.ipa`
- Compressed size: `31,769,699` bytes
- SHA-256:
  `a9af91a5326866217d1cc18d7a2b50ab7a0808bc6e7e7f66379beb10dd9546a6`
- FIX READY / PHYSICAL PENDING: exact title `BCES00065` now resolves automatic
  Mobile SPU Compile Scheduling to enabled after global, database, and custom
  title settings are composed. An explicit user Enabled/Disabled selection
  still takes precedence. On the six-thread A15, the two SPU compiler workers
  therefore use the existing three-thread free floor instead of forcing one or
  two gameplay SPUs into 200-microsecond waits while code compiles.
- DIAGNOSTIC READY / PHYSICAL PENDING: the ten-second performance log now
  reports active `SPU Compilers` and interval `SPU Compile-Throttle Waits`.
  This is a lock-free counter on the existing wait branch; it does not add a
  synchronous log to the SPU hot path. The boot policy log includes the title
  ID and resolved `mobile_spu` value.
- PASS STATIC/PACKAGE: the complete lightweight iOS contract suite, new
  title-default and six-thread scheduling assertions, incremental two-worker
  arm64 core build, serial app build, ZIP readback, deep strict signing, iOS
  15.0 load commands, TrollStore JIT/unsigned-memory/extended-address/
  increased-memory entitlements, version `0.13.0` build `12`, expected core
  exports, and private path/address scans passed. The unsigned checkpoint core
  SHA-256 is
  `1f5f8dd5d97d0f83a28fb499bb19b329fb68d5b219068804b68cd9f26057d939`;
  the packaged ad-hoc signed core SHA-256 is
  `a09b7ac34ca72c2d44a8d8e89d93095439ac25937b7f57c784deec170f3e8785`.
- PASS DISTRIBUTION: the audited IPA was copied to iCloud Drive as
  `ARMSX3-iOS-Core-Test-v0.13.ipa`; Desktop and destination size/hash readback
  are identical.
- REQUIRED PHYSICAL GATE: install these exact bytes, confirm `0.13.0` build
  `12`, and replay the same Uncharted jungle section. Capture boot policy,
  `SPU Compilers`, throttle waits, FPS floor/average/peak, normalized CPU,
  resident memory, eviction cadence, graphics completeness, memory warnings,
  and stability. The candidate passes only with sustained frame progress and
  fewer or shorter zero-FPS stalls; a package or a momentary FPS spike is not
  qualification.

V0.13 Red Dead / lifecycle / NETISO physical evidence:

- PASS PHYSICAL / TRANSPORT: the exact V0.13 package streamed the 9.52 GiB Red
  Dead Redemption GOTY ISO through NETISO without copying it to the phone,
  completed the title installer, reached the Rockstar logo, title menu, and
  real 3D gameplay. This proves the ISO transport and title handoff; it does not
  prove playable performance.
- FAIL PHYSICAL / FIRST STOP: the first Red Dead boot stalled after preparing
  title modules. Stop exceeded the bounded wait, and force-close crashed while
  destroying Vulkan UI-overlay memory. The report was `EXC_BAD_ACCESS` through
  `vk::ui_overlay_renderer::~ui_overlay_renderer`, `vk::image::~image`, and
  `vk::mem_allocator_vma::free`.
- FAIL PHYSICAL / MEMORY: the second boot reused the partial cache and reached
  the game, then iOS killed PID 17217 for `per-process-limit` at 262,539 16-KiB
  pages, approximately 4102 MiB. This is direct jetsam evidence, not an inferred
  out-of-memory result.
- FAIL PHYSICAL / PERFORMANCE: the third warm-cache boot rendered its boot
  screen at 30 FPS and 1827 MiB, then real 3D at approximately 2 FPS and 3031
  MiB. Live logs showed hundreds of Metal and RSX pipeline compilations,
  repeated hard ZCULL synchronization, Vulkan allocator usage up to 142%, and
  process headroom falling to 296-426 MiB. CPU was only about 24% in one sample,
  supporting renderer/cache and scheduling work instead of an interpreter
  fallback.
- FAIL PHYSICAL / BACKGROUND: switching from ARMSX3 to Discord did not pause the
  guest. UIKit deactivation was followed by a memory warning, aborted Metal
  command buffers, and an RSX fatal `VK_ERROR_DEVICE_LOST`. V0.13 has no app
  lifecycle pause/resume handler.
- FAIL PHYSICAL / POST-FATAL STOP: pressing Stop after that device loss produced
  `EXC_CRASH`/`SIGABRT` on the main thread while destroying
  `rsx::reports::ZCULL_control` through the `VKGSRender` typemap teardown. A
  fatal renderer must not enter this known unsafe cleanup path.
- PASS PHYSICAL / 2D CONTROL TITLE: NETISO DuckTales Remastered (`BLUS31368`)
  decrypted, compiled, reached its menu, and ran well enough to serve as a
  transport/input/rendering regression control. It is not demanding-3D proof.
- FAIL PHYSICAL / CFW FAKE-SELF: The Amazing Spider-Man 2 (`BLUS41044`) and
  Teenage Mutant Ninja Turtles: Danger of the Ooze (`BLUS31435`) mounted valid
  NETISO virtual images but failed on `PS3_GAME/USRDIR/EBOOT.BIN` as an invalid
  format. NAS byte inspection proved both are fake-signed debug SELF files with
  a structured `0x900` SELF header and two independently compressed ELF
  segments. V0.14 inflated only the first segment, which produced ELF magic but
  not a complete ELF: the second loadable segment and section-header table were
  missing. DuckTales uses a normal encrypted retail SELF.

V0.14 implementation candidate (physical qualification in progress):

- SUPERSEDED IMPLEMENTATION: V0.14's compressed fake-SELF path bounded one zlib
  stream and checked only ELF magic. Physical Spider-Man 2 and TMNT testing
  proved that was insufficient for structured debug SELF files with multiple
  segments. The complete segment-table repair is recorded after V0.15 below.
- FIX READY: MoltenVK retains pipeline-export MSL as LZFSE instead of raw text.
  Final graphics/compute pipeline-cache use is externally synchronized, and
  iOS atomically checkpoints after 64 new pipelines and 15 seconds when at
  least 1 GiB of process headroom remains. A successful pause requests a forced
  safe-headroom checkpoint, so a later crash cannot discard the entire run.
- FIX READY: Red Dead (US/EU base and GOTY), GTA V (US/EU), and Uncharted 1-3
  (known US/EU IDs) receive the database-layer mobile profile: 50% internal
  resolution, two shader compiler workers, and multithreaded RSX. Uncharted 2
  retains its one-instruction PPU-trap compatibility setting. User per-title
  configuration continues to override this database layer.
- FIX READY: the same demanding-title set enables mobile SPU scheduling so
  compilation cannot consume every useful A15 worker while the game is live.
- FIX READY: UIKit deactivation synchronously releases player-one input and
  pauses a running guest before Metal is backgrounded. Foreground activation
  resumes only a session paused by that lifecycle path. A detected fatal core
  error blocks the physically proven unsafe renderer teardown instead of
  re-entering the ZCULL double-free path.
- RESEARCH FALLBACK ONLY: a no-runtime-JIT route remains documented as static
  ahead-of-time recompilation with interpreter fallback, similar in concept to
  RecompCore. It is not a drop-in PS3 solution and is intentionally deferred
  while native ARM64 PPU/SPU recompilers work. Full interpretation is excluded
  from the performance path.
- REQUIRED: build/sign/install exact V0.14 bytes and physically run cold/warm
  Red Dead, GTA V, Uncharted 1/2/3, DuckTales, Spider-Man 2, and TMNT. Record
  FPS, memory/headroom, cache load/save, graphics, app-switch resume, normal
  Stop/relaunch, and every title's final boot line. Nothing above is physical
  qualification until that matrix is observed on the phone.

V0.14 signed candidate artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.14.ipa`
- SHA-256:
  `f2b062635e67ee37fc1b79711e3903a794bfd698e699f95b5115131842070313`
- PASS STATIC: bounded contract tests, incremental two-worker core build, and
  serial UIKit app build completed. The package contains arm64 app/core Mach-O
  binaries targeting iOS 15.0 and exports the expected core ABI.
- PASS STATIC: strict deep signature verification and all required TrollStore
  JIT, unsigned-executable-memory, extended-address-space, and increased-memory
  entitlements passed. Archive integrity and private-path scans also passed.
- PASS STATIC: bundle readback reports `0.14.0` build `13`; both explicit PS3
  icon PNGs are present at 120x120 and 180x180 without alpha or an accidental
  TIFF/checkerboard asset.
- PASS TRANSFER: repository artifact, Desktop copy, and iCloud Drive copy have
  the exact SHA-256 above. V0.13 is retained as the single rollback candidate;
  obsolete V0.1-V0.12 standalone ARMSX3 IPAs were removed from Desktop.
- PASS PHYSICAL / EXACT PACKAGE: the user installed these exact V0.14 bytes
  through TrollStore and launched them on the physical iPhone 14,3 running
  iOS 15.3.
- PASS PHYSICAL / REGRESSION CONTROL: DuckTales Remastered reached gameplay and
  the user played through the first boss with near-full-speed behavior. This is
  a strong transport/input/rendering control, not demanding-3D qualification.
- PARTIAL PHYSICAL / RED DEAD: Red Dead Redemption reached menus at roughly
  8-12 FPS with spikes to 30 FPS and its initial live-3D boat scene at roughly
  6-8 FPS, improving on the prior 0-2 FPS result. It remains a failure against
  the 30 FPS target: moving video was blurred, train geometry rendered
  incorrectly, and audio crackled under load. The trace recorded repeated
  ZCULL hard synchronizations, texture-cache eviction, Vulkan allocation above
  the configured budget, and only about 706-797 MiB of process headroom.
- PASS PHYSICAL / NORMAL STOP-RELAUNCH: the Red Dead session stopped without a
  fatal renderer/device-loss line, and the same app process started the next
  title. Teardown still emitted private Metal warnings and a sub-second hang
  trace, so lifecycle cleanup remains under observation.
- PASS PHYSICAL / TOY STORY MANIA: the NETISO title compiled, entered its
  free-play mode, and held its 30 FPS cap; DuckTales had held 60 FPS. The user
  reported normal operation after graphics appeared. The first free-play
  transition produced audio over a temporarily black screen while a dense burst
  of Metal/RSX shaders compiled, so shader warm-up presentation remains open.
  The tested mode was not genuine interactive 3D and is excluded from the
  moderate-3D baseline.
- FAIL PHYSICAL / GTA V CHILD LOADER: the GTA V NETISO reached the Duplex intro,
  wrote and exit-spawned `/dev_hdd1/duplex.self`, then remained on a black
  `Loading` screen. The child process requested
  `/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN` and received `CELL_ENOENT`; the
  streamed disc remained correctly mounted at `/dev_bdvd/PS3_GAME`. A V0.15
  compatibility policy is being added to redirect only that legacy path when
  an iOS exit-spawn child has an active virtual ISO. Normal installed games and
  non-child processes are explicitly excluded, and the redirected path keeps
  the BDVD read-only mount semantics.
- FAIL PHYSICAL / UNCHARTED 3 GRAPHICS: a clean V0.14 process (`PID 19348`)
  reproduced the existing periodic square artifacts in the Uncharted 3 menu
  and added a severe green cast, pink banding, and bright rectangular
  corruption. A physical screenshot captured the overlay at approximately
  `12.0 FPS`, `2734 MiB`, and `NET 0.0 Mbps`, proving that active NETISO
  streaming was not the source. The preceding reused-process boot emitted a
  dense RSX fragment-program failure burst (`Unexpected instruction`, invalid
  registers, bad precision/scale, and unknown opcodes) followed by Metal
  warnings. Forced Multithreaded RSX is the leading V0.14-specific suspect and
  requires an isolated physical candidate; this is not yet a proven fix. A
  subsequent live observation after relaunch explicitly reconfirmed both the
  green hue and block artifacts, with the green hue worse than the pre-V0.14
  rendering.
- FAIL PHYSICAL / UNCHARTED 3 RELAUNCH CLEANUP: exiting the reused V0.14 process
  unloaded the ISO and then terminated with
  `Verification failed (object: 0x0)`. The clean comparison process launched
  afterward, so this teardown failure is separate from the deterministic
  graphics corruption.
- PENDING PHYSICAL: Uncharted 2, Spider-Man 2, TMNT, Toy Story Mania, app
  switch/resume, and sustained thermal/cache-reuse gates remain open. Static
  or partial physical success does not close those title-specific gates.

V0.15 focused compatibility candidate:

- FIX READY: iOS guest filesystem calls now redirect the legacy
  `/dev_hdd0/game/PS3_GAME` prefix to `/dev_bdvd/PS3_GAME` only when the caller
  is an exit-spawned child process and the active BDVD is backed by a virtual
  ISO. This covers wrappers such as GTA V's `duplex.self` without copying the
  streamed title or changing normal installed-game paths. Redirecting before
  mount lookup preserves the BDVD read-only contract.
- PASS STATIC: a dedicated policy contract verifies exact-prefix and child
  paths, rejects lookalike prefixes, and rejects initial-process or non-virtual
  disc sessions. The full bounded iOS contract suite and the real two-worker
  `RPCS3Core` incremental build pass.
- REQUIRED: package/sign/install the exact V0.15 artifact, then verify that the
  log contains the redirect diagnostic and GTA advances beyond the prior black
  `Loading` screen. Also verify a normal NETISO title and a local installed
  title to prove the compatibility path does not bleed into other sessions.

V0.15 signed candidate artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.15.ipa`
- Source commit: `b9dad4243b18719e0a44f8b161681fbf8e800fc8`
- SHA-256:
  `9b916cf174fda22b46c446b12f0e5f040e0148abf14a503a007b5ee9f858fa8a`
- PASS STATIC: archive integrity, strict deep signing, required TrollStore
  JIT/unsigned-memory/extended-address/increased-memory entitlements, arm64
  app/core binaries, iOS 15.0 minimum, core ABI export, version `0.15.0` build
  `14`, exact opaque 120/180 px PS3 icons, and private-path scans passed.
- PASS TRANSFER: repository artifact, Desktop copy, and iCloud Drive copy have
  the exact SHA-256 above. V0.14 remains available as the immediate rollback.
- PENDING PHYSICAL: install these exact bytes and verify the GTA child-loader
  redirect plus normal NETISO/local-title isolation. Package success is not
  gameplay qualification.

Post-V0.15 structured debug SELF repair candidate:

- FIX READY: structured debug SELF files now bypass the legacy single-stream
  fake-header shortcut. The core reads the embedded ELF/program/segment/section
  tables, reconstructs every declared file segment at its ELF offset, inflates
  only the segment's bounded zlib range, requires exact compressed and output
  sizes, restores the section-header table, and rejects missing or malformed
  segment payloads. Legacy raw debug SELF and encrypted retail SELF paths remain
  isolated.
- PASS STATIC / NAS FORMAT PROOF: Spider-Man 2 has two compressed segments
  (`8501370 -> 20365416` bytes and `148619 -> 535152` bytes) and reconstructs to
  `20942048` bytes. TMNT has two compressed segments
  (`2617142 -> 10497312` bytes and `121748 -> 398920` bytes) and reconstructs to
  `10957596` bytes. Both embedded ELF64 layouts and section tables validated
  against the authoritative NAS files without writing or changing game media.
- PASS STATIC: the bounded iOS contract suite and a two-worker incremental
  `RPCS3Core` build pass. Physical Spider-Man 2 and TMNT boot/gameplay remain
  required before this compatibility repair can be promoted.

V0.16 focused compatibility/render-isolation candidate:

- FIX READY / GTA: includes V0.15's narrowly scoped exitspawn
  `/dev_hdd0/game/PS3_GAME` to `/dev_bdvd/PS3_GAME` redirect for streamed-disc
  wrappers such as GTA V's `duplex.self`.
- FIX READY / STRUCTURED DEBUG SELF: includes the complete two-segment
  Spider-Man 2/TMNT reconstruction described above.
- EXPERIMENT READY / UNCHARTED 3: `BCES01175` and `BCUS98233` retain the `50%`
  internal-resolution and two-shader-worker mobile limits but no longer force
  Multithreaded RSX. V0.14 introduced that forced offload at the same time the
  clean physical run gained its severe green/pink corruption. This is an
  isolated A/B candidate, not a claimed renderer fix; RDR, GTA, and Uncharted
  1/2 keep their existing profiles.
- PASS STATIC: the complete bounded iOS contract suite and incremental
  two-worker `RPCS3Core` build pass. Physical Uncharted 3 menu/gameplay, GTA
  post-Duplex, Spider-Man 2, and TMNT gates remain required.

V0.16 signed candidate artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.16.ipa`
- Source commit: `609c4f4b230a6695dc1d4af34a6b3db455f21f4b`
- SHA-256:
  `9c141f0d9a5c65f0b3350bd2c25723bb0de5d3c2a1ed898adad70fdd8f8f0f4b`
- PASS STATIC: archive integrity, version `0.16.0` build `15`, strict deep
  signing, required TrollStore JIT/unsigned-memory/extended-address/increased-
  memory entitlements, arm64/iOS 15.0 metadata, bounded contract tests, and the
  two-worker real-core build passed.
- PASS TRANSFER: repository artifact, Desktop copy, and iCloud Drive copy have
  the exact SHA-256 above. V0.14 and V0.15 remain available for controlled
  rollback/comparison.
- PENDING PHYSICAL: install these exact bytes and inspect the Uncharted 3 menu
  before gameplay. Absence of the V0.14 green cast would isolate forced
  Multithreaded RSX as that regression; the older square artifacts remain a
  separate renderer failure until physically disproved. GTA post-Duplex and
  Spider-Man 2/TMNT boot remain independent gates.

V0.16 physical Uncharted 3 result and V0.17 cache-isolation candidate:

- PASS IDENTITY: the connected phone reported installed version `0.16.0` build
  `15` for `com.thec0de.armsx3ios`; this was not a stale-package observation.
- FAIL PHYSICAL: a direct device screenshot of `BCES01175` reproduced the same
  severe green field and pink banding at approximately `14 FPS`, `2767 MiB`,
  and `NET 0.0 Mbps`. Removing forced Multithreaded RSX alone therefore did not
  visibly repair the already-running session.
- CACHE CONFOUND: TrollStore upgraded the app in place and retained V0.14's
  title shader records plus global Vulkan driver pipeline cache. V0.16 could
  therefore recompile/reuse previously persisted corrupt graphics programs;
  it did not provide a clean shader A/B despite the source-level profile split.
- FIX READY FOR V0.17: only Uncharted 3 uses a new on-disk shader-cache
  namespace and a new driver-pipeline-cache file. This forces one graphics-only
  reconstruction while preserving firmware, PPU/SPU objects, saves, trophies,
  game data, and every other title's caches. Multithreaded RSX remains disabled,
  while 50% resolution and two shader workers remain unchanged.
- REQUIRED: package/install the exact V0.17 bytes, verify the generation-2 cache
  diagnostic, and inspect the menu before gameplay. If the green cast remains,
  cached graphics are ruled out and the next isolated delta is MoltenVK shader
  compression; periodic square artifacts remain a separate renderer defect.

V0.16 physical Uncharted 1 follow-up:

- FAIL PHYSICAL: two consecutive U1 attempts terminated back to iOS, including
  the restarted run after it reached live gameplay. No new title-specific crash
  report was available after either collection attempt, so renderer fatal versus
  external memory-pressure termination remains unresolved.
- FAIL PERFORMANCE: restarting the app reached live U1 gameplay. A direct
  device screenshot captured a momentary `14.0 FPS`, `3268 MiB`, `NET 0.0 Mbps`,
  and only `536 MiB` reported process headroom. The user confirmed gameplay FPS
  was otherwise materially unchanged, so this is not an improvement claim.

V0.17 signed graphics-cache-isolation artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.17.ipa`
- Source commit: `216cea564e8b57063758ebbe8298600591718022`
- SHA-256:
  `d41d7232bf5399f09ddede3f19e1184bc4e51abff6cf0efb759e069c0515ea05`
- PASS STATIC: archive integrity, version `0.17.0` build `16`, strict deep
  signing, required TrollStore JIT/memory entitlements, arm64/iOS 15.0
  metadata, generation-2 shader/pipeline-cache strings, bounded contracts, and
  the two-worker real-core build passed.
- PASS TRANSFER: repository artifact, Desktop copy, and iCloud Drive copy have
  the exact SHA-256 above. V0.16 remains the immediate rollback.
- PENDING PHYSICAL: install these exact bytes, launch U3 only to its menu, and
  confirm the generation-2 graphics rebuild plus green/pink/block result before
  spending time on gameplay.

V0.17 physical result and V0.18 pre-regression renderer candidate:

- PASS IDENTITY: the connected phone reported installed version `0.17.0` build
  `16`; the exact candidate was running.
- FAIL PHYSICAL: a direct screenshot again captured the severe green field and
  pink banding in `BCES01175` at approximately `12.1 FPS`, `2669 MiB`,
  `NET 0.0 Mbps`, and `651 MiB` reported headroom. The user also confirmed the
  existing block artifacts remain.
- INVALID CACHE GATE: the user saw no shader rebuild, and the generation-2
  diagnostic was not captured before renderer startup. The title-scoped cache
  selector can run before title-ID publication, so V0.17 did not prove that its
  fresh namespace was selected.
- FIX READY FOR V0.18: every iOS title now uses graphics cache generation 3,
  independent of title-ID timing, and the driver cache uses a new global iOS
  filename. The explicit LZFSE MoltenVK shader-source compression added in
  V0.14 is removed, restoring the pre-V0.14 behavior that had correct U3 color.
  Firmware, PPU/SPU objects, saves, trophies, and game data remain untouched.
- CONTROL READY FOR V0.18: the standalone app exposes a confirmed
  `Rebuild Graphics Caches` action. ABI 32 removes every title's shader cache
  plus legacy/current Vulkan pipeline-cache files only while emulation is fully
  stopped, reports measured reclaimed bytes, and preserves all CPU/content/user
  data. This also covers NETISO titles whose IDs are unknown before first boot.
- REQUIRED: package/install exact V0.18 bytes, capture both generation-3 and
  pre-V0.14-compression diagnostics, and inspect the U3 menu before gameplay.

V0.18 signed pre-regression/cache-control artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.18.ipa`
- Source commit: `7a5b5bc2d385aa17e9cd92608bacccb8a27b2147`
- SHA-256:
  `a4a983ef74dfa8788f48935f9854077a500d9595d46df398f39bd0173dacc180`
- PASS STATIC: archive integrity, version `0.18.0` build `17`, strict deep
  signing, TrollStore JIT/memory entitlements, arm64/iOS 15.0 metadata, ABI 32
  cache-control export, app control strings, generation-3 cache diagnostics,
  pre-V0.14 compression diagnostic, bounded contracts, two-worker core build,
  and serial Xcode build passed against the packaged bytes.
- PASS TRANSFER: repository artifact, Desktop copy, and iCloud Drive copy have
  the exact SHA-256 above. V0.17 remains the immediate rollback.
- PENDING PHYSICAL: with emulation stopped, press `Rebuild Graphics Caches`,
  confirm the measured-success message, then launch U3 and capture diagnostics
  plus the first menu frame. An empty cache need not display a preload progress
  bar; shaders compile on demand because no prior records remain to preload.

V0.2 artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.2.ipa`
- Compressed size: `27,936,522` bytes
- SHA-256:
  `baf43b293635e38f5665afe54e14f5b95eb4160f53766e7937a1adcaa0c9b65c`
- PASS: exact artifact transferred to the connected iOS 15.3 phone's
  `Downloads/ARMSX3-iOS-Core-Test-v0.2.ipa` path.
- EXPECTED: normal `installd` rejected the ad-hoc TrollStore signature with
  `ApplicationVerificationFailed`; install must occur through TrollStore.

V0.3 device-test artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.3.ipa`
- Compressed size: `27,936,029` bytes
- SHA-256:
  `c00aca6ff9e2964353df2542840ef9012749ec9945a67fd68df16368ece86bd7`
- PASS: incremental core rebuild completed with two jobs; the UIKit app built
  with one job and linked the updated real core.
- PASS: strict deep signing, required TrollStore entitlements, arm64/iOS 15.0
  deployment, ABI export, archive integrity, bundle ID, version `0.3.0` build
  `2`, and `UIFileSharingEnabled` readback passed.
- PASS WITH TRACEABILITY FOLLOW-UP: the user installed and launched this
  functional V0.3 package through TrollStore and physically ran two titles.
  The exact installed-file hash was not read back from the disconnected phone.

V0.3 public checkpoint artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.3.ipa`
- Compressed size: `27,936,058` bytes
- SHA-256:
  `b065dcc7bfe06c87dd4a601bbfc1784d43c91e2da78f33104cc0d09a2834c14e`
- PASS: a clean two-worker core rebuild and one-worker app build completed with
  compiler prefix maps in the app, core, and FFmpeg build contracts.
- PASS: independent extraction/readback verified archive integrity, deep strict
  signing, required TrollStore JIT/memory entitlements, arm64 app/core binaries,
  iOS 15.0 minimum, bundle ID `com.thec0de.armsx3ios`, version `0.3.0` build `2`,
  file sharing, and zero private `/Users/...` or `/NAS/...` strings across every
  packaged executable.
- PENDING: the path-scrubbed artifact is runtime-equivalent to the installed
  device-test artifact but its exact bytes have not yet been installed and
  physically requalified.

Physical gates:

- PASS: TrollStore installation and launch on the physical iOS 15.3 device.
- PASS: user-selected official firmware imported and read back as version `4.90`.
- PASS: user-selected `Bejeweled 3` ISO imported and enumerated with its clean
  title.
- PASS: `Bejeweled 3` reached its title menu on the physical device, proving
  that this package advances beyond static core initialization and game import.
- PASS WITH FOLLOW-UP: digital controls worked in the title menu. The user
  reported that X may have required multiple attempts; touch hit geometry must
  be measured before input is qualified.
- FAIL: starting gameplay reached `Preparing title modules | Modules 4 of 4 |
  863 MB`, then remained on the same compilation stage for more than 15
  minutes. `g_progr_pdone` advances only after `ppu_initialize2()` returns for
  a module, and the next expected stage is `Linking PPU Modules`; therefore
  4/4 with no stage transition is a finalization stall, not useful progress.
- DIAGNOSTIC: live device telemetry showed the same `ARMSX3iOS` process alive
  and continuously consuming `64.7%` to `66.7%` CPU with no crash, disconnect,
  or Jetsam event. That proves the app survived, not that boot advanced.
- FIX READY FOR V0.3 BUILD: iOS PPU compilation now runs on the boot thread,
  bypassing the iOS 15 named-thread completion wait, and no longer invokes the
  synchronous `malloc_zone_pressure_relief()` sweep before module linking.
  Explicit log markers identify compilation completion and the transition to
  linking. Other platforms retain the existing parallel path.
- FAIL: pressing Stop during the V0.2 stall remained on `Stopping emulation`.
  Both the app's serial core queue and the core's `g_api_mutex` placed Stop
  behind the synchronous boot call, making cancellation unreachable.
- FIX READY FOR V0.3 BUILD: Stop now uses an independent app control queue and
  an iOS-core stop mutex instead of waiting for the boot lifecycle mutex. It
  submits RPCS3's guarded asynchronous graceful-shutdown request immediately;
  callers poll emulation state before relaunch or final teardown.
- PASS: after force-closing the stalled first run, V0.2's second boot reused the
  PPU objects already written to cache, crossed the prior finalization point,
  and rendered the real `Bejeweled 3` game-selection screen. A direct device
  screenshot and live core logs showed active RSX shader compilation, SPU
  execution, guest filesystem access, and sustained process execution; the
  user confirmed the game works.
- PASS: the installed V0.3 package compiled the title-specific PPU modules for
  another game in the Bejeweled 3 collection and reached live `Zuma` gameplay
  on the physical iOS 15.3 device. This proves a previously uncached title can
  cross the V0.2 finalization point; it does not yet qualify full clean-install
  first boot because firmware and other title caches remained on the device.
- FAIL: rotating the physical device during Zuma gameplay left the title at
  `0 FPS` and apparently frozen. Restarting the app recovered immediately and
  relaunched the game with its compiled cache intact. Rotation-safe drawable
  and Metal-surface resizing is required before orientation is qualified.
- PASS WITH FOLLOW-UP: Stop did not complete against the orientation-frozen
  session, but after restart the same V0.3 Stop action exited running gameplay
  successfully. Cancellation during compilation/frozen rendering and measured
  return latency remain open gates.
- FAIL: the current digital direction control is rigid and provides no diagonal
  analog motion. Replace it with a true continuous virtual stick while retaining
  a distinct D-pad option for titles that require digital input.
- FAIL WITH FIX READY FOR V0.3 BUILD: the user reported poor touch-button
  detection during gameplay. The test controls were inside a `UIScrollView`
  that delayed and cancelled content touches, and their maximum visible size
  was 44 points. V0.3 disables scroll cancellation, uses exact non-overlapping
  44-54 point visible/button frames, increases cluster separation, enables
  simultaneous controls, and adds a pressed-state scale response. Physical
  multi-touch qualification remains pending.
- PENDING: capture the explicit on-screen LLVM self-test result
  `42 * 3 + 7 = 133`; downstream PPU compilation is positive JIT evidence but
  is not a substitute for that exact gate.
- PASS: real gameplay rendering is physically proven for Bejeweled 3 and Zuma.
- PASS PHYSICAL: v0.4's adaptive path cold-compiled all 100 Walking Dead PPU
  modules with three direct workers, transitioned through linking, and reached
  a live guest loop. Uncharted 2 independently selected three workers for 111
  cold modules; its final transition remains pending.
- PENDING: audio accuracy, sustained FPS, thermals, V0.3 second-boot cache
  reuse, multi-touch accuracy, Stop during compilation, clean Stop/relaunch,
  and XMB evidence.

The current result is a physically launched real-core IPA with local Bejeweled
3/Zuma gameplay and physical remote NETISO execution through a live Walking
Dead guest loop. GTA V reached its child-executable handoff; Uncharted 2 reached
real media threads before a fatal PPU trap; Uncharted 3 reached live gameplay
with visible graphical glitches in V0.5. None is sustained demanding-3D proof.
V0.6 is the audited single-mount/Uncharted compatibility candidate;
qualification remains open until its exact bytes pass the one-VISO-build NAS
gate, prompt physical input, Stop/relaunch, intermittent-network recovery, Red
Dead direct-stream, sustained FPS, renderer accuracy, audio, thermals, and
cache-reuse gates.

## Storage and network-disc checkpoint

- PASS: the live private-NAS standard `ps3netsrv` endpoint on port `38008`
  accepted NETISO directory, stat, open, and random-read commands from an
  independent client probe.
- HISTORICAL V0.3 FAIL: importing Red Dead Redemption requires a full local copy and the
  device reported `5.52 GiB more needed`. This is the physical storage failure
  that the read-only NETISO virtual filesystem must eliminate; no workaround is
  claimed in the current IPA.
- PASS: the server exposes `GAMES`, `PS3ISO`, `PS2ISO`, `PSXISO`, and `PSPISO`.
  `GAMES` is the extracted PS3-title root; the other roots retain their named
  formats and must not be flattened together.
- PASS: `/PS3ISO/Red Dead Redemption - Game of the Year Edition.iso` reported
  `10,218,897,408` bytes and returned exact random reads at the beginning and
  midpoint of the image.
- EXPECTED FAILURE: the phone reported approximately `3.88 GiB` immediately
  available and `6.17 GiB` total data available. The current importer requires
  free space for a complete local copy, so the 9.52 GiB Red Dead ISO cannot be
  imported on that device.
- PHYSICAL PARTIAL PASS: v0.4's read-only NETISO virtual filesystem booted both
  extracted and ISO titles while leaving saves, patches, PPU/SPU objects,
  shaders, and metadata local. Red Dead itself still requires a direct `[NAS]`
  row boot; the local `Import` button intentionally requires full-copy space
  and is not the NETISO path.
- REQUIRED: EmuHub's admin panel remains authoritative for managed host paths,
  Docker bind mounts, source ordering, and enable/disable state. See
  `PS3_NETWORK_DISC_DESIGN.md`.
