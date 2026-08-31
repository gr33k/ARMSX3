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
- FAIL PHYSICAL / CORE FATAL: after the V0.17 Uncharted 3 session was left
  running, a direct device screenshot showed `0.0 FPS`, `3880 MiB`, and
  `NET 0.0 Mbps 1398 MiB R0`, followed by `[Core:1] SPU[0x2000100] Thread
  (highCellSpursKernel2) [0x0203c]: Thread terminated due to f...`. The failed
  session remained foreground and no newer ARMSX3 CrashReporter `.ips` existed,
  so this is a caught RPCS3 SPU fatal that paused emulation, not evidence of a
  fresh top-level iOS process crash or Jetsam. The overlay truncates the fatal
  suffix; `ARMSX3-last-session.log` could not be extracted because House Arrest
  rejects the TrollStore app's `ApplicationType=System` classification.
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

V0.18 physical Uncharted 3 result:

- PASS IDENTITY: Installation Proxy reported exact installed version `0.18.0`
  build `17` while the test was running.
- PASS ACTION / CACHE ISOLATION: the user invoked `Rebuild Graphics Caches`
  while stopped before launching U3. The measured deletion message was not
  captured over USB, but this exact build independently selects global graphics
  cache generation 3 and `vk_pipeline_cache_ios_g3.bin`; older generations
  cannot be consumed by this run. Fresh compilation activity followed during
  boot, so this was not a stale V0.17 process observation.
- FAIL PHYSICAL / MENU: a direct device screenshot reproduced the severe
  green/pink cast and rectangular artifacts on the first U3 title frame at
  approximately `8.0 FPS`, `2684 MiB`, and `NET 0.0 Mbps 687 MiB R0`.
- FAIL PHYSICAL / GAMEPLAY: a second direct screenshot reproduced the same
  full-frame green corruption and pervasive box artifacts in live gameplay at
  `0.0 FPS`, `3571 MiB`, and `NET 50.3 Mbps 1241 MiB R0`. The transport was
  actively delivering data with zero reconnects, so this is not a missing-media
  or NETISO reconnect explanation.
- FAIL PHYSICAL / MEMORY PRESSURE: UIKit emitted memory warnings at `16:12:03`
  and `16:12:07` while the corrupted gameplay session remained live. No
  top-level crash was required to establish this pressure failure.
- ROOT-CAUSE NARROWING: restoring pre-V0.14 MoltenVK compression behavior,
  disabling forced U3 Multithreaded RSX, and isolating both shader and driver
  caches did not repair either graphics defect. The green/pink cast remains a
  V0.14-era regression, while the box artifacts predate V0.14. The next
  candidate must restore only U3's pre-V0.14 rendering profile and required RSX
  accuracy flags without changing the better-performing U1/U2 paths.
- FIX READY FOR V0.19: exact U3 IDs `BCES01175` and `BCUS98233` now use native
  100% resolution, one serialized shader compiler worker, Multithreaded RSX
  off, color-buffer read/write on, accurate RSX reservation access on, and
  asynchronous texture streaming off. U1, U2, Red Dead, GTA V, and unprofiled
  titles retain their prior game settings. A post-boot diagnostic reports every
  effective value after custom-config resolution; the prepared database profile
  alone is not accepted as proof that these settings reached the renderer.
- CACHE CONTROL FOR V0.19: iOS graphics cache generation 4 and
  `vk_pipeline_cache_ios_g4.bin` guarantee that the changed U3 rendering policy
  cannot consume V0.18 shader or driver records. This globally changes only the
  derived-cache namespace; firmware, CPU objects, saves, and title data remain
  intact.
- PASS STATIC SOURCE: the complete bounded iOS contract suite and incremental
  two-worker `RPCS3Core` build pass. The resulting core is arm64, targets iOS
  15.0, and exports ABI 32 including graphics-cache control.
- REQUIRED PHYSICAL GATE: install exact V0.19, capture the complete effective
  U3 profile and generation-4 diagnostics, and inspect the first menu frame.
  Do not enter gameplay until color and memory headroom pass because V0.18
  already emitted memory warnings at `3571 MiB` under the lower 50% scale.

V0.19 signed Uncharted 3 accuracy artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.19.ipa`
- Source commit: `c95830636955c8ab13d69e9bd991751f5dea6c18`
- Compressed size: `31,845,374` bytes
- SHA-256:
  `d64a344951bbf2499d297f5def925015a7900d11266125b68b63340454726d3e`
- PASS STATIC: archive integrity, version `0.19.0` build `18`, strict deep
  signing, TrollStore JIT/memory entitlements, arm64/iOS 15.0 metadata, ABI 32
  graphics-cache control, generation-4 shader/driver cache strings, prepared
  and effective U3 profile diagnostics, private-path scan, bounded contracts,
  two-worker core build, and serial Xcode build passed against the packaged
  bytes.
- PASS TRANSFER: repository artifact, Desktop copy, and iCloud Drive copy have
  the exact SHA-256 above. V0.18 remains the immediate rollback.
- PASS PHYSICAL / EXACT INSTALL IDENTITY: the connected iPhone14,3 running
  iOS 15.3 reported bundle `com.thec0de.armsx3ios`, version `0.19.0`, build
  `18`. This is the exact v0.19 qualification lane above; no later package was
  substituted during the test.
- PARTIAL PHYSICAL / U3 COLOR ONLY: Uncharted 3 no longer has the persistent
  green/pink full-frame cast seen in v0.18. The first title/menu frames ran at
  roughly 10-14 FPS with a process footprint around 2.8 GiB.
- FAIL PHYSICAL / U3 TRANSIENT ATTACHMENTS: three adjacent USB framebuffer
  captures proved intermittent stale rectangular contents rather than a
  permanently corrupted source texture. One frame contained a large stale
  yellow rectangle over the lower-left render area, another contained a green
  horizontal block at the upper-right edge, and an adjacent frame could be
  visually clean. Continued gameplay also showed morphing/warping plus
  intermittent green and white squares near the top of the frame. Generation-4
  cache isolation and the restored U3 accuracy profile therefore did not fix
  the resolve/attachment defect.
- FAIL PHYSICAL / DEMANDING 3D CONTROL: Red Dead Redemption title `BLUS30758`
  reached live gameplay at exactly `2.0 FPS`, `3389 MiB`, NET `0.0 Mbps`,
  `963 MiB` transferred, reconnect count `R1`. UIKit emitted
  `Received memory warning` while the session was active. V0.19 is not a
  general 3D-performance improvement and is not releasable for demanding PS3
  gameplay.
- FAIL PHYSICAL / U1 CONTROL: Uncharted 1 held 60 FPS in startup video and the
  menu, then collapsed when live 3D gameplay began and terminated the app. A
  clean second launch was started to distinguish warmed caches from sustained
  gameplay pressure. This transition is the required profiler boundary; menu
  FPS must never be reported as gameplay performance.
- FAIL PHYSICAL / IN-GAME LLVM PRESSURE: two exact v0.19 iPhone resource
  reports recorded `45,002` wakeups in 50 seconds (`897 wakeups/sec`) and
  `45,004` wakeups in 58 seconds (`781 wakeups/sec`) against iOS's reported
  `150 wakeups/sec` limit. Both reports said `Action taken: none`; sampled
  footprint grew from `191.38 MB` to `1173.70 MB` in the first report and from
  `563.44 MB` to `857.17 MB` in the second. The report UUID matched the
  packaged v0.19 `libRPCS3Core.dylib` UUID
  `E921A37A-F8DF-3062-9A6F-706C92421F5D`. Symbolizing the hottest sampled
  chain resolved `ios_thread_worker::run` through `run_recoverable_llvm`,
  `llvm::MCJIT::generateCodeForModule`, `emitObject`, the legacy pass manager,
  machine scheduling, and greedy register allocation. This proves expensive
  PPU LLVM compilation remained active during the sampled gameplay interval;
  it does not by itself attribute every reported wakeup to LLVM. V0.21 must
  move cacheable PPU compilation outside live gameplay and compare the same
  title's wake rate, frame rate, and audio pacing before accepting the change.
- NEXT MEASUREMENT GATE: do not stack more title-profile guesses. Instrument
  cycle-weighted PPU/SPU/RSX CPU work, MoltenVK command encoding/submission,
  actual Metal command-buffer execution, shader conversion/compilation,
  MoltenVK GPU allocation, and iOS process headroom. Use RDR, U1, and U3 on
  this same A15 lane to decide whether a direct Metal RSX backend can remove
  the dominant bottleneck or whether PPU/SPU emulation is already the ceiling.

V0.20 signed PS3 3D profiler artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.20.ipa`
- Source commit: `bf40d9592206f175c808ab3fbf017ab29c4b1148`
- Profiler implementation commit:
  `3cd1d12a868c8f29ed15a1e3289566cd1f6301ae`
- Compressed size: `31,848,919` bytes
- SHA-256:
  `a3e32a7d37d4f8adaf3e829cc6a56cb267086536a590d75f724882c3705a746f`
- PASS STATIC SOURCE: the complete bounded iOS contract suite, incremental
  two-worker `RPCS3Core` build, and serial UIKit build pass. ABI 33 adds
  one-second PPU/SPU/RSX/other CPU, iOS headroom, MoltenVK encode/wait/submit,
  actual Metal execution, shader/pipeline compile, and sampled RSX frame
  telemetry without changing game profiles, resolution, JIT mode, or cache
  behavior. Build identity now derives its ABI directly from
  `RPCS3_IOS_ABI_VERSION`, and a compile-time regression assertion requires
  the exact valid-JSON `"abi":33,"frontend"` boundary and profiler capability
  string.
- PASS PACKAGE: archive integrity, version `0.20.0` build `19`, bundle ID
  `com.thec0de.armsx3ios`, strict deep signing, TrollStore JIT/unsigned-memory/
  extended-address-space/increased-memory entitlements, arm64 app/core, iOS
  15.0 minimum, ABI exports, private-path scan, and embedded valid ABI-33 JSON
  identity pass against the packaged bytes.
- PASS TRANSFER: the repository artifact and iCloud Drive copy have the exact
  SHA-256 above. V0.19 remains the immediate rollback.
- REJECTED PREDECESSOR BYTES: the earlier `c64f4eb...` package advertised ABI
  32 in its identity JSON, and the provisional `af4b94cd...` package emitted
  invalid JSON with `"abi":33u`. Neither package is the current repository or
  iCloud artifact and neither may be installed or used as evidence.
- OBSERVATIONAL CANDIDATE: V0.20 is not an FPS claim. It exists to identify the
  first optimization for V0.21. Telemetry labels and decision gates are fixed
  in `PS3_3D_PERFORMANCE_PLAN.md`.
- REQUIRED PHYSICAL ORDER: fully close V0.19, install only the exact V0.20 hash,
  then start U1 from a fresh process. Capture at least 10 seconds of stable menu
  telemetry and 30 seconds of live gameplay telemetry plus visual/audio/crash
  result. Repeat from fresh processes for RDR and U3. Only after all isolated
  samples pass collection, run U3 -> clean stop -> U1 to measure retained
  memory/device state. Do not mix sequential-title pressure into the isolated
  performance baseline.
- PASS PHYSICAL / EXACT IDENTITY AND PROFILER: the connected iPhone14,3 on
  iOS 15.3 ran exact version `0.20.0` build `19`. U1 title `BCES00065` held
  approximately `60 FPS` in its menu/video path at `1017-1517 MiB`, with
  stable NETISO (`36 MiB`, zero reconnects) and zero sampled shader/pipeline
  compiles. The profiler therefore distinguishes the fast presentation path
  from real gameplay as intended.
- FAIL PHYSICAL / REPEATABLE U1 TERMINATION: two isolated U1 launches returned
  to iOS after entering real 3D. The first gameplay transition fell through
  `28 FPS` at `1837 MiB` to `6 FPS` at `3373 MiB` with only `723 MiB` process
  headroom. The warm-cache rerun loaded the cached PPU object, maintained a
  clean NETISO connection, and still fell from `18 FPS` at `2098 MiB` through
  `7.9`, `4`, `6`, `10`, and `2 FPS` samples while reaching `3367 MiB` and
  `729 MiB` headroom. UIKit memory warnings, texture-cache eviction, and
  GameController daemon interruption accompanied both failures. No new Jetsam
  or top-level crash report was present immediately after the second failure,
  so this is a repeatable memory-pressure termination, not a formally proven
  Jetsam event.
- FAIL PHYSICAL / SIMULTANEOUS GPU, SPU, AND MEMORY PRESSURE: settled live-3D
  samples measured normalized SPU CPU at `49-66%` of six logical cores and
  actual Metal command execution near `1129 ms` in a one-second interval. The
  process emitted severe pressure at `1087 MiB` headroom with the Vulkan
  allocator at `164%`, then exceeded `3.3 GiB`. RSX reached roughly `1876-2425`
  draws per sampled frame and repeatedly found width/height-swapped texture
  interpretations at the same guest addresses. Shader conversion, MSL compile,
  and Metal pipeline compile counters remained zero throughout the sampled
  gameplay. This rules out NETISO and first-use shader compilation as the
  immediate crash cause and makes bounded RSX/unified-memory recovery the first
  V0.21 gate; SPU saturation and direct Metal remain parallel performance work.
- FAIL PHYSICAL / V0.20 WAKE PRESSURE: the exact report
  `ARMSX3iOS.wakeups_resource-2026-08-30-214515.ips` names version `0.20.0`
  build `19`, PID `23524`, core UUID
  `DC8E8EB5-4B4D-322B-A0A4-25256D23AA47`, and `45,001` wakeups in `43`
  seconds (`1042/sec`) against iOS's `150/sec` limit. Symbolization against the
  exact packaged core again resolves `ios_thread_worker::run` through
  `run_recoverable_llvm`, MCJIT object emission, machine scheduling, and greedy
  register allocation. Its `21:44:31-21:45:14` interval primarily covers boot
  and compilation; it must not be misreported as the warm gameplay wake rate.
- V0.21 REQUIRED CHANGE: prevent the measured memory climb before the process
  reaches the approximately `4.1 GiB` allowance, without restoring V0.10/V0.11's
  destructive every-frame texture eviction loop. Record texture, render-target,
  system, scratch, and swapchain allocation pools at pressure transitions, run
  at most one synchronized inactive-texture eviction per pressure episode, and
  require recovery hysteresis before another destructive pass. Re-run the same
  warm U1 scene before spending device time on RDR or U3.
- OBSERVED / MINOR LOADER POLISH: Bejeweled's pre-game shader-loading artwork
  appears off-center while other titles look centered. Source inspection proves
  the base `PIC1` poster uses equal aspect-preserving padding, but a separate
  `PIC0` overlay is intentionally anchored at the two-thirds point by upstream
  `message_dialog::update_custom_background()`. This is loader composition, not
  gameplay viewport drift. Capture Bejeweled's exact assets before deciding on
  a loader-only centering override; do not globally shift gameplay or every
  title's artwork in V0.21.

