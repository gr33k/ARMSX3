#pragma once

#include "MTLGSRender.h"

namespace mtl
{
	// This factory is deliberately not registered by the iOS frontend yet. The
	// backend must encode real RSX draws and synchronization before selection.
	std::unique_ptr<guest_backend> make_native_guest_backend();
} // namespace mtl
