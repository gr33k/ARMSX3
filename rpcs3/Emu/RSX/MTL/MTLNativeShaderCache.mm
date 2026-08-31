#include "MTLNativeShaderCache.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <TargetConditionals.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <exception>
#include <limits>
#include <mutex>
#include <unordered_map>
#include <utility>

#if !TARGET_OS_IOS
#error "The ARMSX3 native RSX Metal cache supports iOS only"
#endif

#if !defined(__arm64__)
#error "The ARMSX3 native RSX Metal cache supports arm64 only"
#endif

namespace rsx::mtl
{
	struct shader_handle::state
	{
		stable_digest key;
		translated_shader translated;
		__strong id<MTLLibrary> library = nil;
		__strong id<MTLFunction> function = nil;
	};

	struct render_pipeline_handle::state
	{
		stable_digest key;
		shader_handle vertex;
		shader_handle fragment;
		__strong id<MTLRenderPipelineState> pipeline = nil;
	};

	namespace
	{
		std::string objc_string(NSString* value, const char* fallback)
		{
			if (!value)
			{
				return fallback;
			}
			const char* utf8 = value.UTF8String;
			return utf8 ? utf8 : fallback;
		}

		std::string metal_error(NSError* error, const char* fallback)
		{
			if (!error)
			{
				return fallback;
			}
			NSString* message = error.localizedDescription;
			if (error.localizedFailureReason.length != 0)
			{
				message = [message stringByAppendingFormat:@" (%@)", error.localizedFailureReason];
			}
			return objc_string(message, fallback);
		}

		MTLDataType function_constant_data_type(const function_constant_type type)
		{
			switch (type)
			{
			case function_constant_type::boolean:
				return MTLDataTypeBool;
			case function_constant_type::int8:
				return MTLDataTypeChar;
			case function_constant_type::uint8:
				return MTLDataTypeUChar;
			case function_constant_type::int16:
				return MTLDataTypeShort;
			case function_constant_type::uint16:
				return MTLDataTypeUShort;
			case function_constant_type::int32:
				return MTLDataTypeInt;
			case function_constant_type::uint32:
				return MTLDataTypeUInt;
			case function_constant_type::float16:
				return MTLDataTypeHalf;
			case function_constant_type::float32:
				return MTLDataTypeFloat;
			}
			return MTLDataTypeNone;
		}

		template <typename State>
		struct cache_entry
		{
			std::mutex mutex;
			std::condition_variable ready;
			std::shared_ptr<const State> value;
			std::string error;
			bool building = false;
			std::atomic<std::uint64_t> last_use = 0;
		};
	} // namespace

	struct native_shader_cache::impl
	{
		using shader_entry = cache_entry<shader_handle::state>;
		using pipeline_entry = cache_entry<render_pipeline_handle::state>;

		explicit impl(void* native_device, const native_cache_limits requested_limits)
			: limits(requested_limits)
		{
			@autoreleasepool
			{
				if (!native_device)
				{
					init_error = "Metal device is null";
					return;
				}
				id candidate = (__bridge id)native_device;
				if (![candidate conformsToProtocol:@protocol(MTLDevice)])
				{
					init_error = "Native object does not conform to MTLDevice";
					return;
				}
				if (limits.shaders == 0 || limits.render_pipelines == 0)
				{
					init_error = "Native Metal cache limits must be nonzero";
					return;
				}
				device = (id<MTLDevice>)candidate;
				registry_id = device.registryID;
			}
		}

		template <typename State, typename Entry, typename Map, typename Builder>
		std::shared_ptr<const State> get_or_build(
			Map& map,
			const stable_digest& key,
			Builder&& builder,
			std::string& error)
		{
			std::shared_ptr<Entry> entry;
			{
				std::lock_guard lock(map_mutex);
				auto [iterator, inserted] = map.try_emplace(key);
				if (inserted)
				{
					iterator->second = std::make_shared<Entry>();
				}
				entry = iterator->second;
				entry->last_use.store(++use_clock, std::memory_order_relaxed);
			}

			std::unique_lock entry_lock(entry->mutex);
			if (entry->value)
			{
				return entry->value;
			}
			if (entry->building)
			{
				entry->ready.wait(entry_lock, [&entry]
					{
						return !entry->building;
					});
				if (!entry->value)
				{
					error = entry->error;
				}
				return entry->value;
			}

			entry->building = true;
			entry->error.clear();
			entry_lock.unlock();

			std::shared_ptr<const State> built;
			try
			{
				built = builder(error);
			}
			catch (const std::exception& exception)
			{
				error = exception.what();
			}
			catch (...)
			{
				error = "Unknown native Metal cache build failure";
			}

			entry_lock.lock();
			entry->value = built;
			entry->error = error;
			entry->building = false;
			entry_lock.unlock();
			entry->ready.notify_all();
			return built;
		}