V0.21 adaptive unified-memory recovery artifact:

- Name: `ARMSX3-iOS-Core-Test-v0.21.ipa`
- Source revision: `0fe4b6d0859fcd39b7cb9cbe9a0354c8ce1d54de`
- Compressed size: `31,848,809` bytes
- SHA-256:
  `62fda2e11269d5851531bedb98973604d94cd2f484e9670628c485d1b9c55ed1`
- FIX READY / ADAPTIVE VRAM: the MoltenVK soft pressure target now uses a
  bounded 20% of reported unified memory rather than a fixed phone ceiling.
  The policy targets approximately `1228 MiB` on a 6 GiB device, `1638 MiB`
  on 8 GiB, `2457 MiB` on 12 GiB, and caps at `3072 MiB` on 16 GiB. The live
  `os_proc_available_memory()` allowance remains authoritative, so installed
  RAM cannot override current iOS process pressure.
- FIX READY / EARLIER BOUNDED RECOVERY: process headroom now enters moderate,
  severe, and fatal pressure at `2048`, `1536`, and `1280 MiB`, with 256 MiB
  hysteresis. iOS no longer applies the desktop tracked-allocation downgrade
  after MoltenVK exceeds its soft unified-memory budget. A fatal transition or
  UIKit warning permits exactly one synchronized inactive-texture eviction;
  repeated fatal requests use the non-destructive severe path until process
  pressure recovers through the severe hysteresis band. This directly avoids
  both V0.20's late `723-729 MiB` reaction and V0.10/V0.11's eviction loop.
- DIAGNOSTIC READY: each iOS pressure transition now reports tracked system,
  render-surface, texture, swapchain, and scratch pools beside process headroom
  and MoltenVK allocator percentage. The next physical run can distinguish
  cache growth from untracked driver/JIT/guest memory without another build.
- PASS STATIC/BUILD: the complete bounded iOS contract suite, focused host/iOS
  VRAM tests, focused pressure-state tests, and incremental two-worker arm64
  `RPCS3Core` build pass. The app was rebuilt serially under the 8 GB Mac RAM
  constraint.
- PASS PACKAGE: archive integrity, version `0.21.0` build `20`, bundle ID
  `com.thec0de.armsx3ios`, strict deep signature verification, TrollStore
  JIT/unsigned-memory/extended-address-space/increased-memory entitlements,
  arm64 app/core, iOS 15.0 minimum, ABI 33 valid build identity, and private
  path/address scans pass against the packaged bytes.
- PASS UNIVERSAL DEVICE CONTRACT: the package declares native device families
  `1` and `2`, requires a full-screen Metal surface, and contains responsive
  stage/controller geometry rather than iPhone compatibility mode. The paired
  benchmark tablet is `iPad14,3`, iPad Pro 11-inch (4th generation, M2),
  128 GB storage, iPadOS 26.3.1, with Developer Mode enabled.
- PASS DISTRIBUTION: the exact repository artifact was copied to iCloud Drive
  as `ARMSX3-iOS-Core-Test-v0.21.ipa`; destination SHA-256 readback matches the
  package hash above. The earlier provisional iPhone-only v0.21 bytes were
  overwritten and must not be used.
- FAIL OBSERVED / REPORT PENDING: U3 terminated V0.20 on the iPhone after the
  U1 runs. At report-collection time the USB hub exposed only the iPad to IOKit
  and libimobiledevice, so the U3 report has not yet been copied or attributed.
  Preserve it on the phone and capture it before another U3 launch.
- REQUIRED PHYSICAL GATES: install these exact bytes on the iPhone and replay
  warm U1 first, recording survival time, FPS, headroom, allocator percentage,
  pool breakdown, destructive-reclaim count, audio, and visual result. Then run
  the identical title/settings/scene on the M2 iPad to establish a hardware
  comparison. A package, install, menu, or pre-rendered video remains
  insufficient evidence.

V0.21 iPad development-install and Universal-JIT qualification:

- PASS DEVICE/INSTALL: the paired `iPad14,3` accepted a development-signed
  V0.21 app with bundle ID `com.thec0de.armsx3ios`, version `0.21.0` build
  `20`, native phone/tablet families, and full-screen presentation. The fresh
  personal-team profile UUID is `28a2a126-fd5d-4c97-ab90-efc42f6a0df9` and
  expires on 2026-09-07; this seven-day install is a benchmark lane, not a
  permanent distribution result.
- PASS PHYSICAL JIT BRIDGE: after mounting the iOS 26 developer disk image and
  attaching LLDB to a start-stopped process, `lldb_universal_jit.py` handled
  every `rpcs3_ios_jit26_protocol_call` page request through debugserver. The
  M2 device selected and prepared 28 16-MiB chunks, or 448 MiB total, before
  sealing the arena. This proves the Universal-JIT page protocol works on the
  connected tablet; it does not prove that a game can boot.
- BLOCKED BEFORE CORE BOOT / EVA: immediately after JIT preparation, static VM
  initialization aborted while reserving RPCS3's 24-GiB direct-map layout
  (8-GiB base/sudo, 12-GiB executable, and 4-GiB static regions). The personal
  development team cannot provision Extended Virtual Addressing, and a manual
  signature that added EVA plus increased-memory entitlements was correctly
  rejected by installation with `0xe8008015` because the profile did not grant
  them. Do not report an M2 performance comparison until installed-profile
  readback contains EVA and the app passes this reservation.
- DEVELOPMENT SUPPORT FILES: `Development.entitlements` records the two memory
  capabilities required by an eligible development profile, but is not a
  default free-team signing path. `lldb_universal_jit.py` is the repeatable
  LLDB/debugserver bridge for the separate iOS 26 Universal-JIT requirement.
- PASS INSTALL / FAIL PROFILE GATE: after SideStore's first refresh completed,
  the exact V0.21 IPA was imported and signed. iOS initially rejected it because
  the free-profile slots were occupied by SideStore, old EmuHub, and the prior
  non-EVA ARMSX3 development install. The prior ARMSX3 container contained no
  user payload (only an empty `games.yml`); it was backed up and removed. The
  replacement then installed as `com.thec0de.armsx3ios.3B67JS22ZN`, version
  `0.21.0`, with a validated profile and `get-task-allow`.
- FAIL INSTALLED ENTITLEMENT READBACK: the SideStore-issued ARMSX3 profile omits
  both `com.apple.developer.kernel.extended-virtual-addressing` and
  `com.apple.developer.kernel.increased-memory-limit`. A physical icon and
  successful installation therefore remain insufficient. Apple's current iOS
  capability matrix does not make EVA available to a free Apple Developer
  account, and this Mac has only the free personal team configured.
- FAIL PHYSICAL LAUNCH / SIDESTORE PROFILE: tapping the installed replacement
  aborted before UI in `asmjit::get_global_runtime()::custom_runtime()` with
  `EXC_BREAKPOINT` / `SIGABRT`; crash evidence is
  `ARMSX3iOS-2026-08-31-001441.ips`. This is not an M2 performance result. Do
  not launch this profile repeatedly or claim iPad qualification until EVA is
  granted or an independently verified compact-memory architecture replaces
  the direct-map requirement.
- NO-PAID-TEAM ROUTES: another free signer (AltStore, Sideloadly, or a different
  SideStore build) cannot repair this profile gate; those tools can provide a
  renewable development signature and debugger-enabled JIT, but Apple's portal
  still omits EVA. The actionable local routes are (1) replace RPCS3's 24-GiB
  fixed direct-map with a measured compact/segmented VM design, or (2) qualify
  the same build on a separate TrollStore/jailbreak-compatible device that can
  preserve the required entitlements. An explicit remote-RPCS3 streaming mode
  is also viable for this iPad, but it is not local emulation and must never be
  presented as a silent native-core fallback. Waiting for a future iPadOS 26
  exploit is possible but is not an engineering schedule. A borrowed eligible
  paid organization/team profile would clear the current test gate without the
  user purchasing membership, but it still depends on paid-team provisioning.
- ORGANIZATION ACCESS CHECK: Xcode recognizes the Apple Developer organization
  team `Netfortris Acquisition Co., Inc`, confirming that the Apple Account is
  associated with a paid organization team. The user's assigned role is
  `Sales`, however, and Xcode marks `Certificates, Identifiers, & Profiles` as
  unavailable. App Store Connect independently shows the same Sales-only role;
  Xcode's usable provisioning cache still contains only free personal team
  `3B67JS22ZN`, and the sole installed development profile remains a seven-day
  `LocalProvision` profile without EVA or increased-memory. This is therefore
  not currently usable paid development access. An authorized organization
  Account Holder/Admin would need to assign an eligible development role and
  grant Certificates, Identifiers & Profiles access; company authorization is
  also required before using an employer-owned team for this project. After
  that change, re-verify the new Team ID and Apple-issued profile entitlements
  rather than assuming the role label fixed the gate.
- CURRENT EXPLOIT-LANE CHECK: TrollStore Lite `2.1.1` is explicitly a
  jailbreak-required package; its implementation depends on jailbreak-provided
  `ldid`, a jailbreak root path, and jailbreak trust-cache handling. It does not
  provide a CoreTrust or jailbreak exploit by itself. Full TrollStore officially
  ends at iOS 17.0, while current Dopamine arm64e support covers all devices only
  through 17.3.1; its iOS 26.0-26.0.1 lane is limited to A12/A13. Palera1n is
  limited to A8-A11. Therefore the connected M2 `iPad14,3` on iPadOS `26.3.1`
  has no currently verified TrollStore, TrollStore Lite, Dopamine, or palera1n
  installation path. Do not install unverified websites/profiles claiming an
  iPadOS 26.3.1 TrollStore jailbreak. Recheck only against the official
  TrollStore, Dopamine, and palera1n projects when support changes.

V0.21 iPhone title observations reported during the 2026-08-30 test session:

- FAIL PHYSICAL / GOD OF WAR POST-LOGO HANG: the title renders four startup
  logos at approximately 60 FPS, then remains at 0 FPS with no visible
  progress. A clean app restart reproduced the same transition, so this is a
  deterministic post-boot title/runtime hang rather than a launcher-only
  failure.
- FAIL PHYSICAL / GRAN TURISMO 6: the title did not load. No device log was
  available for a narrower classification because the USB hub exposed only
  the iPad during this run.
- FAIL PHYSICAL / UNCHARTED 2 LIVE-3D RSX STALL: its animated loading object
  and prerendered sequence displayed correctly at approximately 60 FPS. At the
  live-3D transition the frame became severely green/white-corrupted and then
  reached 0 FPS while sound continued normally. This is evidence that the
  guest/audio path remained alive while frame production or presentation
  stalled; it is not a whole-process freeze and is not a performance pass.
- FAIL PHYSICAL / UNCHARTED 3 CORRECTED CLASSIFICATION: the current build no
  longer has the prior persistent green/pink cast, but transient block and
  white-square corruption remains. Keep this distinct from Uncharted 2's
  green/white live-3D failure.
- FAIL PHYSICAL / LITTLEBIGPLANET SUSTAINED RUN: the title passed its own
  game-data installer and intro video. Skipping the video caused a long
  transition stall that eventually recovered without an app restart. The first
  Sackboy/live-3D view then sustained approximately `12-16 FPS` for a meaningful
  period and appeared visually plausible; the initially unusual scene was
  likely intentional art direction rather than proven render corruption. The
  run ultimately hard-stalled at `0 FPS` and audio stopped as well. This is a
  full emulation/guest stall rather than the renderer-only Uncharted 2 symptom,
  and the title is not qualified. Relaunch recovery remains untested.
- PARTIAL PHYSICAL / XMB: XMB launched on the iPhone. The user heard intermittent
  static during startup, while ordinary menu-navigation click sounds remained
  clean. Several game-list entries displayed `Corrupted Data` icons. It is not
  yet known whether those entries are expected remnants, incomplete installed
  data, or a guest-filesystem/title-registration defect; preserve the exact
  entries and session log before changing install or VFS behavior.
- FAIL PHYSICAL / NEED FOR SPEED CARBON BOOT: the first attempt was launched in
  the same app process immediately after stopping XMB. It reached the EA logo
  and then froze while the debug overlay continued to report `60 FPS`. A second
  attempt after fully quitting and restarting the app stalled at the identical
  point immediately after the EA logo faded. This is a reproducible cold-start
  title/core failure, not evidence of incomplete Stop cleanup; the lingering
  FPS value reflects presentation cadence rather than advancing guest work.
- FAIL PHYSICAL / CARS MATER-NATIONAL CHAMPIONSHIP: the title did not launch.
  The iPhone still did not enumerate through the USB hub, so no matching core
  log was captured and the failure stage remains unclassified.
- PARTIAL PHYSICAL / CARS RACE-O-RAMA: the separate Race-O-Rama title reached
  live rendering and held a consistent `30 FPS` on the iPhone. This is a
  physical performance pass for the tested segment. Purple squares were the
  sole observed defect and are retained as suspected RSX/render artifacts until
  a screenshot or known-good comparison proves they belong to the game. Visual
  accuracy and extended survival remain open; do not merge this result with the
  Mater-National failure above.
- FAIL PHYSICAL / THE SIMPSONS GAME: the title did not launch. Preserve this as
  a separate unclassified boot failure until an iPhone core log is available.
- PARTIAL PHYSICAL / LOST PLANET: the guest HDD installation completed and the
  title reached live 3D on the iPhone. Its initial/pre-game 3D phase was
  reported near `34 FPS`, but visible corruption increased. Interactive 3D
  fluctuated substantially, with a rough `20 FPS` average, observed lows near
  `14 FPS`, and heavier dips while shooting. Simpler live-3D areas reached the
  apparent `30 FPS` target, with brief reported spikes around `34-36 FPS`, and
  were subsequently observed without visible corruption, so the earlier
  glitches are scene-dependent or transient rather than continuous. The run
  was subjectively playable despite its uneven frame pacing and materially
  faster than the
  tested Uncharted and Red Dead Redemption scenes, but sustained full speed and
  renderer correctness are not yet qualified. Use it as a middle-tier
  benchmark between Ratatouille's near-30-FPS result and the heavy-title
  single-digit failures.
- STORAGE REQUIREMENT: streamed source media should remain remote, while
  firmware, saves, shader/PPU caches, and title-required HDD game data may use
  real device capacity up to a measured safety reserve. Do not impose an
  arbitrary small quota or allow optional cache growth to consume space needed
  for a safe iOS update and normal device operation.
