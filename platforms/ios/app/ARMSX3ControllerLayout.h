#pragma once

#include <CoreGraphics/CoreGraphics.h>
#include <algorithm>

namespace armsx3::controls
{
inline constexpr CGFloat portrait_footer_height = 56.0;

inline CGRect portrait_video_frame(CGRect bounds, bool touch)
{
    bounds.size.height = std::max<CGFloat>(0, bounds.size.height - (touch ? portrait_footer_height : 0));
    return bounds;
}

// Preserve the source rail's native aspect and all existing input rectangles.
inline CGRect landscape_ps_frame(CGRect rail)
{
    const CGFloat width = std::max<CGFloat>(66, rail.size.width * 0.415);
    const CGFloat height = std::max<CGFloat>(44, rail.size.height * 0.112);
    return CGRectMake(rail.origin.x + rail.size.width * 0.915 - width,
        rail.origin.y + rail.size.height * 0.949 - height, width, height);
}

// SELECT, START, PS: a separate row below the video, never over the face buttons.
inline CGRect portrait_footer_button(CGRect video, unsigned index)
{
    const CGFloat width = index == 2 ? 88 : 72;
    const CGFloat x = index == 2 ? CGRectGetMaxX(video) - width - 8
        : video.origin.x + 8 + index * 80;
    return CGRectMake(x, CGRectGetMaxY(video) + 6, width, 44);
}
}