		template <typename Map>
		void trim_map(Map& map, const std::size_t limit)
		{
			while (map.size() > limit)
			{
				auto oldest = map.end();
				std::uint64_t oldest_use = std::numeric_limits<std::uint64_t>::max();
				for (auto iterator = map.begin(); iterator != map.end(); ++iterator)
				{
					const auto& entry = iterator->second;
					std::unique_lock entry_lock(entry->mutex, std::try_to_lock);
					if (!entry_lock || entry->building)
					{
						continue;
					}
					const std::uint64_t last_use = entry->last_use.load(std::memory_order_relaxed);
					if (last_use < oldest_use)
					{
						oldest = iterator;
						oldest_use = last_use;
					}
				}
				if (oldest == map.end())
				{
					break;
				}
				map.erase(oldest);
			}
		}

		std::shared_ptr<const shader_handle::state> build_shader(const shader_source& source, std::string& error)
		{
			translation_result translation = translate_spirv_to_msl(source);
			if (!translation)
			{
				error = std::move(translation.error);
				return {};
			}

			@autoreleasepool
			{
				@try
				{
					const translated_shader& translated = *translation.shader;
					NSString* msl = [[NSString alloc]
						initWithBytes:translated.msl_source.data()
							   length:translated.msl_source.size()
							 encoding:NSUTF8StringEncoding];
					NSString* entry_point = [[NSString alloc]
						initWithBytes:translated.msl_entry_point.data()
							   length:translated.msl_entry_point.size()
							 encoding:NSUTF8StringEncoding];
					if (!msl || !entry_point)
					{
						error = "SPIRV-Cross emitted non-UTF-8 MSL or entry-point text";
						return {};
					}

					MTLCompileOptions* compile_options = [[MTLCompileOptions alloc] init];
					compile_options.languageVersion = MTLLanguageVersion2_4;
					compile_options.fastMathEnabled = NO;
					compile_options.preserveInvariance = YES;

					NSError* library_error = nil;
					id<MTLLibrary> library = [device newLibraryWithSource:msl options:compile_options error:&library_error];
					if (!library)
					{
						error = metal_error(library_error, "Metal failed to compile translated MSL");
						return {};
					}
					library.label = [NSString stringWithFormat:@"ARMSX3 RSX shader %.12s", translated.cache_key.hex().c_str()];

					id<MTLFunction> function = nil;
					if (translated.metadata.function_constants.empty())
					{
						function = [library newFunctionWithName:entry_point];
					}
					else
					{
						MTLFunctionConstantValues* values = [[MTLFunctionConstantValues alloc] init];
						for (const function_constant& constant : translated.metadata.function_constants)
						{
							[values setConstantValue:constant.value.data()
												type:function_constant_data_type(constant.type)
											 atIndex:constant.index];
						}
						NSError* function_error = nil;
						function = [library newFunctionWithName:entry_point constantValues:values error:&function_error];
						if (!function)
						{
							error = metal_error(function_error, "Metal failed to specialize the translated shader");
							return {};
						}
					}
					if (!function)
					{
						error = "Translated MSL library did not expose the requested entry point";
						return {};
					}

					auto state = std::make_shared<shader_handle::state>();
					state->key = translated.cache_key;
					state->translated = std::move(*translation.shader);
					state->library = library;
					state->function = function;
					return state;
				}
				@catch (NSException* exception)
				{
					error = objc_string(exception.reason, "Objective-C exception during Metal shader compilation");
					return {};
				}
			}
		}

