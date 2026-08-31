#pragma once

#include "RPCS3IOS.h"
#include "RPCS3IOSDisplay.h"

#include <string>

namespace rpcs3::ios
{
rpcs3_ios_status run_metal_presentation_probe(
	const display_surface_snapshot& surface,
	rpcs3_ios_metal_probe_result& result,
	std::string& error) noexcept;
}
