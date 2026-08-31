#include "stdafx.h"
#include "RPCS3IOSPerformance.h"

#include "Emu/Cell/PPUThread.h"
#include "Emu/Cell/SPUThread.h"
#include "Emu/IdManager.h"
#include "Emu/RSX/RSXThread.h"
#include "util/cpu_stats.hpp"
#include "util/sysinfo.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <mutex>

#ifdef __APPLE__
#include <mach/mach.h>
#endif

#ifdef RPCS3_IOS
#include <malloc/malloc.h>
#include <os/proc.h>
#endif

namespace
{
using sample_clock = std::chrono::steady_clock;
using sample_nanoseconds = std::chrono::nanoseconds;

struct emulator_cpu_cycles
{
	u64 ppu = 0;
	u64 spu = 0;
	u64 rsx = 0;
};

emulator_cpu_cycles sample_emulator_cpu_cycles()
{
	emulator_cpu_cycles result{};

	if (g_fxo->is_init<id_manager::id_map<named_thread<ppu_thread>>>())
	{
		idm::select<named_thread<ppu_thread>>([&result](u32, named_thread<ppu_thread>& ppu)
		{
			result.ppu += thread_ctrl::get_cycles(ppu);
		});
	}

	if (g_fxo->is_init<id_manager::id_map<named_thread<spu_thread>>>())
	{
		idm::select<named_thread<spu_thread>>([&result](u32, named_thread<spu_thread>& spu)
		{
			result.spu += thread_ctrl::get_cycles(spu);
		});
	}

	if (auto* rsx = g_fxo->try_get<rsx::thread>())
	{
		result.rsx = rsx->get_cycles();
	}

	return result;
}

u64 process_memory_footprint()
{
#ifdef __APPLE__
	task_vm_info_data_t info{};
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_VM_INFO,
		reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS)
	{
		return info.phys_footprint;
	}
	return 0;
#else
	return utils::get_memory_usage().second;
#endif
}

class performance_registry final
{
public:
	void reset()
	{
		{
			std::lock_guard lock(m_sample_mutex);
			m_presented_frames = 0;
			m_rsx_load = 0;
			m_has_rsx_load = false;
			m_has_fps_baseline = false;
			m_last_frame_count = 0;
			m_last_sample_time = {};
			static_cast<void>(m_cpu_stats.get_usage());
		}

		{
			std::lock_guard lock(m_renderer_mutex);
			m_renderer_sample = {};
		}

		m_ppu_cpu_usage = 0.0;
		m_spu_cpu_usage = 0.0;
		m_rsx_cpu_usage = 0.0;
		m_other_cpu_usage = 0.0;
		m_has_cpu_breakdown = false;
		static_cast<void>(m_cycle_cpu_stats.get_usage());
		const s64 now_ns = std::chrono::duration_cast<sample_nanoseconds>(
			sample_clock::now().time_since_epoch()).count();
		m_last_cpu_cycle_sample_ns = now_ns;
		m_next_cpu_cycle_sample_ns = now_ns + 1'000'000'000;
	}

