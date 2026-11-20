#include "DuoLayout.h"

#include <stdio.h>
#include <string.h>

static int g_failed;

static double test_abs(double v) {
    return v < 0 ? -v : v;
}

static void expect_true(int cond, const char *msg) {
    if (!cond) {
        fprintf(stderr, "FAIL %s\n", msg);
        g_failed++;
    } else {
        printf("ok %s\n", msg);
    }
}

static void expect_d(const char *msg, double got, double want) {
    if (test_abs(got - want) > 0.01) {
        fprintf(stderr, "FAIL %s got %.4f want %.4f\n", msg, got, want);
        g_failed++;
    } else {
        printf("ok %s\n", msg);
    }
}

static DuoEnv env_make(double w, double h, double top, double left, double bottom, double right) {
    DuoEnv e;
    memset(&e, 0, sizeof e);
    e.bounds = duo_rect_make(0, 0, w, h);
    e.safeArea.top = top;
    e.safeArea.left = left;
    e.safeArea.bottom = bottom;
    e.safeArea.right = right;
    return e;
}

static void expect_bottom_bar(const char *label, DuoEnv env, double barH) {
    DuoRect current = duo_rect_make(0, env.bounds.h - barH, env.bounds.w, barH);
    DuoRect out;
    char buf[128];
    int moved = duo_place_bar(&env, current, &out);
    snprintf(buf, sizeof buf, "%s moves", label);
    expect_true(moved, buf);
    snprintf(buf, sizeof buf, "%s x", label);
    expect_d(buf, out.x, env.safeArea.left);
    snprintf(buf, sizeof buf, "%s width", label);
    expect_d(buf, out.w, env.bounds.w - env.safeArea.left - env.safeArea.right);
    snprintf(buf, sizeof buf, "%s y", label);
    expect_d(buf, out.y, env.bounds.h - env.safeArea.bottom - barH);
    snprintf(buf, sizeof buf, "%s height", label);
    expect_d(buf, out.h, barH);
}

static void test_bottom_bar_tracks_safe_area(void) {
    DuoEnv phone = env_make(390, 844, 54, 0, 34, 0);
    DuoEnv wide = env_make(700, 980, 59, 72, 21, 16);
    /* Published pixel counts are ordinary inputs. Placement must not special-case them. */
    DuoEnv innerPixels = env_make(1878, 2670, 40, 20, 30, 10);
    DuoEnv outerPixels = env_make(1398, 2034, 40, 20, 30, 10);
    DuoEnv odd = env_make(500.5, 800.25, 11, 13, 17, 19);
    expect_bottom_bar("phone", phone, 49);
    expect_bottom_bar("wide side inset", wide, 83);
    expect_bottom_bar("inner pixel size", innerPixels, 80);
    expect_bottom_bar("outer pixel size", outerPixels, 80);
    expect_bottom_bar("odd size", odd, 50);
}

static void test_keyboard_lifts_bottom_bar(void) {
    DuoEnv env = env_make(390, 844, 54, 0, 34, 0);
    DuoRect out;
    DuoRect again;
    env.hasKeyboard = 1;
    env.keyboard = duo_rect_make(0, 520, 390, 324);
    expect_true(duo_place_bar(&env, duo_rect_make(0, 761, 390, 49), &out), "keyboard moves bar");
    expect_d("bar sits on keyboard", out.y, 520 - 49);
    expect_d("bar keeps width", out.w, 390);
    expect_true(!duo_place_bar(&env, out, &again), "parked bar is stable");
}

static void test_huge_keyboard_stays_bottom(void) {
    DuoEnv env = env_make(390, 390, 47, 0, 21, 0);
    DuoRect out;
    DuoRect again;
    env.hasKeyboard = 1;
    env.keyboard = duo_rect_make(0, 120, 390, 270);
    expect_true(duo_place_bar(&env, duo_rect_make(0, 320, 390, 49), &out), "short window moves bar");
    expect_d("short window y", out.y, 71);
    expect_true(!duo_place_bar(&env, out, &again), "short window does not flip to top");
}

static void test_nav_stays_top(void) {
    DuoEnv env = env_make(844, 390, 0, 59, 21, 59);
    DuoRect out;
    env.hasKeyboard = 1;
    env.keyboard = duo_rect_make(0, 220, 844, 170);
    expect_true(duo_place_bar(&env, duo_rect_make(0, 0, 844, 54), &out), "nav moves");
    expect_d("nav y", out.y, 0);
    expect_d("nav x", out.x, 59);
    expect_d("nav width", out.w, 844 - 118);
}

static void test_vertical_bar_not_forced_bottom(void) {
    DuoEnv env = env_make(844, 390, 0, 80, 21, 0);
    DuoRect current = duo_rect_make(844 - 76, 0, 76, 390);
    DuoRect out;
    expect_true(duo_bar_axis(current) == DUO_AXIS_VERTICAL, "side chrome is vertical");
    expect_true(duo_place_bar(&env, current, &out), "vertical bar moves");
    expect_d("vertical x stays on the outer edge", out.x, 844 - 76);
    expect_d("vertical y uses top safe area", out.y, 0);
    expect_d("vertical height clears bottom inset", out.h, 390 - 21);
    expect_true(out.w < out.h, "vertical bar was not turned into a bottom bar");
}

static void test_vertical_bar_ignores_own_side_inset(void) {
    DuoEnv env = env_make(700, 980, 59, 0, 21, 88);
    DuoRect current = duo_rect_make(700 - 88, 0, 88, 980);
    DuoRect out;
    expect_true(duo_place_bar(&env, current, &out), "right bar adjusts height");
    expect_d("right bar is not pushed in by its own inset", out.x, 700 - 88);
    expect_d("right bar height", out.h, 980 - 59 - 21);
}

