#include "ios/IOSPipelineCachePolicy.h"

int main()
{
	using namespace rpcs3::ios;
	static_assert(graphics_shader_cache_version == "v1.95-ios-g3");
	static_assert(graphics_driver_cache_filename == "vk_pipeline_cache_ios_g3.bin");
	static_assert(is_graphics_driver_cache_filename("vk_pipeline_cache.bin"));
	static_assert(is_graphics_driver_cache_filename("vk_pipeline_cache_ios_g3.bin"));
	static_assert(!is_graphics_driver_cache_filename("vk_pipeline_cache_ios_g3.tmp"));
	static_assert(!is_graphics_driver_cache_filename("other_pipeline_cache.bin"));

	static_assert(!should_checkpoint_pipeline_cache(0, 60'000, 2048ull << 20, true));
	static_assert(!should_checkpoint_pipeline_cache(64, 14'999, 2048ull << 20, false));
	static_assert(!should_checkpoint_pipeline_cache(63, 15'000, 2048ull << 20, false));
	static_assert(should_checkpoint_pipeline_cache(64, 15'000, 2048ull << 20, false));
	static_assert(should_checkpoint_pipeline_cache(1, 1, 2048ull << 20, true));
	static_assert(!should_checkpoint_pipeline_cache(128, 60'000, 768ull << 20, true));
}
