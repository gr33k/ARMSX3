#pragma once

#include "RPCS3IOS.h"

#include <cstdint>

namespace rpcs3::ios
{
// One low-frequency renderer sample. MoltenVK values are interval aggregates;
// RSX values describe the frame at the end of that interval.
struct renderer_performance_sample
{
	double interval_seconds = 0.0;
	double command_encoding_ms = 0.0;
	double queue_wait_ms = 0.0;
	double queue_submit_ms = 0.0;
	double metal_execution_ms = 0.0;
	double frame_interval_ms = 0.0;
	std::uint64_t gpu_memory_bytes = 0;
	double spirv_to_msl_ms = 0.0;
	double msl_compile_ms = 0.0;
	double pipeline_compile_ms = 0.0;
	std::uint32_t command_buffer_count = 0;
	std::uint32_t metal_command_buffer_count = 0;
	std::uint32_t spirv_to_msl_count = 0;
	std::uint32_t msl_compile_count = 0;
	std::uint32_t pipeline_compile_count = 0;
	std::uint32_t rsx_draw_calls = 0;
	std::uint32_t rsx_submit_count = 0;
	std::uint32_t rsx_setup_time_us = 0;
	std::uint32_t rsx_vertex_upload_time_us = 0;
	std::uint32_t rsx_texture_upload_time_us = 0;
	std::uint32_t rsx_draw_exec_time_us = 0;
	std::uint32_t rsx_flip_time_us = 0;
	bool moltenvk_valid = false;
	bool shader_valid = false;
	bool rsx_frame_valid = false;
};

// Resets the per-session frame baseline when RPCS3 creates a new graphics
// frame. This does not retain or own the renderer.
void reset_performance_metrics();

// Called from the RSX presentation thread after a frame has been queued for
// display. rsx_load is RPCS3's approximate renderer utilization, not a Metal
// device-wide hardware counter.
void record_presented_frame(std::uint32_t rsx_load) noexcept;

// Publishes a throttled renderer sample without taking the lifecycle lock.
void record_renderer_performance(const renderer_performance_sample& sample) noexcept;

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
