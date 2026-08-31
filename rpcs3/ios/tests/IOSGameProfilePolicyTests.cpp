#include "ios/IOSGameProfilePolicy.h"

int main()
{
	using namespace rpcs3::ios;

	static_assert(mobile_profile_for_title("BLUS30758").resolution_scale_percent == 50);
	static_assert(mobile_profile_for_title("BLES01807").multithreaded_rsx);
	static_assert(mobile_profile_for_title("BLES01807").write_color_buffers);
	static_assert(mobile_profile_for_title("BLUS31156").write_color_buffers);
	static_assert(!mobile_profile_for_title("BLUS30758").write_color_buffers);
	static_assert(mobile_profile_for_title("BCES00065").kind == mobile_title_profile_kind::uncharted_1);
	static_assert(mobile_profile_for_title("BCUS98123").stub_ppu_traps == 1);
	static_assert(mobile_profile_for_title("BCES01175").kind == mobile_title_profile_kind::uncharted_3);
	static_assert(mobile_profile_for_title("BCES01175").resolution_scale_percent == 100);
	static_assert(mobile_profile_for_title("BCES01175").shader_compiler_threads == 1);
	static_assert(!mobile_profile_for_title("BCES01175").multithreaded_rsx);
	static_assert(mobile_profile_for_title("BCES01175").write_color_buffers);
	static_assert(mobile_profile_for_title("BCES01175").read_color_buffers);
	static_assert(mobile_profile_for_title("BCES01175").accurate_rsx_reservation_access);
	static_assert(mobile_profile_for_title("BCES01175").disable_async_texture_streaming);
	static_assert(!mobile_profile_for_title("BCUS98233").multithreaded_rsx);
	static_assert(!mobile_profile_for_title("BCES00065").write_color_buffers);
	static_assert(is_uncharted_3_title("BCES01175"));
	static_assert(is_uncharted_3_title("BCUS98233"));
	static_assert(!is_uncharted_3_title("BCES00065"));
	static_assert(!mobile_profile_for_title("BLUS31368"));
}
