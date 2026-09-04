# Modern iOS installation investigation

Updated 2026-09-04. Installation and wired JIT execution verified on one M2
iPad; VM startup still fails and modern-iOS gameplay is not qualified.
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
- The V0.21 result is historical. On September 4 the same M2/iPadOS 26.3.1 device was reached
  by USB and updated in place to development-signed V0.37. Installed readback
  confirms 0.37.0/get-task-allow=true, with neither EVA nor increased-memory
  rights. Backup and SideStore retained; no paid account used.
- Fresh V0.37 wired test: all 448 MiB of Universal-JIT regions prepared. An
  eight-byte function allocated in the core's arena, written through its RW
  alias, flushed and called through its RX address returned the expected 42;
  allocation released. This is actual generated-code execution, not a helper's
  success status. StikDebug automation and untethered operation remain open.
- Real V0.37 startup still aborts in _GLOBAL__sub_I_vm.cpp after JIT succeeds.
  Pre-initializer probes independently rejected the required 8-GiB reservation
  through mmap (ENOMEM), vm_allocate and mach_vm_allocate (KERN_NO_SPACE).
  A 4-GiB control allocation succeeded and was released. PROT_NONE versus RW
  did not repair the failed 8-GiB mmap. No large physical pages were touched.
  This is not resolved by a different signer or replacing Metal/MoltenVK.
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

Read exact model/OS and the installed profile first. September 4 qualified a small
generated-code test and safe reservation probes in the stopped V0.37 process;
TEST_STATUS.md records exact results. Do not rerun that failure unchanged.
For a new profile or layout candidate, qualify a small
signing/JIT/address-space probe without firmware, game downloads or a full
emulator rebuild. Measure address limits on each new device; do not extrapolate
the tested M2 limit to every future device or confuse reserved-byte totals with
the full aligned address span. For a non-EVA layout prototype, test memory alias/protection
correctness before benchmarking. Consider delayed core loading so failed
capability checks can show a useful setup screen instead of a pre-UI abort.
Only after these gates pass, test a known-working game, rotation, background/
resume, Stop and second launch. Do not use a Metal triangle as this evidence.

### Reproducing the bounded wired probe

1. Launch the exact installed development app with devicectl --start-stopped;
   select the physical device and attach LLDB to ARMSX3iOS. Import the existing
   scripts/lldb_universal_jit.py and run armsx3-jit-install before continuing.
2. Break on _GLOBAL__sub_I_vm.cpp. memory_reserve_4GiB is inlined in V0.37 and
   does not resolve as a separate breakpoint. After the helper adjusts PC,
   LLDB can display a stale frame name: verify register read pc against the
   initializer breakpoint address. Check the protocol breakpoint hit count.
3. Resolve current load addresses of allocate, writable, flush and
   release_allocation in rpcs3::ios::jit through LLDB FindFunctions; never reuse
   ASLR addresses from another launch. Allocate(true,8,16), obtain writable
   alias, write 0x52800540/0xd65f03c0, flush eight bytes, call RX pointer as
   int(*)(), then release_allocation(true,pointer,8). Expected result is 42.
   This checks the core allocator, not only LLDB's own expression JIT.
4. Probe mmap with PROT_NONE first, flags 0x1042, fd -1, offset 0. Record actual
   pointer versus requested hint, errno on failure, and unmap result on success.
   Never use MAP_FIXED, bypass failure or touch the reserved GiBs. Mach VM
   controls must also deallocate successful requests. vm_allocate is the public
   iOS interface; mach_vm.h is explicitly unavailable in the iOS SDK, so its
   debugger-only comparison is not an implementation recommendation.
5. A breakpoint on abort can capture the real failing initializer after probes
   are released. End only that known pre-UI diagnostic process, then quit LLDB;
   preserve crash reports with idevicecrashreport --keep and narrow date/name
   filtering. Do not repeatedly run the same failed build as a game benchmark.

## Primary references checked

- [Apple Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple iOS capability membership table](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [Extended Virtual Addressing](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.extended-virtual-addressing)
- [Increased memory limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
- [TrollStore supported versions](https://github.com/opa334/TrollStore)
- [StikDebug compatibility](https://github.com/StikDebug/StikDebug)
- [StikJIT integration protocol](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md)
- [SideStore current JIT warnings](https://docs.sidestore.io/docs/advanced/jit)