- PASS PHYSICAL / RATATOUILLE 3D PERFORMANCE: the first cold run displayed
  title artwork that did not fill the shader-loading viewport, then completed
  PPU compilation and reached interactive 3D gameplay. It initially sustained
  approximately `25-28 FPS`, subsequently reached the apparent `30 FPS` title
  cap, and continued holding near `30 FPS` with only minimal slowdown during
  gameplay. This is the first sustained full-speed real-3D result reported on
  the iPhone. Extended survival, audio, visual accuracy, and input remain open
  before full title qualification. The tested media appears to be an EU
  language build; that content limitation is separate from compatibility.
- CONFIRMED TITLE-SPECIFIC / BEJEWELED 3: the off-center image is confined to
  its pre-game loading wallpaper; other tested title artwork is centered. Do
  not apply a global gameplay or loader viewport shift. Any correction must be
  scoped to Bejeweled's loader composition.
- EVIDENCE LIMIT: these phone observations are direct user/device-overlay
  reports, but no matching iPhone process log was captured because the phone
  did not enumerate through the USB hub. Preserve that distinction when using
  them to choose a renderer candidate.
- PARTIAL PHYSICAL / MODERN-IOS INSTALL PATH: official iloader 2.3.1 was
  checksum-verified, Developer-ID signed, notarized, and run from a read-only
  image. Its default `ani.sidestore.io` backend failed before Apple login with
  `invalid Trust Key (-45003)`; switching to the official
  `https://ani.sidestore.app` mirror cleared that failure. Account login then
  succeeded, iloader signed and physically installed SideStore `0.6.3`, placed
  its pairing file through House Arrest/AFC, and launched it on the M2 iPad.
  Installation Proxy independently reports bundle
  `com.SideStore.SideStore.3B67JS22ZN`, a validated profile, `get-task-allow`,
  and signer `iPhone Developer: gr33k420@gmail.com (D72N562933)`. The user must
  complete SideStore's first refresh before importing ARMSX3. The initial
  SideStore login/2FA attempt failed with a malformed-data error while its saved
  Anisette URL remained the known-bad `https://ani.sidestore.io`; selecting the
  working `.app` mirror allowed login and the first refresh to complete. The
  subsequent ARMSX3 install and installed-profile failure are recorded in the
  iPad qualification section above. Competitor-emulator attempts were stopped
  at the user's direction; do not spend additional App IDs or active slots on
  them.

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

## V0.21 NETISO failed-launch recovery candidate (2026-08-31)

- FAIL PHYSICAL / SERVER PROCESS CRASH: during the live iPhone title sweep,
  `ps3netsrv` segfaulted at `2026-08-31T08:05:02.679791593Z`. The container
  remained running with Docker restart count `0` because its internal s6
  supervisor restarted `/usr/local/bin/ps3netsrv` approximately 5 ms later.
  This proves container-up state is not sufficient NETISO health evidence and
  explains the variable post-failure reconnect window.
- PASS SERVER IDENTITY: the running amd64 container uses
  `shawly/ps3netsrv:latest` config digest `da9a24050be2...`, which matches the
  current Docker Hub amd64 `latest` manifest inspected during this session.
  There was no newer image to pull or deploy.
- ROOT CAUSE / CLIENT LIFECYCLE: the core retained one extracted-folder VISO
  backing after failed inspection, failed boot, and Stop. Initial connect/open
  completed before the backing became reachable from the independent Stop
  path. A blocked open/read could therefore hold synchronous `BootGame` and the
  serial app core queue through repeated 15-second protocol timeouts; the next
  title or Connect + Scan NAS appeared hung even after s6 revived the server.
- FIX READY: NETISO now publishes one active cancellable backing for either an
  ISO or extracted-folder title before connect/open. `connection::cancel()` is
  terminal and calls `shutdown(SHUT_RDWR)` to wake blocked I/O without racing
  descriptor reuse. Failed metadata inspection, failed boot, exception, Stop
  even when RPCS3 already reports stopped, server replacement, disconnect, and
  shutdown all retire the mount. A new boot always cancels stale stopped-state
  backing before inspection and cannot reuse a cancelled connection.
- PASS DETERMINISTIC CONTRACT: a loopback server intentionally withheld the
  NETISO open response. Cancellation woke the blocked client in approximately
  100 ms instead of waiting for the 15-second I/O deadline; a pre-cancelled
  connection also failed closed. `NetISOProtocolCancellationTests` is now part
  of the bounded contract runner.
- PASS STATIC/BUILD: `git diff --check`, the complete bounded iOS contract
  suite, and the incremental two-worker arm64 `RPCS3Core` build pass with the
  recovery changes. This is not yet physical recovery proof.
- PASS PACKAGE / TRANSFER: `ARMSX3-iOS-Core-Test-v0.22.ipa` is version
  `0.22.0` build `21`, `31,857,787` bytes, SHA-256
  `9ac2e18efd7576452258d6f4234f5ea8ebcfbc87cc611e905d25ba4305f3298a`.
  Independent readback passed ZIP integrity, deep strict signing, arm64
  app/core binaries, iOS 15.0 minimum, iPhone+iPad device families, and the
  TrollStore JIT/unsigned-memory/extended-address-space/increased-memory
  entitlements. The repository and iCloud Drive copies are byte-identical.
- SOURCE IDENTITY NOTE: the package script reports base revision
  `cb32d3effdb97f7c46af4a7085eec3efb41b18cc`; V0.22 also contains the scoped
  verified working-tree changes documented in this section. Do not treat the
  base revision alone as the full source identity until the candidate is
  checkpointed in Git.
- PHYSICAL TITLE MATRIX / OPEN: `Star Wars: The Force Unleashed` and
  `Tomb Raider Trilogy` reported decryption failures. `Hasbro Family Game
  Night` required three boots, reached logos/menu, then remained black at a
  reported `57-60 FPS` before appearing jammed; at that point the server was
  idle with no active port-38008 client and no new server crash, identifying a
  separate guest/runtime hang. `Sonic Generations` began loading after the
  preceding title error. Preserve each result separately from transport health.
- REQUIRED PHYSICAL RECOVERY GATE: install the exact next signed IPA, launch a
  known failing encrypted title, press Stop, immediately launch a known-good
  NETISO title, then Stop and run Connect + Scan NAS. The second launch and both
  `/PS3ISO` and `/GAMES` listings must complete without restarting the app,
  container, or supervised server process. Repeat once while deliberately
  restarting only `ps3netsrv` inside the container. Until this passes on-device,
  the recovery fix remains a candidate rather than accepted behavior.

## GTA V NETISO child-handoff repair (post-V0.22)

- ROOT CAUSE / MISSED V0.15 PATH: the existing compatibility policy was wired
  only through `sys_fs::translate_to_str()`. GTA V's Duplex wrapper performs a
  second `sys_game_process_exitspawn`; `lv2_exitspawn()` resolved
  `/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN` directly through `vfs::get()`
  before `BootGame`, so the executable handoff bypassed every `sys_fs` redirect
  and still targeted the nonexistent HDD path.
- FIX READY: on iOS only, `lv2_exitspawn()` now applies the same exact-prefix
  policy before host VFS resolution and updates child `argv[0]` consistently.
  The redirect requires both continuous child-process mode and an active
  virtual-ISO-backed `/dev_bdvd/PS3_GAME`; normal first-process launches,
  installed-title paths, lookalike prefixes, and non-virtual discs are not
  changed. A notice log records the old and new guest paths when activated.
- PASS STATIC/BUILD: the focused policy contract verifies redirected and
  isolated paths, and the incremental two-worker arm64 `RPCS3Core` build passes
  with the real `sys_process.cpp` integration.
- REQUIRED PHYSICAL: package the next version, launch GTA V from a fresh app,
  advance through the Duplex intro, and require the exitspawn redirect notice
  followed by actual GTA executable boot. A logo, intro, black Loading screen,
  or successful wrapper process alone remains a failure.

## Sonic Generations compilation failure (V0.22 physical)

- FAIL PHYSICAL / INITIAL BOOT: the exact installed V0.22 candidate reached
  `99% Building SPU cache` and stopped advancing. Stop/relaunch skipped the
  completed preload PPU phase, proving that useful cache data persisted, but
  did not qualify a clean first boot.
- FAIL PHYSICAL / RESTART: after relaunch, Sonic briefly produced FPS, then
  repeatedly returned to `0 FPS` while lower-left `Compiling PPU modules`
  notices appeared. A final clean relaunch reproduced the cycle with a black
  screen and no audio, so the user stopped testing V0.22. No iPhone process log
  was captured because only the iPad enumerated over USB, so the module hashes
  are unknown; do not claim that one identical object was repeatedly compiled.
- ROOT-CAUSE CANDIDATE / SPU FINALIZATION: the SPU cache path still used both
  completion mechanisms already removed from the physically stalled PPU path:
  implicit `named_thread_group` joins on iOS 15 and a synchronous
  `malloc_zone_pressure_relief()` sweep between 99% and guest startup.
- FIX READY: iOS SPU cache construction now uses direct `std::thread` workers,
  records each worker's completion before deterministic joins, and proceeds
  directly to guest startup without a synchronous allocator sweep. PPU and SPU
  compilation use one worker at severe headroom, at most two under moderate
  headroom, and up to four only with more than 2304 MiB available. Generic
  gameplay thread limits and non-iOS behavior are unchanged.
- PASS STATIC/BUILD: focused adaptive-memory contracts, the complete bounded
  iOS contract suite, `git diff --check`, and the incremental two-worker arm64
  `RPCS3Core` build all pass with the real SPU/PPU integration.
- REQUIRED PHYSICAL: install the next exact signed IPA, run Sonic from a cold
  title cache through SPU 100% and first gameplay, then relaunch twice. Require
  no 99% finalization stall, no recurring compile/FPS-zero cycle after caches
  settle, and explicit worker-complete/finalization log markers.

## Mobile RSX wait-policy candidate (post-V0.22)

- MEASURED BASIS: V0.20 heavy-3D evidence showed the iPhone process above
  3.3 GiB, normalized SPU load at 49-66% of all six logical cores, and more
  than one second of aggregate Metal execution in a one-second sample. Busy
  CPU waits can therefore starve both guest work and the driver while adding
  heat, but fixing them is not equivalent to reducing the GPU workload.
- FIX READY: unbounded Vulkan fence polling now hot-polls briefly and then
  blocks in `vkWaitForFences`; Vulkan event readback polling hot-polls and then
  sleeps for 50 microseconds; the RSX DMA drain hot-polls and then waits on its
  completion counter with a bounded 100-microsecond wake; and mobile occlusion
  query polling yields after its short hot window. The short path and fault
  recovery upkeep remain intact.
- FIX READY / IOS ONLY: asynchronous Vulkan pipeline workers run at Utility
  QoS instead of inheriting User Interactive QoS from the reusable iOS thread
  pool. PPU, SPU, RSX, audio, and Metal work retain their existing priority.
- SCOPE: shader translation, shader math, attachment formats, command ordering,
  title profiles, resolution, and cache keys are unchanged. This candidate is
  intended to reduce CPU starvation and thermal pressure, not to conceal U2/U3
  renderer corruption or claim that MoltenVK now matches direct Metal.
- PASS STATIC/BUILD: the complete bounded iOS contract suite passes, the four
  modified RSX translation units compile, and the arm64 `RPCS3Core` dylib links
  with `-j2`. The build emits the pre-existing deprecation diagnostic for a
  timed wait on an eight-byte `atomic_t`; the upstream drain-wait contract uses
  that API and the produced binary is valid.
- REQUIRED PHYSICAL: use the exact same warm-cache U1 and RDR gameplay segments
  and settings as V0.20. Record FPS, CPU P/S/R/O, MVK E/W/Q/G, RSX D/S U/X/F,
  headroom, visual correctness, audio, thermals, and Stop/relaunch. Promotion
  requires lower wait/CPU pressure without worse FPS, input latency, stalls,
  artifacts, or shutdown behavior; no performance gain is claimed yet.

## V0.23 combined candidate (2026-08-31)

- SOURCE: executable source revision
  `9a834b3efcc3605d2eaf762a38fd625d8664be97`. It contains the V0.22 NETISO
  recovery checkpoint, GTA V child-executable handoff repair, Sonic SPU-cache
  finalization repair, adaptive PPU/SPU boot compilation, and the mobile RSX
  wait/QoS experiment documented above.
- PASS PACKAGE: `ARMSX3-iOS-Core-Test-v0.23.ipa` is version `0.23.0`, build
  `22`, `31,859,970` bytes, SHA-256
  `e2664a68f74620db43739099482fa3fc733656fac613ed2f721e12fe4bc249e3`.
- PASS INDEPENDENT READBACK: fresh ZIP extraction passed integrity and deep
  strict signature verification. The app and core are arm64 Mach-O binaries,
  both target iOS 15.0, the app links `@rpath/libRPCS3Core.dylib`, and device
  families are iPhone plus iPad. JIT, unsigned executable memory, Extended
  Virtual Addressing, increased memory, and debug entitlements all read back
  true from the extracted package.
- PASS CORE IDENTITY: the embedded core and build product share UUID
  `1B0F3B4C-CD95-38C3-A5C9-B32DC2584447`; the extracted core exports ABI 33's
  version symbol and contains the exact GTA exitspawn and SPU-finalization log
  markers. Ad-hoc signing intentionally makes the signed dylib bytes differ
  from the unsigned build product, so UUID plus symbol/marker readback is the
  valid identity check.
- PASS TRANSFER: repository and iCloud Drive copies are byte-identical and
  have the SHA-256 above. V0.22 remains preserved as the immediate rollback.
- OPEN PHYSICAL: no V0.23 game, input, Stop/relaunch, renderer correctness, or
  FPS result exists yet. Run Sonic first, GTA V second, then controlled U1 and
  RDR comparisons. A successful install, boot screen, menu, or compilation
  stage is not acceptance.

## V0.24 native Metal presentation foundation (2026-08-31)

- SOURCE: clean-room implementation commit
  `9276901f1a13683ccb6942d4f18e5a419f0ec010`. ABI 34 adds one stopped-core
  diagnostic export without changing the selected game renderer, cache keys,
  shader translation, RSX command processing, or title settings.
- CLEAN-ROOM BOUNDARY: the implementation was authored against public Apple
  Metal and QuartzCore APIs. No ARMSX2/PCSX2 Metal source was copied because
  licensing compatibility between those GPL-3.0-or-later files and this fork's
  current licensing was not established.
- FIX READY: the core validates the attached `CAMetalLayer`, reuses its device,
  creates a native command queue, compiles original MSL vertex and fragment
  functions, creates a render pipeline, clears and draws one colored triangle,
  presents the drawable, and waits at most five seconds for completion. The ABI
  returns drawable dimensions and format, GPU duration, registry ID, maximum
  buffer length, unified-memory state, and device name.
