#include "../app/ARMSX3ControllerLayout.h"
#include "../../../rpcs3/ios/RPCS3IOSInput.h"
#include <cassert>
#include <cstdio>

static CGRect normalized(CGRect rail, double x, double y, double w, double h)
{
    return CGRectMake(rail.origin.x + rail.size.width * x, rail.origin.y + rail.size.height * y,
        rail.size.width * w, rail.size.height * h);
}

int main()
{
    using namespace armsx3::controls;
    for (const CGFloat h : {320., 375., 390., 393., 414., 428., 440., 768., 834., 1024.})
    {
        const CGRect rail = CGRectMake(700, 0, h * 853.0 / 1844.0, h);
        const CGRect ps = landscape_ps_frame(rail);
        assert(CGRectContainsRect(rail, ps));
        assert(ps.size.width >= 44 && ps.size.height >= 44);
        assert(!CGRectIntersectsRect(ps, normalized(rail, .147, .848, .288, .076)));
        assert(!CGRectIntersectsRect(ps, normalized(rail, .224, .552, .548, .252)));
        // Entire old brand, including antialiasing margin, is inside the plate's
        // rectangular interior, not a rounded corner or a transparent highlight.
        assert(CGRectContainsRect(CGRectInset(ps, 4, 4), normalized(rail, .529, .88, .344, .046)));
    }
    for (const CGFloat w : {296., 351., 366., 369., 390., 404., 416., 744., 810., 1000.})
    {
        const CGRect stage = CGRectMake(0, 0, w, std::floor(w * 9 / 16) + portrait_footer_height);
        const CGRect video = portrait_video_frame(stage, true);
        assert(video.size.height == std::floor(w * 9 / 16));
        assert(CGRectEqualToRect(portrait_video_frame(stage, false), stage));
        for (unsigned i = 0; i < 3; ++i)
        {
            const CGRect button = portrait_footer_button(video, i);
            assert(CGRectContainsRect(stage, button));
            assert(button.size.width >= 44 && button.size.height >= 44);
            assert(!CGRectIntersectsRect(video, button));
            for (unsigned j = i + 1; j < 3; ++j)
                assert(!CGRectIntersectsRect(button, portrait_footer_button(video, j)));
        }
    }
    rpcs3::ios::pad_state_registry input;
    auto state = rpcs3::ios::disconnected_pad_state();
    state.connected = 1;
    for (const uint64_t bit : {RPCS3_IOS_PAD_BUTTON_PS, RPCS3_IOS_PAD_BUTTON_L3, RPCS3_IOS_PAD_BUTTON_R3})
    {
        state.buttons = bit;
        state.left_stick_x = -1;
        state.right_stick_y = 1;
        assert(input.update(&state) == RPCS3_IOS_OK);
        assert(input.snapshot().buttons == bit);
        assert(input.snapshot().left_stick_x == -1);
        state.buttons = 0;
        assert(input.update(&state) == RPCS3_IOS_OK);
        assert(input.snapshot().buttons == 0);
        input.clear();
        assert(!input.snapshot().connected);
    }
    std::puts("PASS: production PS/footer geometry, brand coverage, input press/release/clear");
}
