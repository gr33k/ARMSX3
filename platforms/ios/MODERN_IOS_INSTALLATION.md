# Modern iOS installation investigation

Updated 2026-09-03. Research and source inspection, not a newly qualified build.
Retain native Metal, CPU/PPU/SPU, audio, controls, lifecycle and game-loading work.

## Separate the gates

1. Installation/signing: a free Personal Team can provision apps, with three
   installed apps per device and seven-day profiles. SideStore can manage
   refreshing; this is not TrollStore-like permanent installation.
2. JIT: modern debugger-based methods need get-task-allow and, on TXM/SPTM
   devices, app-side executable-region preparation. Our Universal-JIT allocator
   and LLDB helper already exist; matching StikDebug automation remains to be
   verified on the exact OS/device. A helper reporting success is not code proof.
3. Virtual address space: current VMLayoutPolicy.h reserves 8 GiB guest/mirror,
   12 GiB executable metadata and 4 GiB static regions. This 24-GiB address-space
   reservation is NOT 24 GiB of resident RAM or storage. The unused 32-GiB desktop
   hook reservation is already omitted on iOS. Do not repeat that optimization
   or claim it eliminates the remaining reservation requirement.
4. Physical memory: available process headroom is separate from address space.
   Increased-memory entitlements on supported hardware can improve headroom;
   device RAM alone does not guarantee the app may use it all.

## What is actually established

- The recorded V0.21 M2/iPad14,3 iPadOS 26.3.1 test installed a free-signed app
  and prepared all 28 x 16-MiB Universal-JIT regions through LLDB/debugserver.
  Startup then failed the VM reservation. The installed profile lacked EVA;
  manually adding unsupported memory entitlements caused profile rejection.
- These are historical physical results in TEST_STATUS.md, not a fresh test of
  V0.35/V0.36 or the latest OS. The previously paired iPad was not found by this
  turn's device-info query. No new installation, signing or account purchase ran.
- Apple's capability table currently marks Extended Virtual Addressing for ADP
  and ADEP, with the free Apple Developer column empty. The raw HTML row was
  checked because the text-only table omitted its checkmark icons.
- TrollStore's official support stops at specific older versions through 17.0;
  it is not the installation path for an up-to-date device.
- StikDebug documents iOS 26+ as app-dependent. SideStore additionally warns
  about restricted compatibility on 26.6/27. Recheck exact version support;
  neither documentation nor our older LLDB result qualifies ARMSX3 today.

## Routes to investigate

- Existing core, eligible development team: obtain a profile actually granting
  EVA, preserve get-task-allow, install a development-signed build, prepare JIT,
  and verify reservation/guest boot. Membership alone neither enables permanent
  JIT nor proves gameplay. Verify team permissions before spending money.
- Free-account target: keep ordinary renewable signing, but investigate a
  genuinely compact/segmented guest-memory layout within the available virtual
  address space. Audit JIT address assumptions, memory mirrors, protection and
  reservation semantics before implementation; never return unreserved pointers
  to bypass failure. This is significant core work, not another signer setting.
- Do not present LiveContainer, a VPN, different signers or a Metal backend as
  granting EVA. Do not switch to interpretation or remote rendering silently.
- Keep the TrollStore artifact separate from a modern development-signed
  artifact. Do not suggest that the TROLLTROLL identity can be installed as-is.

## Low-cost next experiment

Read exact model/OS and the installed profile first. Then qualify a small
signing/JIT/address-space probe without firmware, game downloads or a full
emulator rebuild. Measure address limits on each new device; do not extrapolate
the tested M2 limit to every future device or confuse reserved-byte totals with
the full aligned address span. For a non-EVA layout prototype, test memory alias/protection
correctness before benchmarking. Consider delayed core loading so failed
capability checks can show a useful setup screen instead of a pre-UI abort.
Only after these gates pass, test a known-working game, rotation, background/
resume, Stop and second launch. Do not use a Metal triangle as this evidence.

## PS3 content direction

EmuHub must serve both its mounted ISO files and extracted game folders. NETISO
is chiefly standalone and optional in EmuHub; standalone should support both
an authenticated EmuHub source and standard NETISO. Admin/Docker source config
may generate connection settings, but must not require public NETISO exposure,
admin credentials in exports or privileged host mounting. Source-specific byte
transport should reuse the same native virtual-disc/file semantics.

## Primary references checked

- [Apple Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple iOS capability membership table](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [Extended Virtual Addressing](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.extended-virtual-addressing)
- [Increased memory limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
- [TrollStore supported versions](https://github.com/opa334/TrollStore)
- [StikDebug compatibility](https://github.com/StikDebug/StikDebug)
- [StikJIT integration protocol](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md)
- [SideStore current JIT warnings](https://docs.sidestore.io/docs/advanced/jit)