- PASS STATIC CONTRACT: ABI 34, build-info capability, append-only status 49,
  and the 176-byte result structure are compile-time checked. The complete
  bounded iOS contract runner passes, including NETISO cancellation.
- PASS BUILD/IDENTITY: the two-worker arm64 iOS 15 `RPCS3Core` build and
  one-worker UIKit app build pass. The app-embedded and standalone unsigned
  cores are byte-identical with SHA-256
  `202419786ad02459bbbd5356885d5c9ef16094b77f31b5ecb29deb996bb7ef17`
  and UUID `AA35A824-63CB-3F65-AF7F-BCEF986C9F1E`. The core exports
  `rpcs3_ios_run_metal_presentation_probe`, and the app reports version
  `0.24.0` build `23` for both iPhone and iPad.
- PASS PACKAGE/READBACK: `ARMSX3-iOS-Core-Test-v0.24.ipa` is `31,864,950`
  bytes with SHA-256
  `0cc6f4f62a8c157c347c6727b45696cbfbf2fe4a1b67eca5b38bca9009ce1148`.
  Fresh extraction passed ZIP integrity and deep strict signature validation.
  Both Mach-O binaries are arm64 with minimum iOS 15.0; the app links the
  nested core through `@rpath`, the package contains ABI 34 and probe markers,
  and JIT, unsigned executable memory, Extended Virtual Addressing, increased
  memory, and debug entitlements all read back true.
- PASS TRANSFER: repository and iCloud Drive V0.24 copies are byte-identical
  at the size and SHA-256 above. V0.23 remains preserved and unchanged.
- SCOPE / NO FALSE CLAIM: a passing triangle proves that this device can use
  the app's real display layer for native MSL compilation, pipeline creation,
  command encoding, GPU execution, drawable presentation, and timing readback.
  It does not prove a direct-Metal RSX backend, game rendering, correctness,
  stability, or any FPS improvement; gameplay still uses Vulkan through
  MoltenVK in this candidate.
- REQUIRED PHYSICAL PROBE: with emulation stopped, tap `Metal Probe`. Require a
  dark clear plus clean cyan/gold/green triangle, a `Native Metal PASS` result
  containing the actual device, nonzero drawable dimensions, and no timeout or
  crash. Then launch a known-good Vulkan title to prove the diagnostic did not
  poison the existing renderer session.
- REQUIRED NEXT ENGINEERING GATE: translate one bounded RSX operation class
  through an independently authored Metal backend behind an explicit test-only
  selector, compare pixels and synchronization against Vulkan, and preserve an
  immediate Vulkan rollback. Do not call the backend usable until controlled U1
  and RDR scenes pass visual, FPS, memory, thermals, audio, input, and repeated
  Stop/relaunch qualification on physical hardware.

## ARM system-counter hot-path candidate (post-V0.24)

- SOURCE: isolated commit `de7ba7711`. This change is not present in the
  independently audited V0.24 IPA; preserve that package as the direct-Metal
  probe baseline.
- MEASURED BASIS: `perf_meter` eagerly called `utils::get_tsc()` even when
  `perf_report` was disabled, although its destructor then discarded the
  sample. On ARM64 this is an `mrs cntvct_el0` system-register read that does
  not pipeline, paid once per guest PPU reservation and several SPU DMA/atomic
  operations. Prior U1/RDR telemetry showed these CPU paths heavily loaded
  while the Metal driver was also saturated.
- FIX READY: a lazy `perf_meter(nullptr)` samples only when performance reports
  are enabled. PPU LARX/STCX, SPU DMA, MFC list transfers, and PUTLLC use it.
  The failed-LARX timing heuristic still takes a timestamp only when its address
  window can match, preserving reservation behavior without the common-path
  counter read.
- SAFETY BOUNDARY: `STORE128` remains eagerly timed because its suspend-all path
  consumes `perf0.get()`. GETLLAR and every other meter with an in-function
  timestamp consumer are unchanged. With `perf_report` enabled, sampling and
  reporting behavior remains unchanged.
- PASS STATIC/BUILD: exact call-site review, `git show --check`, the complete
  bounded iOS contract runner, and the incremental two-worker arm64 iOS 15 core
  build pass. The resulting unsigned core has SHA-256
  `d12e5f164f7a872fe4bf69bc2884b37310625c1ae0a916d2bca41507416fe134`
  and UUID `8D3E9F93-699E-3BAC-84B5-191AE4B9D3DA`.
- REQUIRED PHYSICAL: compare identical warm-cache U1 and RDR segments with
  `perf_report` off. Require no reservation/atomic regressions or new crashes,
  then compare CPU P/S, RSX/Metal pressure, frame pacing, FPS, audio, thermals,
  and Stop/relaunch. The static removal of wasted reads is proven; a gameplay
  or FPS gain is not yet claimed.

## PPU cached-reservation repair (post-V0.24)

- SOURCE: isolated commit `4f68677b7`, carrying the final two-line behavior
  from upstream `ca3b755fd` after its temporary diagnostic probe was removed by
  `2e65c8b21`. No failure counters or hot-path diagnostic logging were added.
- ROOT CAUSE: a successful conditional store advances the 128-byte line's
  reservation counter by 128 and then caches that line for the next LARX. The
  cached reload deliberately preserves `ppu.rtime`, but the success path did
  not advance it, leaving the thread exactly one increment behind. Subsequent
  same-line conditional stores could therefore fail indefinitely despite
  unchanged data and no competing writer.
- FIX READY: after a successful store caches `ppu.raddr`, `ppu.rtime` now
  advances by 128 before the live reservation address is cleared. Failure,
  notification, non-cached, and SPU reservation paths are unchanged.
- PASS STATIC/BUILD: the final diff is one comment plus one arithmetic update;
  `git diff --check`, the complete bounded iOS contract runner, and the
  incremental two-worker arm64 iOS 15 core build pass. The resulting unsigned
  core has SHA-256
  `69d17d32b99d881f0ebc16e180c4fb03b76e3d19608ed6c91a809599ba2372e7`
  and UUID `31FCBC20-08E3-3D57-8337-AA6C6B5FB930`.
- REQUIRED PHYSICAL: an affected same-line reservation loop must progress
  rather than accumulate endless STCX failures. If Assassin's Creed is
  available, exercise its `cellSpursAddUrgentCommand` startup path used to
  establish the upstream failure. Also rerun U1/RDR and require no atomic,
  startup, save, input, or Stop/relaunch regression. No title fix or FPS gain is
  claimed before physical evidence.

## Runtime log-amplification candidate (post-V0.24)

- SOURCE: upstream SPU commit `e36d962b0`, upstream PPU commit `00811e493`, and
  scoped mmapper commit `bb07a2f70`. The mmapper commit carries only the four
  production log-level changes from `22ec027fa`; its always-on timing counters
  and profiler globals are deliberately excluded.
- UPSTREAM MEASURED BASIS: one 15-minute Prototype session attributed 49,644 of
  56,881 lines to per-block/per-instruction SPU diagnostics, peaking at 2,473
  lines in one second. A Portal 2 session produced a 1.26 GB log dominated by
  one notice per relative relocation. A Sonic '06 session measured mmapper
  syscall chatter at 395 lines/second sustained. These measurements motivate
  the change but are not claimed as current iPhone results.
- FIX READY / SPU: routine block compilation, fallthrough/filler discovery,
  loop and trampoline simplification, pattern analysis, and nonconstant MFC
  fallback messages move to trace. Invalid MFC sizes and unknown commands remain
  errors, and trace logging can still be enabled for focused diagnosis.
- FIX READY / PPU: ignored relative, ignored 64-bit, and repeated relocations
  are counted and reported once per module with the first address retained,
  instead of formatting and queuing one message per relocation.
- FIX READY / MMAPPER: allocate, free, search-and-map, and successful-address
  messages on the measured streaming path move from warning/notice to trace.
  VM locks, thread suspension, mapping behavior, and memory accounting are
  unchanged.
- PASS STATIC/BUILD: exact level review confirms genuine MFC faults remain at
  error level. `git diff --check`, the complete bounded iOS contract runner,
  and the incremental two-worker arm64 iOS 15 core build pass. The resulting
  unsigned core has SHA-256
  `a10aa29db2957106e37d4e6a31d3a64596a960257f2cea707b050a018a984599`
  and UUID `D8298EB8-B4BC-38B6-8E5A-DB2359F7521E`.
- REQUIRED PHYSICAL: cold-boot a title with substantial PPU/SPU compilation and
  a streaming title, capture line counts/rates and compile/start latency, then
  compare a warm second launch. Require lower routine log volume with genuine
  failures still visible, no new compile loop or hang, and no regression in
  gameplay, audio, memory, or Stop/relaunch. No performance gain is claimed yet.

## ARM64 SPU codegen-correctness candidate (post-V0.24)

- SOURCE: SHUFB commit `4c3ae0229` and float commit `4e676683b`, selectively
  backported from upstream `19d23eb69` and `424514fde`. X86 code generation and
  persistent SPU object-cache machinery are intentionally unchanged.
- UPSTREAM SHUFB EVIDENCE: non-splat constant byte-swap folding plus KnownBits
  single-source selection caused a Borderlands 2 SPURS block at LS `0x25da8`
  to spin forever when compiled but boot when interpreted. Removing both
  triggers also stopped reported Spider-Man: Edge of Time crashes and allowed
  Bleach to reach Story Mode. These are upstream measurements, not yet iPhone
  results.
- FIX READY / SHUFB: on ARM64, only splat constants use the byteswap fold, where
  byteswap is identity. A single-source fast path is selected only when the two
  guest source registers are actually the same. ARM64 TBL/TBX paths otherwise
  remain enabled, and all x86 fast paths remain source-identical.
- UPSTREAM FLOAT EVIDENCE: PS3 SPU tests found 984 ARM-specific output
  divergences before the fixes and zero for the affected CFLTS and FMS cases
  afterward. The accurate f64-to-s32 path also reproduced negative overflow as
  a positive integer because AArch64 saturates to i64 before lane narrowing.
- FIX READY / FLOAT: ARM64 FMS preserves a NaN-pattern addend before host
  negation so SPU extended-range values do not flip sign. CFLTS now explicitly
  saturates high and low in the accurate path and handles ARM64 high/NaN
  behavior directly in the f32 path instead of applying an x86-specific XOR.
- CACHE BOUNDARY: iOS `Automatic` resolves persistent SPU object caching off,
  which is required because persisted ARM64 objects contain unrelocated host
  addresses. Leave it off while qualifying this codegen. The normal SPU guest
  cache and compile pipeline remain enabled.
- PASS STATIC/BUILD: each commit independently passed `git diff --check`, the
  complete bounded iOS contract runner, and an incremental two-worker arm64
  iOS 15 core build. With both commits present, the unsigned core has SHA-256
  `4c9a85bed75a2b24078721b51f8431960672a303ac778b1ea7e2f1af3f596eac`
  and UUID `504F9690-E52F-35B5-A2FB-D7B0D56D7351`.
- REQUIRED PHYSICAL: first verify Borderlands 2 or another known SHUFB-heavy
  title crosses its prior startup/SPURS point without an SPU spin. Then compare
  U1/U2/U3 and RDR from clean app launches for changed hangs, green/white block
  artifacts, geometry, FPS, audio, and crash behavior. These CPU fixes may
  repair bad data feeding RSX, but they are not presumed to fix renderer bugs;
  accept only title-specific observed changes and preserve Vulkan rollback.

## Vulkan command-buffer ring retirement candidate (post-V0.24)

- SOURCE: isolated implementation commit `1fd3c9401`. It was reconstructed
  from the measured problem statement in dangling experiment `d57fc974b`, then
  hardened rather than cherry-picked. The experiment's split ticket/map state,
  missing blocking-wait retirement, and lack of heap-growth epochs were not
  accepted as-is.
- ROOT CAUSE: managed Vulkan upload rings previously advanced their GET pointers
  only when a presented frame retired. A title that submits substantial RSX
  work during a long no-present load can therefore keep allocating without
  returning completed command-buffer ranges. The measured experiment saw a
  Sonic '06 attrib ring grow from 64 MiB to 576 MiB over a 16-second load and a
  Ratchet & Clank index ring grow from 16 MiB to 256 MiB in 290 ms despite only
  kilobyte-size requests. Those are donor measurements, not current iPhone
  results.
- FIX READY: each tagged primary command buffer captures all managed ring GET
  boundaries immediately before submission. A successful fence poll or
  blocking wait retires that snapshot, so no-present work is eventually
  reclaimed when its command-buffer slot is observed or reused. Normal frame
  retirement remains as a second path, and rare heap growth now logs the heap
  name, old/new size, and request size for physical diagnosis.
- ORDERING SAFETY: snapshots carry one manager-serialized monotonic ID. A
  completion older than the most recently applied snapshot is ignored, so an
  out-of-order observation cannot move a wrapped ring backward over reused
  memory. Capture and restore share one mutex; the reusable contiguous entry
  vector avoids per-heap hash-node allocation on every submit.
- GROWTH/TEARDOWN SAFETY: every heap create or grow receives a process-unique
  generation. Restore requires both a currently registered pointer and matching
  generation, preventing an old fence from modifying a re-created or newly
  grown allocator. Snapshot IDs intentionally remain monotonic across renderer
  reset so late old completions stay stale.
- TIMEOUT SAFETY: only `VK_SUCCESS` authorizes command or frame reclamation. A
  timed-out command snapshot is discarded without moving GET, frame cleanup
  skips its snapshot, and the context clears its ticket before reuse. The
  existing broader device-loss cleanup behavior is unchanged.
- POLLING BOUNDARY: this commit adds no fence query and does not switch
  `vkGetFenceStatus` to the prior zero-timeout experiment. It attaches reclaim
  to observations the renderer already performs. Consequently a no-present
  load may retain completed ranges until a command-buffer slot is revisited;
  reducing that latency requires device telemetry and cannot be traded for an
  unmeasured mobile-driver synchronization stall.
- PASS STATIC/BUILD: `git diff --check`, the complete bounded iOS contract
  runner including NETISO cancellation, and the two-worker arm64 iOS 15 core
  build pass. The resulting unsigned core is `77,495,184` bytes, SHA-256
  `b4e8c69ed69527dd87e1080f24d39f001e05210f3ae6929af27ce3e3b911a4c4`,
  UUID `96EC3E90-7DDA-31C6-B0BC-E48330BF4BCE`.
