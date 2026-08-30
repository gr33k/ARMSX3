# ARMSX3 iOS test status

## 2026-08-29 real-core IPA checkpoint

Source:

- Public fork: `gr33k/ARMSX3`, branch `ios-core`
- iOS base: `XITRIX/rpcs3` `ios-port` revision
  `e422589696e480b52c3e083e34e18ccd5a74cc0f`
- ARMSX3 comparison revision:
  `a74a0f3e045f064515a5fa48643e66ab386577d3`
- Core ABI: `29`

Pinned dependencies:

- MoltenVK `1.4.2`, SHA-256
  `b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1`
- iOS 15 LLVM SDK revision `ca7933e47d3a3451-ec81b2304bcb`, SHA-256
  `138446dbbd497f1c18a741aab85b27982ec62099f13e39f81abfbdc901160583`
- FFmpeg `8.1.1`, SHA-256
  `b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3`

Static core gates:

- PASS: all `1,292` Ninja edges built with `-j2` for arm64 iOS 15.0.
- PASS: `libRPCS3Core.dylib` is a 78,017,952-byte arm64 Mach-O with minimum
  iOS 15.0 and the expected ABI 29 C exports.
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
- V0.3 BUILD PENDING: app version `0.3.0`/build `2` adds an explicit native
  `Open XMB` action through the existing `rpcs3_ios_boot_vsh()` export.

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
- PENDING: audio accuracy, sustained FPS, thermals, V0.3 second-boot cache
  reuse, multi-touch accuracy, Stop during compilation, clean Stop/relaunch,
  and XMB evidence.

The current result is a physically launched real-core IPA with real Bejeweled 3
and Zuma gameplay. V0.3 has crossed the former finalization stall for a newly
compiled title, while V0.2 remains the captured failure baseline. Qualification
remains open until the path-scrubbed V0.3 replacement passes artifact audits and
the device passes clean-install first boot, measured multi-touch, audio,
sustained FPS, Stop, relaunch, and XMB gates.

## Storage and network-disc checkpoint

- PASS: the live private-NAS standard `ps3netsrv` endpoint on port `38008`
  accepted NETISO directory, stat, open, and random-read commands from an
  independent client probe.
- FAIL: importing Red Dead Redemption still requires a full local copy and the
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
- REQUIRED: implement a read-only NETISO virtual filesystem so local EmuHub
  storage and user-entered standard `ps3netsrv` servers share one streaming
  client. Keep saves, patches, PPU objects, shaders, and title metadata local.
- REQUIRED: EmuHub's admin panel remains authoritative for managed host paths,
  Docker bind mounts, source ordering, and enable/disable state. See
  `PS3_NETWORK_DISC_DESIGN.md`.