		std::shared_ptr<const render_pipeline_handle::state> build_pipeline(
			const render_pipeline_source& source,
			const stable_digest& key,
			const shader_handle& vertex,
			const shader_handle& fragment,
			std::string& error)
		{
			@autoreleasepool
			{
				@try
				{
					MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
					descriptor.label = source.label.empty() ? [NSString stringWithFormat:@"ARMSX3 RSX pipeline %.12s", key.hex().c_str()] : [NSString stringWithUTF8String:source.label.c_str()];
					descriptor.vertexFunction = (__bridge id<MTLFunction>)vertex.native_function();
					descriptor.fragmentFunction = (__bridge id<MTLFunction>)fragment.native_function();

					for (std::size_t index = 0; index < source.pipeline.color_attachments.size(); ++index)
					{
						const color_attachment_state& input = source.pipeline.color_attachments[index];
						MTLRenderPipelineColorAttachmentDescriptor* output = descriptor.colorAttachments[index];
						output.pixelFormat = static_cast<MTLPixelFormat>(input.pixel_format);
						output.blendingEnabled = input.blending_enabled;
						output.sourceRGBBlendFactor = static_cast<MTLBlendFactor>(input.source_rgb_blend_factor);
						output.destinationRGBBlendFactor = static_cast<MTLBlendFactor>(input.destination_rgb_blend_factor);
						output.rgbBlendOperation = static_cast<MTLBlendOperation>(input.rgb_blend_operation);
						output.sourceAlphaBlendFactor = static_cast<MTLBlendFactor>(input.source_alpha_blend_factor);
						output.destinationAlphaBlendFactor = static_cast<MTLBlendFactor>(input.destination_alpha_blend_factor);
						output.alphaBlendOperation = static_cast<MTLBlendOperation>(input.alpha_blend_operation);
						output.writeMask = static_cast<MTLColorWriteMask>(input.write_mask);
					}

					descriptor.depthAttachmentPixelFormat = static_cast<MTLPixelFormat>(source.pipeline.depth_attachment_pixel_format);
					descriptor.stencilAttachmentPixelFormat = static_cast<MTLPixelFormat>(source.pipeline.stencil_attachment_pixel_format);
					descriptor.sampleCount = source.pipeline.sample_count;
					descriptor.inputPrimitiveTopology = static_cast<MTLPrimitiveTopologyClass>(source.pipeline.input_primitive_topology);
					descriptor.alphaToCoverageEnabled = source.pipeline.alpha_to_coverage_enabled;
					descriptor.alphaToOneEnabled = source.pipeline.alpha_to_one_enabled;
					descriptor.rasterizationEnabled = source.pipeline.rasterization_enabled &&
					                                  !vertex.translation()->requirements.rasterization_disabled;
					descriptor.supportIndirectCommandBuffers = source.pipeline.support_indirect_command_buffers;
					descriptor.maxVertexAmplificationCount = source.pipeline.max_vertex_amplification_count;

					if (!source.pipeline.vertex_attributes.empty() || !source.pipeline.vertex_layouts.empty())
					{
						MTLVertexDescriptor* vertex_descriptor = [MTLVertexDescriptor vertexDescriptor];
						for (const vertex_attribute_state& input : source.pipeline.vertex_attributes)
						{
							MTLVertexAttributeDescriptor* output = vertex_descriptor.attributes[input.attribute_index];
							output.format = static_cast<MTLVertexFormat>(input.format);
							output.offset = input.offset;
							output.bufferIndex = input.buffer_index;
						}
						for (const vertex_buffer_layout_state& input : source.pipeline.vertex_layouts)
						{
							MTLVertexBufferLayoutDescriptor* output = vertex_descriptor.layouts[input.buffer_index];
							output.stride = input.stride;
							output.stepFunction = static_cast<MTLVertexStepFunction>(input.step_function);
							output.stepRate = input.step_rate;
						}
						descriptor.vertexDescriptor = vertex_descriptor;
					}

					NSError* pipeline_error = nil;
					id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&pipeline_error];
					if (!pipeline)
					{
						error = metal_error(pipeline_error, "Metal failed to build the RSX render pipeline");
						return {};
					}

					auto state = std::make_shared<render_pipeline_handle::state>();
					state->key = key;
					state->vertex = vertex;
					state->fragment = fragment;
					state->pipeline = pipeline;
					return state;
				}
				@catch (NSException* exception)
				{
					error = objc_string(exception.reason, "Objective-C exception during Metal pipeline compilation");
					return {};
				}
			}
		}