- REQUIRED PHYSICAL: first cold-launch Sonic Generations and record every named
  heap-growth line, process footprint/headroom, whether PPU/SPU progress exits,
  and whether a renderable frame appears. If available, repeat the Ratchet load
  that exercised the index ring. Then run the exact warm U1 and RDR gameplay
  segments used for V0.20, plus U3 visual checks and sequential Stop/relaunch.
  Acceptance requires bounded repeated growth, no allocator fatal, no new
  geometry/color corruption, no worse FPS/audio/input, and clean teardown. A
  successful build or lower theoretical lifetime is not a gameplay or
  performance claim.

## V0.25 combined candidate (2026-08-31)

- SOURCE: packaged executable revision
  `3bf59d91357a9e1881d4ee76bc58f14b2d621bd8`. Relative to V0.24, it contains
  the lazy ARM system-counter path, PPU cached-reservation repair, bounded
  runtime logging, ARM64 SHUFB/FMS/CFLTS correctness backports, and the
  generation-safe Vulkan command-buffer ring retirement documented above. The
  native Metal presentation probe remains available, while Vulkan/MoltenVK
  remains the only selected game renderer.
- PASS PACKAGE: `ARMSX3-iOS-Core-Test-v0.25.ipa` is version `0.25.0`, build
  `24`, `31,864,995` bytes, SHA-256
  `32ad1ab5f36a3d1bdff208f169cea1ebcd65b6bee1979189c2698c8767c738c7`.
- PASS INDEPENDENT READBACK: a fresh temporary extraction passed full ZIP
  integrity and `codesign --verify --deep --strict`. The app and embedded core
  are arm64 Mach-O binaries targeting iOS 15.0; the app links the core through
  `@rpath`, requires arm64 plus Metal, and declares iPhone and iPad families.
- PASS ENTITLEMENTS: the extracted signature independently reports JIT,
  unsigned executable memory, Extended Virtual Addressing, increased memory,
  and `get-task-allow` true under the TrollStore application identifier.
- PASS CORE IDENTITY: the signed embedded core and unsigned build product share
  UUID `96EC3E90-7DDA-31C6-B0BC-E48330BF4BCE`. The package exports
  `rpcs3_ios_abi_version`, `rpcs3_ios_build_info`, and the native Metal probe;
  its build-info marker reports ABI 34, and the named heap-growth diagnostic is
  present. The unsigned core is `77,495,184` bytes with SHA-256
  `b4e8c69ed69527dd87e1080f24d39f001e05210f3ae6929af27ce3e3b911a4c4`.
- PASS TRANSFER/ROLLBACK: repository and iCloud Drive V0.25 copies are
  byte-identical at the size and SHA above. V0.23 remains unchanged at SHA
  `e2664a68...ffe8b`, and V0.24 remains unchanged at SHA
  `0cc6f4f6...e1148`; neither was overwritten or deleted.
- TOOLING FOLLOW-UP: the packaging run's old summary printed export-symbol
  count `1` as `core ABI`. Commit `16ca69a50` now requires the ABI export and
  validates the numeric build-info marker, correctly reading `34`. This script
  correction occurred after packaging and does not change V0.25 app/core/IPA
  bytes; the independent extraction above is the authoritative package audit.
- REQUIRED PHYSICAL ORDER: install this exact SHA, run the stopped-core Metal
  Probe first, then boot a known-good local title to prove Vulkan remains clean.
  Next cold-test Sonic Generations while recording named heap growth and memory,
  test GTA V child handoff, and run the same warm U1/RDR scenes plus U3 visual
  checks. Finish with input, background/foreground, Stop, immediate relaunch,
  and sequential-title teardown. No install, menu, compile progress, probe, or
  package result substitutes for title-specific gameplay evidence.

## ARM64 SPU reservation-line copy candidate (post-V0.25)

- SOURCE: isolated commit `2fca893c9`, selectively backported from upstream
  `9b3331698`. Only the two ARM64 reservation-copy branches were retained; the
  donor's 399-line Borderlands/SPURS diagnostic payload was deliberately
  excluded. X64 and other architectures remain source-identical.
- FIX READY: `mov_rdata` and `mov_rdata_nt` now move each 128-byte SPU
  reservation line through eight explicit 16-byte NEON values instead of
  delegating copy granularity to `std::memcpy`. These paths snapshot GETLLAR
  data and refill guest local store while other emulated threads may be active.
- MACHINE-CODE READBACK: the linked arm64 iOS core contains four `ldp qN, qN`
  pairs followed by four `stp qN, qN` pairs covering offsets `0x00` through
  `0x70`, followed directly by `ret`; there is no libc copy call in the
  emitted function.
- PASS STATIC/BUILD: `git diff --check`, the complete bounded iOS contract
  runner including NETISO cancellation, and the two-worker arm64 iOS 15 core
  build pass. The resulting unsigned core has SHA-256
  `d835b01fb41711762694a1ce104c8c10738a0c2859e8ac224d770952e5439ae2`
  and UUID `BC645A7C-3475-34BC-95A4-DCEF20B23767`.
- EVIDENCE BOUNDARY: upstream measured no Borderlands 2 behavior change from
  this copy correction. It is retained as an ARM64 correctness/hot-path
  cleanup, not an FPS or hang fix, and does not by itself justify replacing
  the audited V0.25 package.
- REQUIRED PHYSICAL: after a later combined package, compare an SPU-heavy
  title from clean launch through gameplay and immediate Stop/relaunch. Require
  no reservation/SPURS regression, no new crash or hang, and unchanged or
  better frame/audio behavior before promotion.

## MTRSX liveness and fail-closed handoff candidate (post-V0.25)

- SOURCE: producer guard commit `fd61206d0` plus liveness hardening commit
  `38af7ccb7`, selectively reconstructed from upstream `ae4f26c39`,
  `8ae45a74b`, and `889b82675`. The upstream MM line-ending rewrite and
  title-specific shader diagnostics were excluded.
- ROOT RISK: the setting says MTRSX is requested; it does not prove a worker is
  alive to drain its queue. The old copy, index-emulation, Vulkan-submit, and
  lazy host-memory paths could all enqueue from the setting alone. If startup
  failed or the worker exited, the processed count and submit-flushed flag
  could never advance, leaving flip, Stop, and relaunch waiting permanently.
- FIX READY / COMPLETE COVERAGE: both copy overloads, index emulation, Vulkan
  queue submission, and lazy host-memory flush now use one `can_offload()`
  predicate. If no worker is accepting work, each producer uses its existing
  synchronous path instead of dropping or stranding a job. The generic backend
  callback is reached only through those guarded sites.
- ARM64 LIVENESS SAFETY: worker identity is published through an atomic pointer
  and cleared on normal exit. `can_offload()` additionally requires the named
  thread's atomic state to remain `created`, so a stale pointer after a fault or
  finish cannot authorize new work. Fault recovery uses the same checked
  identity rather than racing a plain pointer.
- iOS LIFECYCLE BOUNDARY: database, custom, and mobile-profile settings are
  applied in `System.cpp` before RSX calls `dma_manager::init()`. iOS settings
  APIs also reject mutation during emulation. Therefore an MTRSX-disabled iOS
  title retains the prior early worker exit and does not inherit upstream's
  always-live 5 ms wake loop. U1, U2, RDR, and GTA V profiles already enable
  MTRSX before worker creation; U3 intentionally remains serialized.
- PASS STATIC/BUILD: every current enqueue site was audited, `git diff --check`,
  the complete bounded iOS contract runner including NETISO cancellation, and
  the two-worker arm64 iOS 15 core build pass. The combined unsigned core after
  the wait hardening below is `77,495,552` bytes, SHA-256
  `9a7a9bb2791c6637e5e8ef87802a1e1d4358e935c850af0468c78ed3a141ecca`,
  UUID `48E70305-AFB8-3F0E-A517-8230486FDC73`.
- REQUIRED PHYSICAL: on fresh app launches of U1 and RDR, require the `RSX
  Offloader` thread to be present while effective settings report MTRSX on.
  Capture settled FPS, RSX/other CPU, frame waits, audio, memory, and Stop time
  in the same repeatable scenes. Then prove U3 remains free of green/pink or
  block corruption with MTRSX off. No static result proves an FPS increase.

## Stop-aware Vulkan wait candidate (post-V0.25)

- SOURCE: isolated commit `2610e3cfa`, based on the generic portions of
  upstream `36c4820b8` and `2310d51fd`. Librashader/upscaler changes were not
  included because they are unrelated to the selected game-renderer path.
- ROOT RISK: `fence::wait_flush()` spun forever if an asynchronous submit was
  never flushed, while the zero-timeout GPU-fence path eventually called
  `vkWaitForFences(..., UINT64_MAX)`. Either condition could trap the RSX
  thread after a renderer or driver failure, preventing Emulation Join, Stop,
  immediate relaunch, and orderly app shutdown.
- FIX READY: normal flushed/submitted fences retain their existing hot paths.
  A pathological submit-flush spin periodically checks thread abort and stopped
  state. After the existing 512 hot GPU polls, an indefinite fence wait now
  uses 100 ms driver-wait slices, reports one diagnostic at three seconds, and
  returns `VK_TIMEOUT` only once emulation is stopping.
- SAFETY BOUNDARY: this is teardown escape, not live GPU recovery. It does not
  mark an unfinished fence successful or reclaim its ring snapshot; the
  generation-safe allocator path clears timeout authority. No renderer reset,
  pipeline-cache invalidation, or ordinary synchronization ordering changed.
- PASS STATIC/BUILD: `git diff --check`, the complete bounded iOS contract
  runner, and a warning-clean incremental arm64 iOS 15 core rebuild pass. Core
  identity is the combined SHA/size/UUID recorded in the MTRSX section above.
- REQUIRED PHYSICAL: Stop during a known-good title, during NETISO failure,
  while shader/PPU/SPU work is active, and during a reproduced zero-FPS RSX
  stall. Require prompt return to the launcher, no Jetsam or crash, no retained
  audio/haptics, and successful immediate launch of a second title. Capture
  either abandonment diagnostic if exercised; absence during normal Stop is
  expected and not failure.

## V0.26 combined candidate (2026-08-31)

- SOURCE: packaged executable revision
  `c152000dcf678444238779e0e490bd0bf67c2a0f`. Relative to V0.25, this adds
  the ARM64 reservation-line vector copy, complete fail-closed MTRSX producer
  gating with race-free liveness, and stop-aware Vulkan submit/GPU-fence waits.
  Vulkan/MoltenVK remains the selected game renderer; the native Metal probe is
  unchanged and remains a stopped-core diagnostic only.
- PASS PACKAGE: `ARMSX3-iOS-Core-Test-v0.26.ipa` is version `0.26.0`, build
  `25`, `31,865,895` bytes, SHA-256
  `c846c16862c690678e6c8ab97d94ef1cb1ae417187e1bae42c5eee95073e4457`.
- PASS METADATA REGENERATION: pre-sign readback caught the plist template still
  hardcoding build `24` despite Xcode's build setting being `25`; no bad IPA was
  accepted. Commit `c152000dc` aligns the template and registers it as a CMake
  configure dependency. Touching the template now provably forces CMake
  regeneration, and final app readback reports exactly `0.26.0 (25)`.
- PASS INDEPENDENT READBACK: a fresh temporary extraction passed ZIP integrity,
  absence of `__MACOSX` payloads, `codesign --verify --deep --strict`, and
  standalone core signature verification. The package contains ten regular
  payload files. App and core are arm64 Mach-O binaries targeting iOS 15.0;
  the app links `@rpath/libRPCS3Core.dylib`, requires arm64 plus Metal, and
  declares both iPhone and iPad families.
- PASS ENTITLEMENTS: the extracted app independently reports JIT, unsigned
  executable memory, Extended Virtual Addressing, increased memory limit, and
  `get-task-allow` true under the TrollStore application identifier.
- PASS CORE IDENTITY: the signed embedded core and unsigned build product share
  UUID `48E70305-AFB8-3F0E-A517-8230486FDC73`. The unsigned core is
  `77,495,552` bytes with SHA-256
  `9a7a9bb2791c6637e5e8ef87802a1e1d4358e935c850af0468c78ed3a141ecca`;
  the independently extracted signed core SHA-256 is
  `46c937160395f588b9db8cc2d0f838e281788d16deaa8015b8044b72c72c7a88`.
  ABI 34, build-info, and native-Metal-probe exports are present, as are the
  named ring-growth, three-second GPU-fence, stop-abandonment, and MTRSX
  liveness symbols.
- PASS TRANSFER/ROLLBACK: repository and iCloud V0.26 copies are byte-identical.
  V0.23 remains SHA `e2664a68...ffe8b`, V0.24 remains SHA
  `0cc6f4f6...e1148`, and V0.25 remains SHA `32ad1ab5...c738c7`; none was
  overwritten or deleted.
- REQUIRED PHYSICAL ORDER: install this exact SHA and start with a known-good
  local Bejeweled 3 or DuckTales launch/Stop/relaunch. Then run the exact U1 and
  RDR gameplay scenes used for prior FPS comparisons while confirming effective
  MTRSX on and an active `RSX Offloader`; capture FPS floor/average/peak,
  PPU/SPU/RSX/other CPU, memory, audio, and graphics. Test GTA V child handoff,
  Sonic Generations cache completion and heap growth, U3 colors/blocks with
  MTRSX off, sequential NETISO failure/recovery, background/foreground, Stop,
  and immediate second-title launch. Package, compile progress, and menu output
  are not gameplay or performance proof.

## PPU range-lock wake candidate (post-V0.26)

- SOURCE: isolated commit `65758e455`, selectively backported from upstream
  `27819fba8`. Reverted barrier-bypass, timed-backoff, notifier-park, and
  reservation-table experiments were not imported.
- ROOT CAUSE: `vm::writer_lock` can stamp every registered PPU with
  `cpu_flag::memory` while SPU reservation writes hold the global exclusive
  range-lock word. The passive PPU path spun 100 times and then yielded a full
  scheduler quantum, but the release path never notified that word. Under
  repeated short SPU writer intervals, a PPU could sleep through each all-clear
  window and unnecessarily extend guest synchronization stalls.
- FIX READY: writer release now notifies only when the whole exclusive-range
  word transitions to zero, which is the sole state that can release a passive
  PPU. After the unchanged short spin, the PPU waits on the observed word value
  instead of yielding blind. The `50'000` `atomic_wait_timeout` value is 50
  microseconds and is retained as a lost-notification safety net, not a pacing
  delay.
- CORRECTNESS BOUNDARY: all existing DATA and PROTECTION exclusion remains in
  place. The patch changes neither the protected range nor the writer-lock
  lifetime and does not use the generic 16-byte barrier bypass that previously
  produced `SEGV_ACCERR`. A value change before the wait returns immediately.
