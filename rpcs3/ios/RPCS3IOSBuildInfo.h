#pragma once

#include "RPCS3IOS.h"

#define RPCS3_IOS_STRINGIFY_IMPL(value) #value
#define RPCS3_IOS_STRINGIFY(value) RPCS3_IOS_STRINGIFY_IMPL(value)

namespace rpcs3::ios
{
inline constexpr char build_info_json[] =
	"{\"abi\":" RPCS3_IOS_STRINGIFY(RPCS3_IOS_ABI_VERSION)
	",\"frontend\":\"ios\""
	",\"upstream\":\"fdcfded8dfd3060af66bda0a3ac4635458980038\""
	",\"llvm\":\"ca7933e47d3a3451d81e72ac174dcb5aa28b59d1\""
	",\"jit\":\"sealed-arena\""
	",\"renderer\":\"vulkan-moltenvk\""
	",\"moltenvk\":\"1.4.2\""
	",\"ffmpeg\":\"8.1.1\""
	",\"audio\":\"remoteio\""
	",\"input\":\"gamecontroller-multiplayer-rumble\""
	",\"games\":\"pkg-rap-iso-zip-folder-netiso-updates-runtime-patches-library-delete-cache-management-trophies-big-picture\""
	",\"settings\":\"global-and-per-game-cfg-root-catalog-title-database-recommendations-presets\""
	",\"rpcn\":\"servers-account-social-online\""
	",\"performance\":\"fps-cpu-breakdown-rsx-frame-moltenvk-metal-shaders-memory-headroom-netiso\""
	",\"lifecycle\":\"pause-resume-stop-big-picture\""
	",\"media_codecs\":true}";
}

#undef RPCS3_IOS_STRINGIFY
#undef RPCS3_IOS_STRINGIFY_IMPL