	void record_presented_frame(u32 rsx_load) noexcept
	{
		m_rsx_load.store(std::min(rsx_load, 100u), std::memory_order_relaxed);
		m_has_rsx_load.store(true, std::memory_order_release);
		m_presented_frames.fetch_add(1, std::memory_order_relaxed);

		const s64 now_ns = std::chrono::duration_cast<sample_nanoseconds>(
			sample_clock::now().time_since_epoch()).count();
		s64 next_ns = m_next_cpu_cycle_sample_ns.load(std::memory_order_relaxed);
		if (now_ns < next_ns || !m_next_cpu_cycle_sample_ns.compare_exchange_strong(
			next_ns, now_ns + 1'000'000'000, std::memory_order_acq_rel))
		{
			return;
		}

		const s64 previous_ns = m_last_cpu_cycle_sample_ns.exchange(now_ns, std::memory_order_acq_rel);
		const s64 elapsed_ns = now_ns - previous_ns;
		const emulator_cpu_cycles cycles = sample_emulator_cpu_cycles();
		const double process_cpu = std::clamp(m_cycle_cpu_stats.get_usage(), 0.0, 100.0);
		const double normalization = static_cast<double>(elapsed_ns) *
			std::max<u32>(1, utils::get_thread_count());
		if (elapsed_ns <= 0 || normalization <= 0.0 || !(cycles.ppu || cycles.spu || cycles.rsx))
		{
			m_has_cpu_breakdown.store(false, std::memory_order_release);
			return;
		}

		const double ppu = std::clamp(100.0 * cycles.ppu / normalization, 0.0, 100.0);
		const double spu = std::clamp(100.0 * cycles.spu / normalization, 0.0, 100.0);
		const double rsx = std::clamp(100.0 * cycles.rsx / normalization, 0.0, 100.0);
		m_ppu_cpu_usage.store(ppu, std::memory_order_relaxed);
		m_spu_cpu_usage.store(spu, std::memory_order_relaxed);
		m_rsx_cpu_usage.store(rsx, std::memory_order_relaxed);
		m_other_cpu_usage.store(std::max(0.0, process_cpu - ppu - spu - rsx), std::memory_order_relaxed);
		m_has_cpu_breakdown.store(true, std::memory_order_release);
	}

	void record_renderer_performance(const rpcs3::ios::renderer_performance_sample& sample) noexcept
	{
		std::lock_guard lock(m_renderer_mutex);
		m_renderer_sample = sample;
	}

	rpcs3_ios_status snapshot(rpcs3_ios_performance_metrics* metrics)
	{
		if (!metrics || metrics->struct_size < sizeof(rpcs3_ios_performance_metrics))
		{
			return RPCS3_IOS_INVALID_ARGUMENT;
		}

		const u64 memory_used = process_memory_footprint();
		const u64 memory_total = utils::get_total_memory();
		const u64 memory_available = rpcs3::ios::available_process_memory_headroom();
		rpcs3::ios::renderer_performance_sample renderer_sample{};
		{
			std::lock_guard lock(m_renderer_mutex);
			renderer_sample = m_renderer_sample;
		}

		std::lock_guard lock(m_sample_mutex);
		const auto now = sample_clock::now();
		const u64 frame_count = m_presented_frames.load(std::memory_order_relaxed);
		const bool presented_since_last_sample = !m_has_fps_baseline || frame_count > m_last_frame_count;
		rpcs3_ios_performance_metrics result{};
		result.struct_size = sizeof(result);
		result.cpu_usage_percent = std::clamp(m_cpu_stats.get_usage(), 0.0, 100.0);
		result.valid_fields |= RPCS3_IOS_PERFORMANCE_CPU_VALID;

		if (m_has_fps_baseline)
		{
			const double elapsed = std::chrono::duration<double>(now - m_last_sample_time).count();
			if (elapsed > 0.0 && elapsed <= 2.0 && frame_count >= m_last_frame_count)
			{
				result.frames_per_second = static_cast<double>(frame_count - m_last_frame_count) / elapsed;
				result.valid_fields |= RPCS3_IOS_PERFORMANCE_FPS_VALID;
			}
		}

		m_has_fps_baseline = true;
		m_last_frame_count = frame_count;
		m_last_sample_time = now;

		if (m_has_rsx_load.load(std::memory_order_acquire))
		{
			result.gpu_usage_percent = presented_since_last_sample
				? m_rsx_load.load(std::memory_order_relaxed)
				: 0.0;
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_GPU_VALID;
		}

		if (memory_used && memory_total)
		{
			result.memory_used_bytes = memory_used;
			result.memory_total_bytes = memory_total;
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_MEMORY_VALID;
		}

		if (memory_available != umax)
		{
			result.memory_available_bytes = memory_available;
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_MEMORY_HEADROOM_VALID;
		}

		if (m_has_cpu_breakdown.load(std::memory_order_acquire))
		{
			result.ppu_cpu_usage_percent = m_ppu_cpu_usage.load(std::memory_order_relaxed);
			result.spu_cpu_usage_percent = m_spu_cpu_usage.load(std::memory_order_relaxed);
			result.rsx_cpu_usage_percent = m_rsx_cpu_usage.load(std::memory_order_relaxed);
			result.other_cpu_usage_percent = m_other_cpu_usage.load(std::memory_order_relaxed);
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_CPU_BREAKDOWN_VALID;
		}

		if (renderer_sample.moltenvk_valid)
		{
			result.moltenvk_sample_seconds = renderer_sample.interval_seconds;
			result.moltenvk_command_encoding_ms = renderer_sample.command_encoding_ms;
			result.moltenvk_queue_wait_ms = renderer_sample.queue_wait_ms;
			result.moltenvk_queue_submit_ms = renderer_sample.queue_submit_ms;
			result.metal_gpu_execution_ms = renderer_sample.metal_execution_ms;
			result.moltenvk_frame_interval_ms = renderer_sample.frame_interval_ms;
			result.moltenvk_gpu_memory_bytes = renderer_sample.gpu_memory_bytes;
			result.moltenvk_command_buffer_count = renderer_sample.command_buffer_count;
			result.metal_command_buffer_count = renderer_sample.metal_command_buffer_count;
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_MOLTENVK_VALID;
		}

		if (renderer_sample.shader_valid)
		{
			result.spirv_to_msl_ms = renderer_sample.spirv_to_msl_ms;
			result.msl_compile_ms = renderer_sample.msl_compile_ms;
			result.metal_pipeline_compile_ms = renderer_sample.pipeline_compile_ms;
			result.spirv_to_msl_count = renderer_sample.spirv_to_msl_count;
			result.msl_compile_count = renderer_sample.msl_compile_count;
			result.metal_pipeline_compile_count = renderer_sample.pipeline_compile_count;
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_SHADER_VALID;
		}

		if (renderer_sample.rsx_frame_valid)
		{
			result.rsx_draw_calls = renderer_sample.rsx_draw_calls;
			result.rsx_submit_count = renderer_sample.rsx_submit_count;
			result.rsx_setup_time_us = renderer_sample.rsx_setup_time_us;
			result.rsx_vertex_upload_time_us = renderer_sample.rsx_vertex_upload_time_us;
			result.rsx_texture_upload_time_us = renderer_sample.rsx_texture_upload_time_us;
			result.rsx_draw_exec_time_us = renderer_sample.rsx_draw_exec_time_us;
			result.rsx_flip_time_us = renderer_sample.rsx_flip_time_us;
			result.valid_fields |= RPCS3_IOS_PERFORMANCE_RSX_FRAME_VALID;
		}

		*metrics = result;
		return RPCS3_IOS_OK;
	}

private:
	std::atomic<u64> m_presented_frames{0};
	std::atomic<u32> m_rsx_load{0};
	std::atomic_bool m_has_rsx_load{false};
	std::atomic<double> m_ppu_cpu_usage{0.0};
	std::atomic<double> m_spu_cpu_usage{0.0};
	std::atomic<double> m_rsx_cpu_usage{0.0};
	std::atomic<double> m_other_cpu_usage{0.0};
	std::atomic_bool m_has_cpu_breakdown{false};
	std::atomic<s64> m_last_cpu_cycle_sample_ns{0};
	std::atomic<s64> m_next_cpu_cycle_sample_ns{0};
	std::mutex m_sample_mutex;
	std::mutex m_renderer_mutex;
	utils::cpu_stats m_cpu_stats;
	utils::cpu_stats m_cycle_cpu_stats;
	rpcs3::ios::renderer_performance_sample m_renderer_sample{};
	bool m_has_fps_baseline = false;
	u64 m_last_frame_count = 0;
	sample_clock::time_point m_last_sample_time{};
};

performance_registry g_performance_registry;
std::atomic_bool g_process_memory_warning_pending{false};
}

namespace rpcs3::ios
{
void reset_performance_metrics()
{
	g_performance_registry.reset();
	g_process_memory_warning_pending.store(false, std::memory_order_release);
}

void record_presented_frame(u32 rsx_load) noexcept
{
	g_performance_registry.record_presented_frame(rsx_load);
}

void record_renderer_performance(const renderer_performance_sample& sample) noexcept
{
	g_performance_registry.record_renderer_performance(sample);
}

u64 available_process_memory_headroom() noexcept
{
#ifdef RPCS3_IOS
	return os_proc_available_memory();
#else
	return umax;
#endif
}

u64 relieve_process_memory_pressure() noexcept
{
#ifdef RPCS3_IOS
	return malloc_zone_pressure_relief(nullptr, 0);
#else
	return 0;
#endif
}

void notify_process_memory_warning() noexcept
{
	g_process_memory_warning_pending.store(true, std::memory_order_release);
}

bool consume_process_memory_warning() noexcept
{
	return g_process_memory_warning_pending.exchange(false, std::memory_order_acq_rel);
}

rpcs3_ios_status capture_performance_metrics(rpcs3_ios_performance_metrics* metrics)
{
	return g_performance_registry.snapshot(metrics);
}
}
