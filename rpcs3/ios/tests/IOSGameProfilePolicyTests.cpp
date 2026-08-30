#include "ios/IOSGameProfilePolicy.h"

int main()
{
	using namespace rpcs3::ios;

	static_assert(mobile_profile_for_title("BLUS30758").resolution_scale_percent == 50);
	static_assert(mobile_profile_for_title("BLES01807").multithreaded_rsx);
	static_assert(mobile_profile_for_title("BCES00065").kind == mobile_title_profile_kind::uncharted_1);
	static_assert(mobile_profile_for_title("BCUS98123").stub_ppu_traps == 1);
	static_assert(mobile_profile_for_title("BCES01175").shader_compiler_threads == 2);
	static_assert(!mobile_profile_for_title("BLUS31368"));
}
