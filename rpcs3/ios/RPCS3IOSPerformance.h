#pragma once

#include "RPCS3IOS.h"

#include <cstdint>

namespace rpcs3::ios
{
// Resets the per-session frame baseline when RPCS3 creates a new graphics
// frame. This does not retain or own the renderer.
void reset_performance_metrics();

// Called from the RSX presentation thread after a frame has been queued for
// display. rsx_load is RPCS3's approximate renderer utilization, not a Metal
// device-wide hardware counter.
void record_presented_frame(std::uint32_t rsx_load) noexcept;

// Returns the current dirty-memory headroom before iOS applies the process
// limit. The query is intentionally cheap enough for frame-boundary sampling.
std::uint64_t available_process_memory_headroom() noexcept;

// Returns unused pages from all malloc zones to iOS after a bounded transient
// allocation workload, such as an LLVM compilation batch.
std::uint64_t relieve_process_memory_pressure() noexcept;

// UIKit can observe system-wide pressure before the process-headroom query
// crosses a local threshold. The wrapper publishes that warning atomically and
// the RSX frame boundary consumes it without taking the lifecycle lock.
void notify_process_memory_warning() noexcept;
bool consume_process_memory_warning() noexcept;

// Produces an observational snapshot without taking the serialized lifecycle
// lock. The caller supplies struct_size for ABI validation.
rpcs3_ios_status capture_performance_metrics(rpcs3_ios_performance_metrics* metrics);
}