- PASS STATIC/BUILD: `git diff --check`, the complete bounded iOS contract
  runner including NETISO cancellation, and an incremental two-worker arm64
  iOS 15 core link pass. The unsigned core is `77,495,496` bytes, SHA-256
  `69f877d3390062eaede7314311904691bb952aa0e181a2d8848006ee4b9a27ca`,
  UUID `8CBB9D4B-1A5D-3021-B333-038914B797A9`. Clang reports the upstream
  eight-byte `atomic_t::wait` API as deprecated; this is a compile warning, not
  a failed link, and changing wait primitives without device evidence is
  intentionally deferred.
- EXCLUDED TITLE-SPECIFIC CHANGE: upstream `6c4b63905` admits one verified
  Sonic '06 `cellSync` byte-pattern hash to `PUTLLC16`. It is safe and
  fail-closed for that exact hash, but no evidence connects it to Sonic
  Generations, U1, RDR, or U3, so it is not included or advertised as a broad
  performance fix.
- REQUIRED PHYSICAL: package only with the next independently audited
  candidate. Compare the exact warm U1 and RDR scenes against V0.26 while
  recording FPS, PPU/SPU/RSX/other CPU, thermals, memory, audio, and graphics.
  Require no page-protection fault, new hang, input regression, or worse
  Stop/relaunch. Static and donor evidence do not prove an iPhone FPS gain.

## Post-stall audio refill candidate (post-V0.26)

- SOURCE: isolated commit `e1d70c9f4`, selectively backported from the audio
  portions of upstream `14e740513`. Unrelated upstream changes were excluded.
- ROOT RISK: the callback ring previously retained only 20 ms above the
  configured target. After a renderer or compiler stall, a refill burst could
  silently lose an entire 256-sample block. At 48 kHz that is 5.33 ms and is a
  concrete match for the periodic knock/click reported during heavy 3D loads.
- FIX READY: ring capacity now retains 60 ms above the unchanged target, giving
  a stalled producer 40 ms more burst headroom without increasing the normal
  steady-state queue target. A whole-block push failure is counted and emits a
  rate-limited warning on the first and then every 64th drop instead of being
  silent.
- SAFETY BOUNDARY: sample format, downmix, resampling, time-stretch target,
  backend callback cadence, and ordinary latency policy are unchanged. The
  additional capacity is not a claim that RSX/PPU stalls are fixed, and a drop
  warning is evidence of starvation rather than permission to mask it.
- PASS STATIC/BUILD: `git diff --check`, the complete bounded iOS contract
  runner, and the incremental two-worker arm64 iOS core build pass. The
  combined post-V0.26 core identity after the tiled-blit candidate below is
  `77,495,936` bytes, SHA-256
  `76130a8fe2a4c5d1ba7d244b8a2a63be4a6f2f750db6524d34cdd2f4763dd369`,
  UUID `2AD96B4E-B4BE-3980-AAAC-AE317D74AB94`.
- REQUIRED PHYSICAL: in the same U1, RDR, U2/U3, and Sonic load transitions,
  capture the new drop warning, queued milliseconds, FPS, and audible output.
  Require no added steady-state latency, drift, fast audio, static, or teardown
  regression. Absence of a warning alone is not proof of clean audio.

## Tiled blit-bound renderer candidate (post-V0.26)

- SOURCE: isolated commit `8bb0deb0f`, based on upstream `37848abbc` and
  hardened after independent review. The broader texture-cache refactor and
  pitch-compatibility series remain excluded so this result stays attributable.
- ROOT RISK: the old blit-size heuristic could create a destination cache
  section beyond the active GCM tile. That can alias a neighboring tile and is
  a plausible source of stale rectangles, transient white/green blocks, or
  warped regions in U2/U3; it is not a generic FPS fix.
- FIX READY: representable destination sections are clamped to full rows that
  fit before the tile boundary. The cap is carried through the 720-line and
  matching-source-width expansions so neither can re-expand across the tile.
  Multiplication and end-address calculations use widened arithmetic.
- CORRECTNESS FALLBACK: when the payload fits only as a partial final row and
  no full rectangular cache section can satisfy both payload coverage and tile
  containment, the GPU/cache path returns before lock acquisition or cache
  mutation. NV3089 then uses its established CPU/tile copy fallback; the
  transfer is not silently discarded.
- UPSTREAM EDGE REPAIR: read-only review found that upstream ceiling division
  could overrun a non-pitch-aligned tile tail and that its later 720 minimum
  could undo a valid clamp. Both findings are covered by focused contracts for
  exact fit, floor clamp, partial tails, unrepresentable payloads, sub-720
  tiles, widened multiplication, and zero pitch. A second review found no
  remaining code issue.
- PASS STATIC/BUILD: `git diff --check`, two independent complete iOS contract
  runs, and a bounded two-worker arm64 iOS 15 core build pass. The active
  combined core is `77,495,936` bytes, SHA-256
  `76130a8fe2a4c5d1ba7d244b8a2a63be4a6f2f750db6524d34cdd2f4763dd369`,
  UUID `2AD96B4E-B4BE-3980-AAAC-AE317D74AB94`.
- REQUIRED PHYSICAL: compare U2 and U3 menus plus live 3D against V0.26 using a
  rebuilt graphics cache, then inspect RDR/U1 for regressions. Instrument or
  capture fallback frequency before attributing a performance cost. Require no
  green/pink cast, new rectangles, missing transfers, crash, or worse
  Stop/relaunch; a build cannot prove renderer correctness.

## Full-queue vblank liveness candidate (post-V0.26)

- SOURCE: isolated commit `f8fd9dae1`, selectively backported from upstream
  `c78913cfd`. Local differences are a shorter rationale and diagnostics on the
  first drop as well as every 1024th drop.
- ROOT CAUSE: `send_event()` retried `CELL_EBUSY` every 100 microseconds with
  no bound. If the guest interrupt thread stopped draining its 32-event queue,
  the periodic vblank producer became the waiter and stopped generating all
  future ticks, allowing the display pipeline to remain at zero FPS even after
  the original guest delay ended.
- FIX READY: only a full-queue event containing exclusively primary and/or the
  two supported secondary-head vblank bits is dropped. Those periodic bits are
  already explicitly loss/duplicate-tolerant in the existing `CELL_EAGAIN`
  assertion. Queue, flip, user, unmapped-memory, reserved, and every mixed event
  retain the original retry behavior.
- REPLAY/STOP BOUNDARY: a stale vblank-only replay can be dropped and setup
  retried once; non-vblank replay remains blocking. The early return can bypass
  the old stop check only for a disposable periodic tick. No event is falsely
  marked delivered, and no non-vblank bit is added to or removed from
  `unsent_gcm_events` differently.
- PASS STATIC/BUILD: independent read-only review found no issue;
  `git diff --check`, the complete bounded iOS contract runner, and the
  incremental two-worker arm64 core build pass. The combined unsigned core is
  `77,496,088` bytes, SHA-256
  `26f0fab419217781bb9d58f9fbd8c710925d315b296dee360a4a6febdf679020`,
  UUID `85B65975-D68E-308D-93F4-E879EE5995B2`.
- REQUIRED PHYSICAL: reproduce a title or failure path that fills the event
  queue, capture the first-drop warning with vblank/FPS recovery, and prove
  input, flip, Stop, immediate relaunch, and a second title remain correct.
  This protects liveness after a guest-side stall; it does not repair the guest
  mutex or prove higher settled FPS in U1/RDR.

## One-to-one blit interpolation candidate (post-V0.26)

- SOURCE: isolated commit `8a729951e`, semantically backported from upstream
  `32b711cdb` into the equivalent pre-refactor texture-cache branch.
- ROOT RISK: the memory-source blit path could honor a linear-filter request
  even when the guest operation was an exact 1:1 copy. Sampling adjacent texels
  in that case can blur or smear moving images, matching the reported RDR car
  and train presentation without implying a general shader failure.
- FIX READY: after a memory source is resolved, a copy with absolute X and Y
  scale both equal to one disables interpolation. Any real scaling retains the
  caller's filter. Render-target sources, including resolution-scaled sources,
  remain excluded and preserve their existing interpolation behavior.
- SAFETY BOUNDARY: 16/32-bit format conversion still uses typeless metadata;
  mirrored 1:1 scans still use their existing coordinate transform; DMA/null
  copies do not consume the flag. The final GL/Vulkan blitter is the only
  affected consumer. No cache identity, clipping, format, or destination
  selection changed.
- PASS STATIC/BUILD: independent read-only review found no issue;
  `git diff --check`, the complete bounded iOS contract runner, and the
  incremental two-worker arm64 core build pass. The combined unsigned core is
  `77,496,088` bytes, SHA-256
  `1dec6ab09436ba6fcfe896ab6f1815b77241cb50b80a5b4aa5195d03a72d0f45`,
  UUID `70FA71F1-B238-3A63-88D0-6DB5CCDA6945`.
- REQUIRED PHYSICAL: compare the exact RDR moving-car and train sequence to
  V0.26 after a clean graphics cache, then use U1 and U3 as visual controls.
  Require sharper 1:1 motion with no pixel shimmer, missing filtering during
  real scaling, color regression, block artifacts, or crash. This candidate
  makes no settled-FPS claim.

## V0.27 combined candidate (2026-08-31)

- SOURCE: packaged executable revision
  `0f57831d34fa93b99f843c760c5ac40a41851ccf`. Relative to V0.26, this adds
  the PPU range-lock wake, post-stall audio refill/drop telemetry, hardened
  tile-bound blit sizing, full-queue vblank liveness, and exact 1:1
  memory-blit sampling documented above. Vulkan/MoltenVK remains the selected
  game renderer; the native Metal presentation probe is unchanged.
- PASS PACKAGE: `ARMSX3-iOS-Core-Test-v0.27.ipa` is version `0.27.0`, build
  `26`, `31,865,916` bytes, SHA-256
  `f5eb3b64841e3d8ceaecc3dc8927976a911d6574463ce374e9494e143878230c`.
- PASS INDEPENDENT READBACK: a fresh temporary extraction passed full ZIP
  integrity, absence of `__MACOSX`, `codesign --verify --deep --strict`, and
  standalone embedded-core signature verification. The ZIP and extracted app
  each contain ten regular files. App and core are arm64 Mach-O binaries
  targeting iOS 15.0; the app links the core through `@rpath`, links
  GameController/Metal/UIKit, requires arm64 plus Metal, and declares iPhone
  and iPad device families.
- PASS ENTITLEMENTS: independent signature readback reports JIT, unsigned
  executable memory, Extended Virtual Addressing, increased memory limit, and
  `get-task-allow` true under `com.thec0de.armsx3ios`.
- PASS CORE IDENTITY: signed and unsigned cores share UUID
  `70FA71F1-B238-3A63-88D0-6DB5CCDA6945`. The unsigned core is `77,496,088`
  bytes with SHA-256
  `1dec6ab09436ba6fcfe896ab6f1815b77241cb50b80a5b4aa5195d03a72d0f45`;
  the independently extracted signed core is `78,119,808` bytes with SHA-256
  `d78b44d3d8df6d573a548541d0edb3d614bd49d205b36aac7f96227f2a31c263`.
  App UUID is `E6342429-CED6-3744-8D6A-468C7B8E09BD`. ABI 34, build-info,
  native-Metal-probe exports, and the new vblank/audio diagnostics are present;
  iOS 17.4-only `os_sync` imports and private local paths are absent.
- PASS TRANSFER/ROLLBACK: repository and iCloud V0.27 copies are byte-identical
  at the size and SHA above. V0.26 was hydrated from its iCloud dataless
  placeholder and reverified unchanged at SHA
  `c846c16862c690678e6c8ab97d94ef1cb1ae417187e1bae42c5eee95073e4457`;
  it was not overwritten. Earlier recorded V0.23-V0.25 rollback artifacts also
  retain their distinct filenames.
- RESOURCE SAFETY: packaging ran serially on the 8 GB Mac. After the package
  audit, only exact stale temporary audit extractions, one strip-test core, and
  duplicate log-archive tar wrappers were removed; source, crash evidence,
  signed IPAs, dependencies, and rollback artifacts were preserved.
- REQUIRED PHYSICAL ORDER: install this exact V0.27 SHA. First launch/Stop and
  immediately relaunch known-good local Bejeweled 3 or DuckTales. Then A/B the
  exact warm U1 and RDR gameplay scenes against V0.26 while capturing FPS,
  PPU/SPU/RSX/other CPU, memory/headroom, audio-drop telemetry, graphics, and
  Stop time. Use the RDR car/train sequence for 1:1 blur; cold-test U2/U3 with a
  rebuilt graphics cache for tile artifacts; exercise a full event queue for
  vblank recovery. Finish with GTA V child handoff, Sonic cache completion,
  sequential NETISO failure/recovery, background/foreground, input, rumble,
  Stop, and a second title. Static audit and packaging are not gameplay proof.

## Incompatible-pitch overlap candidate (post-V0.27)

- SOURCE: isolated commit `d24ca3a66`, adapted from upstream
  `d4b287944e1ee172935665384b25afbb8c8e292f` into this fork's older
  texture-cache architecture. The upstream 17-commit blit-destination
  surface-cache migration remains excluded; this candidate contains only the
  two ownership/range guards that are valid before that migration.
- ROOT RISK: the old blit sizing heuristic can pad a destination cache block
  across a later color/depth surface that has an incompatible pitch. A stale
  split can also replace an exact-address surface whose newer ownership cannot
  be preserved without pitch conversion. Either path can present neighboring
  memory as the active image, making it a concrete candidate for U2/U3 colored
  squares, warped regions, and directional smearing.
- FIX READY: guessed destination padding is truncated before the earliest
  newer incompatible-pitch color/depth surface. The safe length is floored to
  complete rows, but the actual write payload is always retained even when it
  ends inside the final row. Exact-address split reinsertion now preserves an
  equal/newer incompatible-pitch owner instead of invalidating it with stale
  data. Compatible, older, and non-overlapping surfaces keep their prior path.
- DIAGNOSTIC SAFETY: the exact-address conflict warning is emitted on
  occurrence `1, 2, 4, 8...` rather than for every conflict. This keeps the
  first marker and logarithmic lifetime counts while preventing the renderer
  path from recreating the iOS per-line logging/watchdog failure mode.
- PASS REVIEW/STATIC/BUILD: two independent read-only reviews found both donor
  halves present, correct iterator/range and tag semantics, preserved payload,
  safe alignment, no missing old-architecture integration, and no issue in the
  rate limiter. `git diff --check`, the complete bounded iOS contract runner,
  and a two-worker arm64 iOS core build pass. The resulting unsigned core is
  `77,497,664` bytes, SHA-256
  `2140bc83acb836f9492edc4c5167a6be1e5b083413fad556d730de7418b2c6dd`,
  UUID `FB0EA266-AEBB-37FE-BA97-FA51F3DC4F62`.
