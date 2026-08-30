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
- MEDIA REPAIR READY / PHYSICAL PENDING: the extracted Uncharted 1 `BCES00065`
  folder was using a modified debug/FSELF `EBOOT.BIN` (SHA-256
  `1d97d8e3ab6ff860df418dc664876dd54b6fb98f6fa8e2a4b5e0f0721d0a6355`).
  It is preserved as `EBOOT.BIN_EMUHUB_BACKUP_20260830_0800`; the folder's
  preserved retail `EBOOT.BIN_CEX` is now active as `EBOOT.BIN` (SHA-256
  `bcbd125bc0614fb5994d30f2e82c6510aaaf2fc6c51f917c4953d4a210b32bd4`).
  After restarting only `ps3netsrv`, a NAS-local protocol probe enumerated 60
  extracted titles and passed an ISO PVD random read on the rebuilt Uncharted
  virtual image at `22,654,615,552` bytes. Real gameplay remains unverified.
- PASS SERVER / NO UPDATE AVAILABLE: the running container already uses
  `ps3netsrv` build `20250501`, current image digest
  `sha256:f23497ba5c34099e65c3a0590f5dfd0ee21c5c66f592a644aafb2d88f3d60e1e`.
  Pulling `shawly/ps3netsrv:latest` confirmed it is current, so no image or
  Compose replacement was performed.
- FAIL PHYSICAL / GOD OF WAR ASCENSION: V0.7 title `BCES01741` reaches the
  Duplex screen and loops back to it repeatedly. No connected-device core log
  was available, so child-SELF handoff, guest failure, and media modification
  remain open; no fix is claimed in V0.8.
- REQUIRED PHYSICAL GATES: install the exact V0.8 bytes and first tap every
  D-pad cardinal/diagonal plus sweep both analog sticks while confirming `PAD
  OK` and live values. Then verify guest response, edge-to-edge landscape,
  simultaneous stick/face input, Stop/relaunch, repaired Uncharted 1 boot,
  Uncharted 2, and the God of War loop. Preserve `ARMSX3-last-session.log` after
  any failure. Package/static checks do not close these gates.

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
