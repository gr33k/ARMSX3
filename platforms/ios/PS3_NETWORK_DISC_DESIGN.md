# EmuHub PS3 network-disc contract

## Product boundary

EmuHub owns PS3 library configuration. NETISO is a read-only transport, not a
second library database. The iOS client must accept either source type through
the same virtual filesystem:

1. **EmuHub managed** - host paths and Docker bind mounts are configured in the
   EmuHub admin panel. EmuHub publishes the normalized NETISO namespace and
   advertises it on the LAN.
2. **Standard ps3netsrv** - the user enters a server IP or hostname and port
   (default `38008`), or selects a server found by bounded LAN discovery.

No PS3 image is copied into the iPhone sandbox for streamed launches. Firmware,
save data, patches, PPU/SPU objects, shader caches, and game metadata remain
local so normal RPCS3 title-ID patching and cache reuse are preserved.

## Managed roots

The admin panel stores an ordered list of enabled mounts. Each entry has a
stable ID, display name, content kind, host path, container path, read-only
flag, priority, and scan state.

| Content kind | NETISO path | Purpose |
| --- | --- | --- |
| `ps3-folder` | `/GAMES` | Extracted PS3 disc folders |
| `ps3-iso` | `/PS3ISO` | PS3 ISO files and supported split images |
| `ps2-iso` | `/PS2ISO` | PS2 compatibility library |
| `ps1-iso` | `/PSXISO` | PlayStation compatibility library |
| `psp-iso` | `/PSPISO` | PSP compatibility library |

Multiple host paths may map to one content kind. EmuHub merges them in admin
priority order and rejects ambiguous duplicate virtual names instead of
silently selecting an arbitrary file. Existing `/roms/<system>` mounts remain
valid; generated Compose must preserve unrelated custom mounts exactly.

ARMSX3 consumes only `/GAMES` and `/PS3ISO`. EmuHub routes `/PS2ISO`,
`/PSXISO`, and `/PSPISO` entries to its PS2, PlayStation, and PSP runtimes. The
folders remain visible on a standard server because a real CFW PS3 can consume
them, but they are not misreported as PS3 titles in the ARMSX3 library.

## Client configuration and discovery

Each saved server contains `sourceType`, `host`, `port`, optional TLS/LAN trust
metadata, enabled state, and last successful capability probe. Port `38008` is
the default but is always editable.

EmuHub-managed servers advertise `_emuhub-netiso._tcp` with a stable server ID
and protocol version. The Add Server screen performs Bonjour discovery and,
when the user enables legacy discovery, a bounded scan of the phone's current
IPv4 subnet for the selected port. Scanning is concurrency-limited, cancellable,
and never runs continuously in the background. Manual host and port entry is
always available and is the compatibility floor for unmodified `ps3netsrv`.

Discovery is not acceptance. Before saving a source, the client must complete
an actual NETISO directory probe and display the roots returned by that server.

## Virtual filesystem

The iOS core implements a read-only `fs::device_base` backed by NETISO stat,
directory, open, and offset-read commands. It supports both ISO files and
extracted `GAMES/<title>` trees. The device provides:

- persistent TCP connections with reconnect and request serialization;
- big-endian packed NETISO command encoding with strict response bounds;
- 1 MiB aligned per-file read-ahead with one bounded buffer per open file;
- cancellation and finite connect/read deadlines;
- immutable file identity checks across reconnects;
- monotonic byte/read/cache-hit/reconnect counters from which the wrapper
  calculates live throughput;
- fail-closed behavior on short reads or changed remote file identity.

The existing ISO parser and game-folder boot code read through this device.
Title discovery still derives the title ID and metadata through the normal PS3
content path, so patch selection is not bypassed.

Exactly one active backing is retained for the selected `/PS3ISO` image or
server-generated `/***PS3***/GAMES/<title>` virtual image. The backing is
published before its potentially slow connect/open operation so the independent
Stop path can cancel an in-progress server-side VISO build. Cancellation is
terminal for that connection: it performs `shutdown(SHUT_RDWR)` to wake blocked
I/O, prevents reconnect, and leaves final descriptor close to the owning
operation. Failed metadata inspection, failed `BootGame`, explicit Stop,
server replacement, disconnect, and core shutdown all retire the active mount.
A subsequent launch therefore starts from a fresh backing instead of consuming
the stale connection's full timeout and blocking the serial core queue.

Container health and server-process health are distinct. The current
`shawly/ps3netsrv` image supervises `ps3netsrv` inside a still-running container;
therefore EmuHub health checks must probe the protocol and detect an internal
process restart rather than trusting Docker's container state alone. The client
must fail visibly after a server crash and may reconnect on the next explicit
operation, but it must not run an unbounded automatic retry loop.

V0.4 intentionally does not add the proposed cross-file 64 MiB LRU or latency
histograms. Physical major-3D testing must first show whether network reads are
the limiting factor; expanding cache memory before that evidence would compete
with LLVM, SPU, and RSX allocations on constrained iPhones.

## Launch surfaces

The EmuHub library is the primary multi-game browser and direct-launch surface.
The iOS menu also exposes **Open PS3 XMB** through the existing
`rpcs3_ios_boot_vsh()` core export. XMB boot and direct title boot are separate:
opening XMB does not imply that stock XMB automatically lists every EmuHub
mount. A later selected-disc mount can expose one chosen network title to XMB
without duplicating the entire EmuHub catalog.

## Verification gates

- Protocol unit tests cover every packed command and malformed response.
- Loopback integration covers list/stat/open/random-read/reconnect/cancel.
- Live NAS proof covers both `PS3ISO` and extracted `GAMES` content.
- A physical iPhone launches a title larger than available local storage.
- First and second boot prove local PPU/shader cache reuse while disc reads stay
  remote.
- Network interruption fails visibly, reconnects only when safe, and never
  falls back to a hosted/WebKit/WASM path.
- A failed title followed by Stop must release a blocked mount promptly; a
  second title and a fresh `/PS3ISO` plus `/GAMES` scan must succeed without an
  app, container, or server-process restart.
- Managed-server qualification must kill only the supervised `ps3netsrv`
  process, prove that protocol health changes while the container remains up,
  and prove bounded client recovery after the supervisor restarts it.
- Admin mount changes survive Compose regeneration, container restart, and Git
  sync without altering unrelated mounts.
