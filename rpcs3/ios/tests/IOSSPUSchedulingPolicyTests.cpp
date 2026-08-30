#include "ios/IOSSPUSchedulingPolicy.h"

int main()
{
	using rpcs3::ios::automatic_mobile_spu_scheduling_for_title;
	using rpcs3::ios::spu_compile_free_thread_floor;

	static_assert(automatic_mobile_spu_scheduling_for_title("BCES00065"));
	static_assert(automatic_mobile_spu_scheduling_for_title("BCUS98123"));
	static_assert(automatic_mobile_spu_scheduling_for_title("BLUS30758"));
	static_assert(automatic_mobile_spu_scheduling_for_title("BLES01807"));
	static_assert(automatic_mobile_spu_scheduling_for_title("BCES01175"));
	static_assert(!automatic_mobile_spu_scheduling_for_title("BLUS31368"));
	static_assert(!automatic_mobile_spu_scheduling_for_title(""));

	static_assert(spu_compile_free_thread_floor(6, false) == 0);
	static_assert(spu_compile_free_thread_floor(6, true) == 3);
	static_assert(spu_compile_free_thread_floor(10, true) == 5);
	static_assert(spu_compile_free_thread_floor(12, false) == 2);
	static_assert(spu_compile_free_thread_floor(12, true) == 2);
}
