#pragma once

#include "MTLSpirvCompiler.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace rsx::mtl
{
	class shader_handle
	{
	public:
		shader_handle() = default;

		[[nodiscard]] explicit operator bool() const noexcept;
		[[nodiscard]] stable_digest key() const noexcept;
		[[nodiscard]] const translated_shader* translation() const noexcept;
		// Borrowed Objective-C object pointer. It remains valid while this handle lives.
		[[nodiscard]] void* native_function() const noexcept;

	private:
		struct state;
		explicit shader_handle(std::shared_ptr<const state> value);
		std::shared_ptr<const state> m_state;

		friend class native_shader_cache;
	};

	class render_pipeline_handle
	{
	public:
		render_pipeline_handle() = default;

		[[nodiscard]] explicit operator bool() const noexcept;
		[[nodiscard]] stable_digest key() const noexcept;
		// Borrowed Objective-C object pointer. It remains valid while this handle lives.
		[[nodiscard]] void* native_pipeline_state() const noexcept;

	private:
		struct state;
		explicit render_pipeline_handle(std::shared_ptr<const state> value);
		std::shared_ptr<const state> m_state;

		friend class native_shader_cache;
	};

	struct shader_cache_result
	{
		shader_handle value;
		std::string error;

		[[nodiscard]] explicit operator bool() const noexcept
		{
			return static_cast<bool>(value);
		}
	};

	struct render_pipeline_cache_result
	{
		render_pipeline_handle value;
		std::string error;

		[[nodiscard]] explicit operator bool() const noexcept
		{
			return static_cast<bool>(value);
		}
	};

	struct native_cache_limits
	{
		std::size_t shaders = 1024;
		std::size_t render_pipelines = 512;
	};

	// This cache is one-device-only. Pass an id<MTLDevice> as (__bridge void*).
	// The implementation retains the device and all cached native objects under ARC.
	class native_shader_cache
	{
	public:
		explicit native_shader_cache(void* metal_device, native_cache_limits limits = {});
		~native_shader_cache();

		native_shader_cache(const native_shader_cache&) = delete;
		native_shader_cache& operator=(const native_shader_cache&) = delete;
		native_shader_cache(native_shader_cache&&) noexcept;
		native_shader_cache& operator=(native_shader_cache&&) noexcept;

		[[nodiscard]] bool valid() const noexcept;
		[[nodiscard]] std::string initialization_error() const;
		[[nodiscard]] std::uint64_t device_registry_id() const noexcept;
		[[nodiscard]] shader_cache_result get_or_create_shader(const shader_source& source);
		[[nodiscard]] render_pipeline_cache_result get_or_create_render_pipeline(const render_pipeline_source& source);

		void clear();
		void trim_to_limits();
		[[nodiscard]] std::size_t shader_count() const;
		[[nodiscard]] std::size_t render_pipeline_count() const;

	private:
		struct impl;
		std::unique_ptr<impl> m_impl;
	};
} // namespace rsx::mtl