- PACKAGE STATE: not packaged. V0.27 remains the latest independently audited
  signed IPA and the immediate rollback. The Mac had only about 630 MiB free
  after the core relink, below the package script's 5 GiB safety floor; bypassing
  that guard would risk the workspace for no device evidence.
- REQUIRED PHYSICAL: package and install only after safe staging space is
  available. Rebuild the graphics cache, then repeat the same U2 and U3 menu
  and live-3D scenes enough times to distinguish a real change from first-run
  cache behavior. Capture conflict occurrence counts, cache invalidation and
  allocation markers, FPS/frame-time, process headroom, colors, blocks,
  warping, Stop, immediate relaunch, and a second title. Run the exact RDR
  car/train and warm U1 scenes as regression controls. Reject on missing writes,
  new corruption, crash, log growth, or worse teardown. Source/build evidence
  is not a renderer-correctness or FPS result.

## Serialized GTA child-handoff and Stop candidate (post-V0.27)

- SOURCE: isolated commit `652f9f7af`. This supersedes the incomplete
  `0fd9a4f3a` exitspawn attempt, which redirected guest `argv[0]` itself. The
  corrected path keeps guest-visible argv under
  `/dev_hdd0/game/PS3_GAME/...` while resolving only the host executable lookup
  through `/dev_bdvd/PS3_GAME/...`; title wrappers therefore retain their
  expected argument contract without requiring a copied disc tree.
- SESSION OWNERSHIP: iOS guest lifetime is now an explicit generation-owned
  state machine: `idle`, `active`, `stop_requested`, `cleanup_queued`, and
  `cleanup_armed`. Initial boot, child exitspawn, Stop, cleanup dispatch, normal
  handoff, and terminal failure all validate the same nonzero generation token.
  This closes the launch gate until teardown is genuinely complete instead of
  exposing a transient stopped state that permits overlapping guests.
- CALLBACK/THREAD SAFETY: exitspawn callback publication and Stop cancellation
  are serialized by the generation mutex. Emulator callbacks are mutated only
  on the RPCS3 main thread. The embedding contract now requires a non-null
  `main_thread_callback` that executes inline when already on that thread and
  otherwise enqueues there; the shipped iOS app already satisfies this in
  `ARMSX3CoreSession.mm`.
- STOP/BOOT SAFETY: all four initial boot APIs (Big Picture, XMB, installed
  title, and NETISO title) hold an in-flight boot claim and revalidate it before
  and after boot. Stop cancels NETISO immediately but defers emulator/callback
  mutation while inspection or `BootGame` is active. Cleanup queueing is
  deduplicated; enqueue failure rolls back to retryable `stop_requested`,
  including cleanup armed while a boot operation was still in flight.
- TERMINAL CLEANUP: normal continuous-mode process exit preserves the pending
  child handoff. A terminal crash instead clears Big Picture, continuous mode,
  ForceBoot, feedback, NETISO, and session ownership before returning idle.
  Repeated Stop requests cannot publish duplicate cleanup jobs or let stale
  argv, environment, disc path, data path, KLIC, or HDD1 ownership survive into
  a later generation.
- PASS CONTRACT/BUILD/AUDIT: `git diff --check`, the complete bounded iOS
  contract runner, and a two-worker arm64 iOS 15 core build pass. Focused
  contracts cover generation wrap/ownership, phase transitions, duplicate
  queue prevention, queue-failure rollback, terminal-versus-continuous release,
  and boot-operation deferral. Independent final review reports no remaining
  P0/P1/P2 finding. The resulting unsigned core is `77,520,344` bytes, SHA-256
  `a6a54ecbd7d6eaf1bfe1097db84c0d31d580737882cbc83b55232b1fbb8b25f4`,
  UUID `E670B5A0-2B71-3173-AF5D-F7001FC8710D`.
- PACKAGE STATE: not packaged and not physically run. V0.27 remains the latest
  independently audited signed IPA and immediate rollback. Source, contracts,
  compilation, and review do not prove the GTA child executable reaches live
  gameplay or that Stop timing is correct on a device.
- REQUIRED PHYSICAL: capture the GTA V Duplex transition showing original
  guest argv, redirected BDVD host lookup, and the actual GTA executable
  progressing beyond the prior black `Loading` state. Then deliberately fail a
  child launch and immediately scan/start another NETISO title. Exercise Stop
  during NETISO inspection, PPU/module boot, and exitspawn; repeated Stop taps;
  background then Stop; terminal child crash then clean relaunch; scheduling
  failure followed by a retrying Stop; and a second local/NETISO title. Require
  no stale mount, argv/environment/data/disc/KLIC/HDD1 state and preserve
  fail-closed behavior. Device logs and gameplay are mandatory evidence.

## Adaptive PPU precompile and Sonic diagnostics candidate (post-V0.27)

- SOURCE: isolated commit `c8b7fd651`; only `PPUThread.cpp` changes. The
  investigation confirms that a warm main-EBOOT cache suppresses the broad
  `Emu.GetGameDirs()` precompile scan. Sonic's repeated runtime popup is
  therefore consistent with a late PRX/overlay, a changing cache identity, or
  a child-process restart, but prior device logs did not identify the module
  and do not prove identical-object recompilation.
- BOUNDED DIAGNOSTICS: iOS logs distinct precompile begin, source, scan-complete,
  worker-end, and precompile-end markers. Source roots are capped at eight plus
  one truncation count. Cache misses identify path, SHA-derived cache directory,
  object, fragments scanned/total, check-only state, and process occurrence;
  the first 64 and then powers of two are retained to prevent unbounded logs.
  Dispatch and completion lines report configured worker limit, actual native
  starts, inline fallbacks, current-thread participation, headroom, and stopped
  state rather than presenting a maximum as completed work.
- ADAPTIVE WORKERS: the outer SPRX pool now uses short-lived pthread workers
  with explicit joins, 8 MiB stacks, and the existing adaptive iOS headroom
  policy. High/moderate/severe dispatch is capped at 4/2/1 workers. A nested
  `ppu_initialize()` remains on its owning outer worker instead of opening a
  second adaptive pool, so concurrent LLVM work does not multiply beyond that
  aggregate budget. Runtime-discovered modules outside the outer pool retain
  the normal adaptive inner parallelism.
- FAILURE SAFETY: pthread setup failure falls back inline without stranding an
  acquired compiler permit. Parent cleanup joins every started child before
  stack teardown; worker cleanup releases LLVM permits; outer-worker cleanup
  restores and notifies the file-memory budget before the parent join. Thread
  name and watchdog state use pthread cleanup on iOS. Impossible join failure
  aborts the process rather than detaching a worker whose context would be
  freed. Non-iOS retains its original named-thread path.
- NETISO BOUNDARY: this does not recursively rescan every warm NETISO game
  directory. Such a scan would enumerate/decrypt remote disc content on each
  launch and could make startup worse. The new identity evidence must first
  distinguish a genuinely missing late module from a restart or changing key;
  any later fix should use a targeted per-title completeness record.
- PASS STATIC/BUILD/AUDIT: `git diff --check`, the complete bounded iOS contract
  runner, and a two-worker arm64 iOS 15 core build pass. Multiple independent
  review rounds found and closed raw-thread registration, non-iOS forwarding,
  stack size, join/context lifetime, watchdog, semaphore, file-budget, parent
  cleanup, aggregate-limit, and log-bounding defects; final review reports no
  remaining P0/P1/P2 finding. The resulting unsigned core is `77,527,184`
  bytes, SHA-256
  `9ef3f2788521355c9cbab7e4308f3294be2a65df8b7dc4d5bec03fa2958ed24b`,
  UUID `09F84F1D-ED5B-375A-AA07-3D34E11BE036`.
- RESOURCE SAFETY: work stayed at `-j2` on the 8 GB Mac. The 145 MiB expanded
  Aug 30 temporary device log archive was losslessly preserved as the verified
  46,639,995-byte
  `/private/tmp/armsx3-recent-20260830.logarchive.tar.gz` before only its
  expanded temporary copy was removed. Source, dependencies, signed IPAs, and
  V0.26/V0.27 rollbacks were untouched.
- PACKAGE STATE: not packaged and not physically run. V0.27 remains the latest
  independently audited signed IPA. Compilation and review do not prove Sonic
  stops repeating work or that launch time improves on an iPhone.
- REQUIRED PHYSICAL: install the exact future packaged SHA and capture one cold
  plus two warm Sonic launches. For every `Compiling PPU modules` popup, retain
  the cache-miss path/object/key, precompile source/queue, child-process marker,
  worker counts, headroom, elapsed phase, and whether the object already exists
  next launch. Require warm reuse, bounded logs, no finalization stall, no
  thread/permit/file-budget deadlock, and clean Stop/relaunch. Then run a local
  title and a NETISO failure followed by a second title, plus warm U1/RDR, to
  reject startup, memory, graphics, audio, and gameplay regressions.

## V0.28 combined candidate (2026-08-31)

- SOURCE: packaged executable revision
  `18be3e5662c5918db93917b97649e9c648e7879c`. Relative to V0.27 this combines
  the incompatible-pitch ownership guard (`d24ca3a66`), serialized GTA
  child-handoff/Stop lifecycle (`652f9f7af`), and adaptive PPU/Sonic diagnostics
  (`c8b7fd651`). It does not claim or select a direct-Metal game renderer;
  Vulkan/MoltenVK remains the active gameplay path.
- PASS PACKAGE: `ARMSX3-iOS-Core-Test-v0.28.ipa` is version `0.28.0`, build
  `27`, `31,868,910` bytes, SHA-256
  `9a8276c864dbe6f26d586ee876817794715a37ea30262b957d59e7069fe33c4a`.
  The package was built serially from the independently hashed unsigned core
  and reports ABI 34 plus iOS 15.0 arm64.
- PASS INDEPENDENT READBACK: a fresh temporary extraction passed full ZIP
  integrity, absence of `__MACOSX`, `codesign --verify --deep --strict`, and
  standalone embedded-core signature verification. It contains nine regular
  files: app/core binaries, two controller skins, two icon renditions,
  `Info.plist`, `PkgInfo`, and `CodeResources`. The clean ad-hoc TrollStore build
  has no stale `embedded.mobileprovision`; signature entitlements identify
  `TROLLTROLL.com.thec0de.armsx3ios`.
- PASS ENTITLEMENTS/TARGET: readback confirms JIT, unsigned executable memory,
  Extended Virtual Addressing, increased memory limit, and `get-task-allow`.
  App and core are arm64 Mach-O binaries targeting iOS 15.0. The app supports
  iPhone and iPad, links the core through `@rpath`, and links
  GameController/Metal/UIKit. iOS 17.4-only `os_sync` imports are absent.
- PASS CORE IDENTITY: the unsigned and signed cores share UUID
  `09F84F1D-ED5B-375A-AA07-3D34E11BE036`. The unsigned core is `77,527,184`
  bytes with SHA-256
  `9ef3f2788521355c9cbab7e4308f3294be2a65df8b7dc4d5bec03fa2958ed24b`;
  the independently extracted signed core is `78,151,152` bytes with SHA-256
  `344aed3809471090f6952944a667a8a40eab2f00e48287e70c906649cd7b4fee`.
  App UUID is `E6342429-CED6-3744-8D6A-468C7B8E09BD`. ABI, NETISO boot/Stop,
  serialized session, preserved-argv exitspawn, adaptive PPU, and bounded
  cache-miss diagnostics are present; private local paths are absent.
- PASS TRANSFER/ROLLBACK: repository and iCloud V0.28 copies are byte-identical
  at the size and SHA above. V0.27 remains unchanged at SHA-256
  `f5eb3b64841e3d8ceaecc3dc8927976a911d6574463ce374e9494e143878230c`
  and is the immediate rollback; V0.26 was not touched.
- RESOURCE SAFETY: final core/app builds were limited to `-j2`/`-jobs 1`.
  Before packaging, the final core was copied and hash-verified, then only its
  reproducible CMake tree and Xcode DerivedData were removed to satisfy the
  5 GiB package floor. After readback, only temporary audit, staging, and app
  build trees were removed. The signed IPA, compressed device log archive,
  source, dependencies, and rollback packages were preserved; 5.4 GiB remains
  free.
- PHYSICAL STATE: untested. No compatible iPhone was connected during this
  package run, and the paired iPad lacks the required EVA execution lane. A
  signed IPA, static audit, and simulator are not PS3 gameplay evidence.
- REQUIRED PHYSICAL ORDER: install this exact V0.28 SHA. First launch and Stop
  known-good local Bejeweled 3, then immediately relaunch it. Test GTA V through
  Duplex and capture preserved guest argv plus redirected BDVD host lookup;
  deliberately fail one child executable, then scan/start another NETISO title.
  Exercise Stop during NETISO inspection, PPU compilation, and exitspawn plus
  repeated taps and background/foreground. Run Sonic once cold and twice warm,
  correlating every popup to path/cache/object/process identity and worker
  counts. Finally rebuild graphics cache for U2/U3 artifact scenes and use warm
  U1/RDR plus the RDR car/train as FPS/audio/visual regressions. Reject stale
  mounts or launch state, repeated identical cache work, deadlock, unbounded
  logs, new graphics corruption, worse FPS/audio, crash, or slow Stop/relaunch.

### V0.28 user physical heavy-3D result (2026-08-31)

- FAIL PHYSICAL / HEAVY 3D: the user reports that Uncharted 1, Uncharted 2,
  Uncharted 3, and Red Dead Redemption retain the same poor live-gameplay
  performance, and that the Uncharted sessions still crash. This rejects V0.28
  as a heavy-3D performance or stability milestone. Do not spend additional
  device time repeating those broad comparisons on this package.
- IDENTITY/EVIDENCE BOUNDARY: the report followed delivery of V0.28. The direct
  USB lane was subsequently restored for `iPhone14,3` on iOS 15.3, UDID
  `00008110-001C048C0C3B801E`, and the live `ARMSX3iOS` process was captured.
  This is sufficient to identify the GTA child failure below, but a separate
  warm-scene trace is still required before attributing any Uncharted/RDR crash
  or performance change to one source revision.
- SCOPE RETAINED: V0.28 remains an independently audited candidate for its
  serialized GTA child handoff, Stop cleanup, bounded PPU precompile, and Sonic
  cache diagnostics. None of those changes was a direct-Metal gameplay renderer
  or a demonstrated settled-gameplay FPS improvement.