		__strong id<MTLDevice> device = nil;
		std::uint64_t registry_id = 0;
		native_cache_limits limits;
		std::string init_error;
		mutable std::mutex map_mutex;
		std::atomic<std::uint64_t> use_clock = 0;
		std::unordered_map<stable_digest, std::shared_ptr<shader_entry>, stable_digest_hash> shaders;
		std::unordered_map<stable_digest, std::shared_ptr<pipeline_entry>, stable_digest_hash> pipelines;
	};

	shader_handle::shader_handle(std::shared_ptr<const state> value)
		: m_state(std::move(value))
	{
	}

	shader_handle::operator bool() const noexcept
	{
		return static_cast<bool>(m_state);
	}

	stable_digest shader_handle::key() const noexcept
	{
		return m_state ? m_state->key : stable_digest{};
	}

	const translated_shader* shader_handle::translation() const noexcept
	{
		return m_state ? &m_state->translated : nullptr;
	}

	void* shader_handle::native_function() const noexcept
	{
		return m_state ? (__bridge void*)m_state->function : nullptr;
	}

	render_pipeline_handle::render_pipeline_handle(std::shared_ptr<const state> value)
		: m_state(std::move(value))
	{
	}

	render_pipeline_handle::operator bool() const noexcept
	{
		return static_cast<bool>(m_state);
	}

	stable_digest render_pipeline_handle::key() const noexcept
	{
		return m_state ? m_state->key : stable_digest{};
	}

	void* render_pipeline_handle::native_pipeline_state() const noexcept
	{
		return m_state ? (__bridge void*)m_state->pipeline : nullptr;
	}

	native_shader_cache::native_shader_cache(void* metal_device, const native_cache_limits limits)
		: m_impl(std::make_unique<impl>(metal_device, limits))
	{
	}

	native_shader_cache::~native_shader_cache() = default;
	native_shader_cache::native_shader_cache(native_shader_cache&&) noexcept = default;
	native_shader_cache& native_shader_cache::operator=(native_shader_cache&&) noexcept = default;

	bool native_shader_cache::valid() const noexcept
	{
		return m_impl && m_impl->device != nil && m_impl->init_error.empty();
	}

	std::string native_shader_cache::initialization_error() const
	{
		return m_impl ? m_impl->init_error : "Native Metal cache was moved from";
	}

	std::uint64_t native_shader_cache::device_registry_id() const noexcept
	{
		return m_impl ? m_impl->registry_id : 0;
	}

	shader_cache_result native_shader_cache::get_or_create_shader(const shader_source& source)
	{
		shader_cache_result result;
		if (!valid())
		{
			result.error = initialization_error();
			return result;
		}
		if (result.error = validate_shader_source(source); !result.error.empty())
		{
			return result;
		}

		const stable_digest key = make_shader_cache_key(source);
		auto state = m_impl->get_or_build<shader_handle::state, impl::shader_entry>(
			m_impl->shaders,
			key,
			[this, &source](std::string& error)
			{
				return m_impl->build_shader(source, error);
			},
			result.error);
		if (state)
		{
			result.value = shader_handle(std::move(state));
		}
		trim_to_limits();
		return result;
	}

	render_pipeline_cache_result native_shader_cache::get_or_create_render_pipeline(const render_pipeline_source& source)
	{
		render_pipeline_cache_result result;
		if (!valid())
		{
			result.error = initialization_error();
			return result;
		}
		if (result.error = validate_render_pipeline_source(source); !result.error.empty())
		{
			return result;
		}

		shader_cache_result vertex = get_or_create_shader(source.vertex);
		if (!vertex)
		{
			result.error = "Vertex shader: " + vertex.error;
			return result;
		}
		shader_cache_result fragment = get_or_create_shader(source.fragment);
		if (!fragment)
		{
			result.error = "Fragment shader: " + fragment.error;
			return result;
		}

		const stable_digest key = make_render_pipeline_cache_key(vertex.value.key(), fragment.value.key(), source.pipeline);
		auto state = m_impl->get_or_build<render_pipeline_handle::state, impl::pipeline_entry>(
			m_impl->pipelines,
			key,
			[this, &source, &key, &vertex, &fragment](std::string& error)
			{
				return m_impl->build_pipeline(source, key, vertex.value, fragment.value, error);
			},
			result.error);
		if (state)
		{
			result.value = render_pipeline_handle(std::move(state));
		}
		trim_to_limits();
		return result;
	}

	void native_shader_cache::clear()
	{
		if (!m_impl)
		{
			return;
		}
		std::lock_guard lock(m_impl->map_mutex);
		m_impl->pipelines.clear();
		m_impl->shaders.clear();
	}

	void native_shader_cache::trim_to_limits()
	{
		if (!m_impl)
		{
			return;
		}
		std::lock_guard lock(m_impl->map_mutex);
		m_impl->trim_map(m_impl->pipelines, m_impl->limits.render_pipelines);
		m_impl->trim_map(m_impl->shaders, m_impl->limits.shaders);
	}

	std::size_t native_shader_cache::shader_count() const
	{
		if (!m_impl)
		{
			return 0;
		}
		std::lock_guard lock(m_impl->map_mutex);
		return m_impl->shaders.size();
	}

	std::size_t native_shader_cache::render_pipeline_count() const
	{
		if (!m_impl)
		{
			return 0;
		}
		std::lock_guard lock(m_impl->map_mutex);
		return m_impl->pipelines.size();
	}
} // namespace rsx::mtl
