"""Bridge ARMSX3's iOS 26 Universal JIT protocol through LLDB/debugserver.

Import this script after attaching LLDB to an app launched with --start-stopped,
then run ``armsx3-jit-install`` before continuing the process.
"""

from __future__ import annotations

import lldb


JIT_PROTOCOL_SYMBOL = "rpcs3_ios_jit26_protocol_call"
JIT_PAGE_SIZE = 16 * 1024
COMMAND_DETACH = 0
COMMAND_PREPARE_REGION = 1
PROGRESS_PAGE_INTERVAL = 1024


def _register(frame: lldb.SBFrame, name: str) -> lldb.SBValue:
    value = frame.FindRegister(name)
    if not value.IsValid():
        raise RuntimeError(f"register {name} is unavailable")
    return value


def _read_register(frame: lldb.SBFrame, name: str) -> int:
    return _register(frame, name).GetValueAsUnsigned()


def _write_register(frame: lldb.SBFrame, name: str, value: int) -> None:
    error = lldb.SBError()
    if not _register(frame, name).SetValueFromCString(f"0x{value:x}", error):
        raise RuntimeError(f"could not write {name}: {error.GetCString()}")


def _send_packet(debugger: lldb.SBDebugger, packet: str) -> None:
    result = lldb.SBCommandReturnObject()
    debugger.GetCommandInterpreter().HandleCommand(
        f"process plugin packet send {packet}", result
    )
    output = (result.GetOutput() or "") + (result.GetError() or "")
    if not result.Succeeded() or "response: OK" not in output:
        detail = output.strip() or "no debugserver response"
        raise RuntimeError(f"debugserver rejected {packet}: {detail}")


def _prepare_region(frame: lldb.SBFrame, address: int, length: int) -> None:
    if not address or not length:
        raise RuntimeError(
            f"invalid Universal JIT region address=0x{address:x} length={length}"
        )

    page_count = (length + JIT_PAGE_SIZE - 1) // JIT_PAGE_SIZE
    debugger = frame.GetThread().GetProcess().GetTarget().GetDebugger()
    print(
        f"[ARMSX3 JIT] Preparing {page_count} pages at 0x{address:x} "
        f"({length // (1024 * 1024)} MiB)"
    )

    for page_index in range(page_count):
        page_address = address + page_index * JIT_PAGE_SIZE
        _send_packet(debugger, f"M{page_address:x},1:69")
        completed = page_index + 1
        if completed % PROGRESS_PAGE_INTERVAL == 0 or completed == page_count:
            print(f"[ARMSX3 JIT] Prepared {completed}/{page_count} pages")


def handle_jit_call(
    frame: lldb.SBFrame,
    _breakpoint_location: lldb.SBBreakpointLocation,
    _internal_dict: dict,
) -> bool:
    """Handle one protocol call and auto-continue; return True only on failure."""

    try:
        command = _read_register(frame, "x0")
        address = _read_register(frame, "x1")
        length = _read_register(frame, "x2")

        if command == COMMAND_PREPARE_REGION:
            _prepare_region(frame, address, length)
            return_value = address
        elif command == COMMAND_DETACH:
            print("[ARMSX3 JIT] Arena sealed; retaining the wired LLDB session")
            return_value = 0
        else:
            raise RuntimeError(f"unsupported Universal JIT command {command}")

        return_address = _read_register(frame, "lr")
        _write_register(frame, "x0", return_value)
        _write_register(frame, "pc", return_address)
        return False
    except Exception as error:
        print(f"[ARMSX3 JIT] ERROR: {error}")
        return True


def install_command(
    debugger: lldb.SBDebugger,
    _command: str,
    result: lldb.SBCommandReturnObject,
    _internal_dict: dict,
) -> None:
    target = debugger.GetSelectedTarget()
    if not target.IsValid():
        result.SetError("No selected target; attach to the stopped app first")
        return

    breakpoint = target.BreakpointCreateByName(JIT_PROTOCOL_SYMBOL)
    if not breakpoint.IsValid():
        result.SetError(f"Could not create breakpoint for {JIT_PROTOCOL_SYMBOL}")
        return

    breakpoint.SetScriptCallbackFunction(f"{__name__}.handle_jit_call")
    breakpoint.SetAutoContinue(True)
    result.AppendMessage(
        f"Installed ARMSX3 Universal JIT bridge as breakpoint "
        f"{breakpoint.GetID()} ({breakpoint.GetNumLocations()} current locations)"
    )


def __lldb_init_module(debugger: lldb.SBDebugger, _internal_dict: dict) -> None:
    debugger.HandleCommand(
        f"command script add -f {__name__}.install_command armsx3-jit-install"
    )
    print("ARMSX3 iOS 26 JIT bridge loaded; run armsx3-jit-install before continue")
