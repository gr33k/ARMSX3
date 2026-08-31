#include "RPCS3IOSMetalProbe.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <cstdio>

namespace rpcs3::ios
{
namespace
{
constexpr uint64_t probe_timeout_ns = 5'000'000'000;

void set_error(std::string& output, NSString* message)
{
	const char* utf8 = message.UTF8String;
	output = utf8 ? utf8 : "Unknown native Metal error";
}
}

rpcs3_ios_status run_metal_presentation_probe(
	const display_surface_snapshot& surface,
	rpcs3_ios_metal_probe_result& result,
	std::string& error) noexcept
{
	@autoreleasepool
	{
		@try
		{
			if (!surface.valid())
			{
				error = "Attach a valid CAMetalLayer before running the native Metal probe";
				return RPCS3_IOS_INVALID_STATE;
			}

			CAMetalLayer* layer = (__bridge CAMetalLayer*)surface.metal_layer;
			if (![layer isKindOfClass:CAMetalLayer.class])
			{
				error = "The attached display surface is not a CAMetalLayer";
				return RPCS3_IOS_INVALID_ARGUMENT;
			}

			id<MTLDevice> device = layer.device;
			if (!device)
			{
				error = "The attached CAMetalLayer has no Metal device";
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			id<MTLCommandQueue> queue = [device newCommandQueue];
			if (!queue)
			{
				error = "Metal could not create a command queue";
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}
			queue.label = @"ARMSX3 native Metal probe";

			static NSString* const shader_source =
				@"#include <metal_stdlib>\n"
				 "using namespace metal;\n"
				 "struct ProbeVertex { float4 position [[position]]; float3 color; };\n"
				 "vertex ProbeVertex armsx3_probe_vertex(uint id [[vertex_id]]) {\n"
				 "  const float2 positions[3] = { float2(-0.78, -0.70), float2(0.0, 0.78), float2(0.78, -0.70) };\n"
				 "  const float3 colors[3] = { float3(0.05, 0.78, 0.95), float3(0.98, 0.72, 0.16), float3(0.20, 0.92, 0.52) };\n"
				 "  ProbeVertex out; out.position = float4(positions[id], 0.0, 1.0); out.color = colors[id]; return out;\n"
				 "}\n"
				 "fragment float4 armsx3_probe_fragment(ProbeVertex in [[stage_in]]) { return float4(in.color, 1.0); }\n";

			NSError* compile_error = nil;
			id<MTLLibrary> library = [device newLibraryWithSource:shader_source options:nil error:&compile_error];
			if (!library)
			{
				set_error(error, compile_error.localizedDescription ?: @"Metal could not compile the probe MSL");
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			id<MTLFunction> vertex = [library newFunctionWithName:@"armsx3_probe_vertex"];
			id<MTLFunction> fragment = [library newFunctionWithName:@"armsx3_probe_fragment"];
			if (!vertex || !fragment)
			{
				error = "Metal did not publish both probe shader functions";
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			id<CAMetalDrawable> drawable = [layer nextDrawable];
			if (!drawable)
			{
				error = "CAMetalLayer did not provide a drawable";
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
			descriptor.label = @"ARMSX3 native Metal probe pipeline";
			descriptor.vertexFunction = vertex;
			descriptor.fragmentFunction = fragment;
			descriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;

			NSError* pipeline_error = nil;
			id<MTLRenderPipelineState> pipeline =
				[device newRenderPipelineStateWithDescriptor:descriptor error:&pipeline_error];
			if (!pipeline)
			{
				set_error(error, pipeline_error.localizedDescription ?: @"Metal could not create the probe pipeline");
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
			pass.colorAttachments[0].texture = drawable.texture;
			pass.colorAttachments[0].loadAction = MTLLoadActionClear;
			pass.colorAttachments[0].storeAction = MTLStoreActionStore;
			pass.colorAttachments[0].clearColor = MTLClearColorMake(0.018, 0.027, 0.055, 1.0);

			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
			if (!command_buffer || !encoder)
			{
				error = "Metal could not create the probe command buffer or encoder";
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			command_buffer.label = @"ARMSX3 native Metal probe commands";
			[encoder setRenderPipelineState:pipeline];
			[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
			[encoder endEncoding];
			[command_buffer presentDrawable:drawable];

			dispatch_semaphore_t completion = dispatch_semaphore_create(0);
			[command_buffer addCompletedHandler:^(__unused id<MTLCommandBuffer> completed) {
				dispatch_semaphore_signal(completion);
			}];
			[command_buffer commit];

			if (dispatch_semaphore_wait(
					completion,
					dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(probe_timeout_ns))) != 0)
			{
				error = "Native Metal probe timed out after 5 seconds";
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			if (command_buffer.status != MTLCommandBufferStatusCompleted)
			{
				set_error(error, command_buffer.error.localizedDescription ?: @"Native Metal command buffer failed");
				return RPCS3_IOS_METAL_PROBE_FAILED;
			}

			result.width = static_cast<uint32_t>(std::min<NSUInteger>(
				drawable.texture.width, UINT32_MAX));
			result.height = static_cast<uint32_t>(std::min<NSUInteger>(
				drawable.texture.height, UINT32_MAX));
			result.pixel_format = static_cast<uint32_t>(drawable.texture.pixelFormat);
			result.registry_id = device.registryID;
			result.max_buffer_length = device.maxBufferLength;
			result.unified_memory = device.hasUnifiedMemory ? 1u : 0u;

			const CFTimeInterval gpu_start = command_buffer.GPUStartTime;
			const CFTimeInterval gpu_end = command_buffer.GPUEndTime;
			if (gpu_end >= gpu_start)
			{
				result.gpu_duration_ns = static_cast<uint64_t>((gpu_end - gpu_start) * 1'000'000'000.0);
			}

			const char* device_name = device.name.UTF8String;
			std::snprintf(
				result.device_name,
				sizeof(result.device_name),
				"%s",
				device_name ? device_name : "Unknown Metal device");
			return RPCS3_IOS_OK;
		}
		@catch (NSException* exception)
		{
			set_error(error, exception.reason ?: @"Objective-C exception during native Metal probe");
			return RPCS3_IOS_METAL_PROBE_FAILED;
		}
	}
}
}