static void test_rotation_follows_bounds(void) {
    DuoEnv portrait = env_make(390, 844, 54, 0, 34, 0);
    DuoEnv landscape = env_make(844, 390, 0, 59, 21, 59);
    DuoRect portraitOut;
    DuoRect landscapeOut;
    duo_place_bar(&portrait, duo_rect_make(12, 700, 300, 49), &portraitOut);
    duo_place_bar(&landscape, duo_rect_make(12, 300, 300, 49), &landscapeOut);
    expect_d("portrait width", portraitOut.w, 390);
    expect_d("landscape width", landscapeOut.w, 844 - 118);
    expect_true(landscapeOut.w > portraitOut.w, "rotation widens the bar with the window");
    expect_d("landscape y", landscapeOut.y, 390 - 21 - 49);
}

static void test_root_view_is_not_a_bar(void) {
    DuoEnv env = env_make(390, 844, 54, 0, 34, 0);
    DuoRect out;
    expect_true(duo_bar_axis(duo_rect_make(0, 0, 390, 844)) == DUO_AXIS_UNKNOWN, "root view axis");
    expect_true(!duo_place_bar(&env, duo_rect_make(0, 0, 390, 844), &out), "root view is not placed");
    expect_true(duo_bar_axis(duo_rect_make(0, 0, 390, 129)) == DUO_AXIS_UNKNOWN, "tall banner is not chrome");
}

static void test_side_keyboard_narrows_bar(void) {
    DuoEnv env = env_make(1000, 700, 20, 20, 20, 20);
    DuoRect out;
    env.hasKeyboard = 1;
    env.keyboard = duo_rect_make(760, 0, 240, 700);
    expect_true(duo_place_bar(&env, duo_rect_make(0, 640, 1000, 49), &out), "side keyboard moves bar");
    expect_d("bar stops before side keyboard", out.x + out.w, 760);
    expect_d("bar x", out.x, 20);
}

static void test_panel_and_keyboard(void) {
    DuoEnv env = env_make(400, 800, 40, 40, 40, 40);
    DuoRect panel;
    env.hasKeyboard = 1;
    env.keyboard = duo_rect_make(0, 500, 400, 300);
    panel = duo_clamp_panel(&env, duo_rect_make(50, 450, 300, 400), 8);
    expect_d("panel y", panel.y, 92);
    expect_d("panel x", panel.x, 50);
    expect_d("panel w", panel.w, 300);
    expect_d("panel h", panel.h, 400);
    panel = duo_clamp_panel(&env, duo_rect_make(-30, 80, 100, 120), 8);
    expect_d("offscreen panel x", panel.x, 48);
}

static void test_hit_and_video(void) {
    DuoRect hit = duo_hit_rect(duo_rect_make(0, 0, 20, 32), 44, 16);
    DuoRect untouched = duo_hit_rect(duo_rect_make(0, 0, 50, 50), 44, 16);
    DuoRect capped = duo_hit_rect(duo_rect_make(0, 0, 10, 10), 44, 16);
    expect_d("hit width", hit.w, 44);
    expect_d("hit height", hit.h, 44);
    expect_d("hit x", hit.x, -12);
    expect_d("hit y", hit.y, -6);
    expect_true(duo_rect_near(untouched, duo_rect_make(0, 0, 50, 50), 0.01), "large control unchanged");
    expect_d("capped hit", capped.w, 42);
    expect_true(duo_video_use_fit(626, 890, 1080, 1920), "wider container fits portrait video");
    expect_true(!duo_video_use_fit(390, 844, 1080, 1920), "tall phone keeps fill");
    expect_true(!duo_video_use_fit(0, 844, 1080, 1920), "unknown container keeps current gravity");
    expect_true(!duo_video_use_fit(700, 980, 0, 0), "unknown video keeps current gravity");
}

static void test_keyboard_inset_math(void) {
    expect_d("adds the deficit", duo_additional_bottom(34, 300), 266);
    expect_d("already clear", duo_additional_bottom(300, 300), 0);
    expect_d("hidden keyboard", duo_additional_bottom(34, 0), 0);
    expect_d("system inset larger than keyboard", duo_additional_bottom(320, 300), 0);
}

static void test_degenerate(void) {
    DuoEnv env = env_make(0, 0, 0, 0, 0, 0);
    DuoRect out;
    expect_true(!duo_place_bar(&env, duo_rect_make(0, 0, 49, 49), &out), "empty bounds");
    env = env_make(100, 100, 80, 80, 80, 80);
    expect_true(!duo_place_bar(&env, duo_rect_make(0, 60, 100, 40), &out), "safe area consumes the container");
}

int main(void) {
    test_bottom_bar_tracks_safe_area();
    test_keyboard_lifts_bottom_bar();
    test_huge_keyboard_stays_bottom();
    test_nav_stays_top();
    test_vertical_bar_not_forced_bottom();
    test_vertical_bar_ignores_own_side_inset();
    test_rotation_follows_bounds();
    test_root_view_is_not_a_bar();
    test_side_keyboard_narrows_bar();
    test_panel_and_keyboard();
    test_hit_and_video();
    test_keyboard_inset_math();
    test_degenerate();
    if (g_failed) {
        fprintf(stderr, "%d assertion(s) failed\n", g_failed);
        return 1;
    }
    printf("all layout assertions passed\n");
    return 0;
}