- NEXT MEASURED TARGET: archived RDR and U1 physical traces prove that both
  titles detect multiple PUTLLC16 candidates while accurate SPU reservations
  reject them. RDR also detects the dormant CellSpurs JobChain pattern hash
  `620oYSe8uQqq9eTkhWfMqoEXX0us`. Do not enable the reverted generic
  writer-lock bypass: upstream reverted it after a real `SEGV_ACCERR`. Before
  admitting any target hash, retain and disassemble its exact guest bytes and
  prove that only one 16-byte quadword is consumed and written, with no later
  use of the other 112 reservation bytes. A hash-gated candidate then requires
  same-scene failure-rate, frame-time, graphics, crash, and Stop A/B evidence.

### V0.28 GTA V child boot failure and candidate repair (2026-08-31)

- FAIL PHYSICAL / V0.28: GTA V `BLES01807` reaches and runs `duplex.self`, then
  displays `HDD boot game is corrupted. The application will be terminated.` A
  repeated launch on the same package reaches the same error; no further V0.28
  retries are useful.
- ROOT CAUSE EVIDENCE: the device process trace records two immediate
  `sys_fs_stat` failures with `CELL_ENOENT` for the exact guest path
  `/dev_hdd0/game/PS3_GAME/USRDIR/common.edat`. The active PPU cache path is
  `cache/BLES01807/ppu-...-duplex.self`, proving that the wrapper executable did
  boot. V0.28 redirects only the child executable lookup to `/dev_bdvd`; it
  deliberately preserves guest `argv[0]`, so subsequent literal guest file
  access still sees an unmounted HDD-shaped placeholder.
- EVIDENCE FILES: the process-only trace is
  `/private/tmp/armsx3-gta-v028-process.log`. The complete device archive is
  retained as
  `/private/tmp/armsx3-gta-v028-20260831-0846.logarchive.tar.gz`; it was losslessly
  compressed from 130 MiB to 35 MiB to protect the Mac's limited disk.
- CANDIDATE REPAIR: the iOS guest-session owner now records whether the launch
  came from `rpcs3_ios_boot_netiso_game`. On `on_ready`, only title `BLES01807`
  with a live nonzero session generation, continuous child mode, NETISO origin,
  and a canonical virtual ISO/NETISO `/dev_bdvd/PS3_GAME` source may mount the
  compatibility alias `/dev_hdd0/game/PS3_GAME` to that same virtual disc tree.
  XMB, installed games, initial NETISO executables, local discs, other titles,
  stale generations, and prefix lookalikes fail closed.
- CLEANUP CONTRACT: Stop, terminal child failure, shutdown, and failed launch
  rollback clear the NETISO-session/alias state. The VFS itself is recreated for
  each emulator load, preventing a compatibility mount from crossing into the
  next session.
- STATIC VERIFICATION: `IOSExitspawnDiscPathPolicyTests` passes under C++20 with
  `-Wall -Wextra -Werror`; the full bounded
  `rpcs3/ios/tests/run-contract-tests.sh` suite passes, including `NETISO
  cancellation contract PASS`; `git diff --check` passes. This is not yet a
  build or physical fix. The next gates are an iOS core compile, independently
  audited signed IPA, then physical proof that `common.edat` resolves and GTA
  advances beyond the corruption dialog without poisoning Stop/relaunch.

## V0.29 GTA V disc-alias and bounded PUTLLC16 candidate (2026-08-31)

- SOURCE: pushed `ios-core` revision
  `693fae776c095a5612b889cba712464fee47ffbb`. The candidate includes the
  exact-title GTA V NETISO child alias above and the hash-gated iOS PUTLLC16
  admission for the known upstream pattern plus the captured RDR CellSpurs
  JobChain pattern. It does not include or select the unfinished native-Metal
  renderer files; Vulkan/MoltenVK remains the gameplay renderer.
- PASS BUILD: the clean iOS 15 arm64 core build completed with `-j2`. One first
  compile correctly rejected an implicit conversion from RPCS3's explicit
  config boolean to `bool`; the call now uses `static_cast<bool>`, and both the
  resumed build and final post-commit relink pass. The full bounded contract
  suite and `git diff --check` pass.
- PASS PACKAGE: `ARMSX3-iOS-Core-Test-v0.29.ipa` is version `0.29.0`, build
  `28`, `31,871,458` bytes, and SHA-256
  `1ef9bcf6c458108d11120b60370364cefac644301ff8f90d43a5a06322f4fe21`.
  The first independent readback caught a stale hard-coded build `27`; that
  package was rejected before transfer, the plist was corrected, and the IPA
  was rebuilt from the pushed revision above.
- PASS INDEPENDENT READBACK: a fresh temporary extraction passed ZIP integrity,
  absence of `__MACOSX`, strict deep app signature verification, standalone
  core signature verification, and the private local path/address scan. The
  archive contains nine regular files. App UUID is
  `E6342429-CED6-3744-8D6A-468C7B8E09BD`; core UUID is
  `1C944246-68F2-3EF5-B765-5AAC9ECD3650`. The unsigned core is `77,544,520`
  bytes with SHA-256
  `0a5bb7ca5491492babc47d84ed6331a453486db25785a8cd91449f02cbe7097b`;
  the extracted signed core has SHA-256
  `760ffbc455e007d02a70f2291efc4d6f45e783486b746759b887d3f8edc9f390`.
- PASS TARGET/CONTRACT: app and core are arm64 Mach-O binaries targeting iOS
  15.0. Readback confirms ABI 34, NETISO boot/Stop exports, the GTA alias marker,
  and the bounded PUTLLC16 admission marker. The signature contains
  `get-task-allow`, JIT, unsigned executable memory, Extended Virtual
  Addressing, and increased-memory-limit entitlements under
  `TROLLTROLL.com.thec0de.armsx3ios`.
- PASS TRANSFER: the repository artifact and iCloud Drive copy at
  `ARMSX3-iOS-Core-Test-v0.29.ipa` are byte-identical at the size and SHA above.
  Normal Installation Proxy reaches verification and rejects the TrollStore
  ad-hoc signature with expected error `0xe8008014`; USB port 22 is not exposed,
  so this device requires installation through TrollStore from iCloud Drive.
- RESOURCE SAFETY: obsolete browser/update caches and only archived superseded
  IPAs were removed. The clean feasibility checkout was copied to
  `/Data/dockerprojects/armsx3-ios/checkpoints/ARMSX3-ios-feasibility-20260831`.
  Its `.git` metadata was restored locally after preflight proved that
  `ARMSX3-ios-core` is a linked worktree; never delete that common metadata while
  this worktree exists. V0.26-V0.28, Codex history, dependencies, and device
  evidence remain preserved.
- REQUIRED PHYSICAL: install this exact V0.29 SHA with TrollStore. Launch GTA V
  fresh and retain the alias-mount line plus the first `sys_fs_stat` result for
  `common.edat`; require progress beyond the V0.28 corruption dialog. Then Stop,
  launch one unrelated local or NETISO title, Stop, and launch GTA V again to
  reject stale aliases or session poisoning. RDR/U1 performance remains an
  unproven A/B gate; a successful package or GTA boot is not a heavy-3D FPS
  claim.

### V0.29 physical rejection and V0.30 GTA original-executable candidate (2026-08-31)

- FAIL PHYSICAL / V0.29: the user installed the exact V0.29 TrollStore package
  and GTA V `BLES01807` again displayed `HDD boot game is corrupted. The
  application will be terminated.` V0.29 is rejected as a GTA boot fix; do not
  repeat it.
- DEVICE EVIDENCE: `/private/tmp/armsx3-gta-v029-live.log` records the initial
  NETISO boot, two completed `/dev_hdd1/duplex.self` handoffs, two successful
  exact-title alias mounts, and the guest EBOOT redirect from
  `/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN` to
  `/dev_bdvd/PS3_GAME/USRDIR/EBOOT.BIN`. The core remained live near 56-58 FPS
  while the corruption dialog was visible, proving the alias and redirect ran
  but did not supply the modified wrapper's absent payload.
- SOURCE LAYOUT: the authoritative NETISO source is
  `/NAS/Consoles/roms/Playstation_3_Games/GAMES/BLES01807-[Grand Theft Auto V]`
  through `192.168.10.144:38008`. `PS3_GAME/USRDIR` has no `common.edat`; it has
  `BOOT.BIN` (67,124 bytes), modified `EBOOT.BIN` (15,023,168 bytes), and
  preserved `EBOOT.BIN.ORIG` (14,564,408 bytes). SHA-256 values are respectively
  `cda8f73f0ec20b76dcc030b52195fbb9fb51e94bb36acccb45e159d98293a9f8`,
  `8cd96122a52a96fd1c673fca06d5ace70403eb0e037e9550aa0ed5506e1b4cb7`, and
  `dbe129873ea26e8e9066e1a32e026aa58beb09e0eeca90b9370169a50b42bb16`.
- V0.30 CANDIDATE: iOS disc-archive selection bypasses the modified wrapper and
  boots `EBOOT.BIN.ORIG` only for exact title `BLES01807` and only when both the
  standard and preserved executables exist. Other title IDs, missing original,
  missing standard executable, non-iOS builds, and install-disc behavior retain
  the prior path and therefore fail closed.
- STATIC GATE: the expanded `IOSExitspawnDiscPathPolicyTests` and full bounded
  `rpcs3/ios/tests/run-contract-tests.sh` suite pass, including NETISO
  cancellation; `git diff --check` passes. This is not a physical fix claim.
  Required proof is the exact V0.30 package log marker selecting
  `EBOOT.BIN.ORIG`, followed by progress beyond the corruption dialog, then
  Stop/relaunch and an unrelated-title launch to reject stale state.

#### V0.30 audited package

- SOURCE/BUILD: committed source `e5782041a9a3847a10c2c9e1296462fd8216b6d1`
  compiled incrementally with two workers and linked successfully. The only
  compile diagnostic was the pre-existing unused `this` lambda-capture warning
  in `System.cpp`; the bounded contracts and diff check remained green.
- PACKAGE: `ARMSX3-iOS-Core-Test-v0.30.ipa` is version `0.30.0`, build `29`,
  `31,871,545` bytes, and SHA-256
  `9f14512391bc5d50b3055287d52eddee6b918f211a39b69d4e78d27d2058adb4`.
- INDEPENDENT READBACK: a fresh temporary extraction passed ZIP integrity,
  nine-file inventory, absence of `__MACOSX`, strict deep app signature and
  standalone core signature verification, and private-path scanning. App UUID
  is `E6342429-CED6-3744-8D6A-468C7B8E09BD`; core UUID is
  `76BBECC9-5EF0-3767-B56C-80562A89D964`. The unsigned core SHA-256 is
  `41de14dfaa5f0bb95d4d4ee8f27e5cd2fd99eee49f9916aa4170f3b7287bcf6b`;
  extracted signed-core SHA-256 is
  `c7556bc8bdfc6da2fd8f96cce5be205c5643c025aa61b59dedffdf2e1d42ef52`.
- TARGET/CONTRACT: app and core are arm64 Mach-O binaries targeting iOS 15.0.
  Readback confirms ABI 34, NETISO boot and Stop exports, the exact preserved
  EBOOT selector marker, GameController/Metal/UIKit linkage, and no iOS
  17.4-only `os_sync` imports. Signature readback confirms `get-task-allow`,
  JIT, unsigned executable memory, Extended Virtual Addressing, and increased
  memory limit under `TROLLTROLL.com.thec0de.armsx3ios`.
- TRANSFER: repository artifact, iCloud Drive copy, and NAS checkpoint at
  `/Data/dockerprojects/armsx3-ios/checkpoints/ARMSX3-iOS-Core-Test-v0.30.ipa`
  are byte-identical at the SHA above. V0.29 remains the immediate physical
  failure reference; no rollback package or unfinished native-Metal file was
  modified.
- OPEN PHYSICAL GATE: package correctness is proven, GTA boot correctness is
  not. Install this exact V0.30 through TrollStore and launch BLES01807 once
  while capturing the selector marker and first outcome. Accept only progress
  beyond the corruption dialog; then perform Stop/relaunch and an unrelated
  title to reject stale session state.

### V0.30 physical GTA boot result and V0.31 streamed-install candidate (2026-08-31)

- PASS PHYSICAL / ORIGINAL EXECUTABLE: the exact V0.30 package selected
  `EBOOT.BIN.ORIG`; its PPU cache identity includes `EBOOT.BIN.ORIG`, and about
  176 original-executable modules compiled before boot. GTA V advanced beyond
  the repeatable V0.28/V0.29 `HDD boot game is corrupted` termination. V0.30
  therefore closes that wrapper/executable blocker, but it is not a gameplay
  or performance pass.
- NEW PHYSICAL BLOCKER: GTA created local metadata under
  `/dev_hdd0/game/BLES01807_install`, then failed to find `part0.rpf` through
  `part3.rpf` and `common.rpf` in its local `USRDIR`. It subsequently displayed
  `ERROR: Not enough available space. The application will be terminated.` The
  complete live trace is `/private/tmp/armsx3-gta-v030-live.log`.
- SOURCE SIZE: the authoritative streamed GTA `USRDIR` contains `common.rpf`
  plus `part0.rpf` through `part4.rpf`, totaling 8,898,562,048 bytes. Duplicating
  that immutable set into the app container is unnecessary and exceeds the
  capacity reported through the current device service.
- CAPACITY DISCREPANCY: iPhone14,3 iOS 15.3 Settings reports 161.9 GB used of
  256 GB, while the same connected device's lockdown disk-usage domain reports
  3,169,738,752 bytes immediately data-available and 5,629,984,768 bytes total
  data-available. The core subtracts a 1-GiB safety reserve from host `statfs`;
  it does not impose a fixed 5-GiB app quota. V0.31 adds in-sandbox telemetry
  for filesystem-free, Foundation volume-available, important-usage, and
  opportunistic-usage capacity. Do not globally advertise fictitious capacity
  until this physical readback proves what the sandbox can actually reclaim.
- V0.31 CANDIDATE: only exact title `BLES01807`, from a live nonzero-generation
  NETISO session with a canonical virtual ISO/NETISO source, may mount
  `/dev_hdd0/game/BLES01807_install/USRDIR` onto the streamed
  `/dev_bdvd/PS3_GAME/USRDIR`. Local metadata remains local; the 8.90-GB RPF set
  stays remote. Other titles, local launches, stale/zero generations, and
  non-virtual sources fail closed.
- CLEANUP/EMUHUB CONTRACT: streamed aliases have independent generation-owned
  state and are removed on Stop, terminal child failure, shutdown, and failed
  launch cleanup before the NETISO device is cancelled. EmuHub's future ISO
  service should preserve this split-storage/VFS contract while replacing only
  the byte-serving backend; it must not force full-game copies into iOS storage.
- STATIC GATE: the expanded exact-title policy tests and complete bounded
  `rpcs3/ios/tests/run-contract-tests.sh` suite pass, including NETISO
  cancellation; `git diff --check` passes. Build/package and physical progress
  beyond the space dialog remain open.
