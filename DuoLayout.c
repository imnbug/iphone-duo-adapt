#include "DuoLayout.h"

/* Thickness limits describe chrome shape, not a device. A bar is a thin strip.
 * Anything thicker is left untouched so a root view or a feed cell is not
 * resized as if it were a tab bar. */
static const double DUO_HORIZONTAL_MAX_THICKNESS = 128.0;
static const double DUO_VERTICAL_MAX_THICKNESS = 180.0;

static double duo_abs(double v) {
    return v < 0 ? -v : v;
}

static double duo_max(double a, double b) {
    return a > b ? a : b;
}

static double duo_min(double a, double b) {
    return a < b ? a : b;
}

DuoAxis duo_bar_axis(DuoRect frame) {
    if (frame.w < 1.0 || frame.h < 1.0) return DUO_AXIS_UNKNOWN;
    if (frame.h < frame.w && frame.h <= DUO_HORIZONTAL_MAX_THICKNESS && frame.w >= frame.h * 2.0) {
        return DUO_AXIS_HORIZONTAL;
    }
    if (frame.w < frame.h && frame.w <= DUO_VERTICAL_MAX_THICKNESS && frame.h >= frame.w * 2.0) {
        return DUO_AXIS_VERTICAL;
    }
    return DUO_AXIS_UNKNOWN;
}

DuoRect duo_content_rect(const DuoEnv *env) {
    DuoRect area;
    double left = env->safeArea.left;
    double top = env->safeArea.top;
    double right = env->safeArea.right;
    double bottom = env->safeArea.bottom;
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right < 0) right = 0;
    if (bottom < 0) bottom = 0;

    area.x = env->bounds.x + left;
    area.y = env->bounds.y + top;
    area.w = env->bounds.w - left - right;
    area.h = env->bounds.h - top - bottom;
    if (area.w < 0) area.w = 0;
    if (area.h < 0) area.h = 0;
    if (!env->hasKeyboard || area.w <= 0 || area.h <= 0) return area;

    {
        DuoRect kb = env->keyboard;
        double overlapL = duo_max(area.x, kb.x);
        double overlapT = duo_max(area.y, kb.y);
        double overlapR = duo_min(area.x + area.w, kb.x + kb.w);
        double overlapB = duo_min(area.y + area.h, kb.y + kb.h);
        double overlapW = overlapR - overlapL;
        double overlapH = overlapB - overlapT;
        if (overlapW < 1.0 || overlapH < 1.0) return area;

        if (overlapW >= overlapH) {
            double kbMidY = kb.y + kb.h * 0.5;
            double distTop = duo_abs(kbMidY - env->bounds.y);
            double distBot = duo_abs(kbMidY - (env->bounds.y + env->bounds.h));
            if (distBot <= distTop) {
                double newBottom = duo_min(area.y + area.h, kb.y);
                area.h = duo_max(0, newBottom - area.y);
            } else {
                double oldBottom = area.y + area.h;
                double newTop = duo_max(area.y, kb.y + kb.h);
                area.y = newTop;
                area.h = duo_max(0, oldBottom - newTop);
            }
        } else {
            double kbMidX = kb.x + kb.w * 0.5;
            double distLeft = duo_abs(kbMidX - env->bounds.x);
            double distRight = duo_abs(kbMidX - (env->bounds.x + env->bounds.w));
            if (distRight <= distLeft) {
                double newRight = duo_min(area.x + area.w, kb.x);
                area.w = duo_max(0, newRight - area.x);
            } else {
                double oldRight = area.x + area.w;
                double newLeft = duo_max(area.x, kb.x + kb.w);
                area.x = newLeft;
                area.w = duo_max(0, oldRight - newLeft);
            }
        }
    }
    return area;
}

static int duo_horizontal_is_bottom(const DuoEnv *env, DuoRect bar, DuoRect area) {
    double maxY = bar.y + bar.h;
    double boundsBottom = env->bounds.y + env->bounds.h;
    if (maxY >= boundsBottom - env->safeArea.bottom - bar.h - 24.0) return 1;
    if (env->hasKeyboard) {
        if (duo_abs(maxY - env->keyboard.y) <= bar.h + 24.0) return 1;
        if (duo_abs(maxY - (area.y + area.h)) <= 24.0) return 1;
    }
    if (bar.y <= env->bounds.y + env->safeArea.top + 24.0) return 0;
    return (bar.y + bar.h * 0.5) > (env->bounds.y + env->bounds.h * 0.5);
}

int duo_place_bar(const DuoEnv *env, DuoRect current, DuoRect *outFrame) {
    DuoRect area;
    DuoRect next;
    DuoAxis axis;
    if (!env || !outFrame) return 0;
    if (env->bounds.w < 1.0 || env->bounds.h < 1.0) return 0;
    axis = duo_bar_axis(current);
    if (axis == DUO_AXIS_UNKNOWN) return 0;
    area = duo_content_rect(env);
    if (area.w < 1.0 || area.h < 1.0) return 0;
    next = current;

    if (axis == DUO_AXIS_HORIZONTAL) {
        next.x = area.x;
        next.w = area.w;
        if (next.h > area.h) next.h = area.h;
        if (next.h < 1.0 || next.w < 1.0) return 0;
        if (duo_horizontal_is_bottom(env, current, area)) {
            next.y = area.y + area.h - next.h;
        } else {
            next.y = area.y;
        }
    } else {
        /* Vertical chrome occupies the outer edge. Side safe-area insets often
         * already belong to that bar, so applying them again would push it inward. */
        next.y = area.y;
        next.h = area.h;
        if (next.w > env->bounds.w) next.w = env->bounds.w;
        if (next.w < 1.0 || next.h < 1.0) return 0;
        if ((current.x + current.w * 0.5) <= (env->bounds.x + env->bounds.w * 0.5)) {
            next.x = env->bounds.x;
        } else {
            next.x = env->bounds.x + env->bounds.w - next.w;
        }
    }

    if (duo_rect_near(next, current, 0.5)) return 0;
    *outFrame = next;
    return 1;
}

DuoRect duo_clamp_panel(const DuoEnv *env, DuoRect panel, double margin) {
    DuoRect area;
    if (!env) return panel;
    if (margin < 0) margin = 0;
    area = duo_content_rect(env);
    area.x += margin;
    area.y += margin;
    area.w -= margin * 2.0;
    area.h -= margin * 2.0;
    if (area.w < 1.0 || area.h < 1.0) return panel;
    if (panel.w < 1.0 || panel.h < 1.0) return panel;
    if (panel.w > area.w) panel.w = area.w;
    if (panel.h > area.h) panel.h = area.h;
    if (panel.x < area.x) panel.x = area.x;
    if (panel.y < area.y) panel.y = area.y;
    if (panel.x + panel.w > area.x + area.w) panel.x = area.x + area.w - panel.w;
    if (panel.y + panel.h > area.y + area.h) panel.y = area.y + area.h - panel.h;
    return panel;
}

DuoRect duo_hit_rect(DuoRect bounds, double minSide, double maxExpand) {
    double extraW = 0;
    double extraH = 0;
    if (minSide < 0) minSide = 0;
    if (maxExpand < 0) maxExpand = 0;
    if (bounds.w < minSide) {
        extraW = minSide - bounds.w;
        if (extraW > maxExpand * 2.0) extraW = maxExpand * 2.0;
    }
    if (bounds.h < minSide) {
        extraH = minSide - bounds.h;
        if (extraH > maxExpand * 2.0) extraH = maxExpand * 2.0;
    }
    bounds.x -= extraW * 0.5;
    bounds.y -= extraH * 0.5;
    bounds.w += extraW;
    bounds.h += extraH;
    return bounds;
}

int duo_video_use_fit(double containerW, double containerH, double videoW, double videoH) {
    double containerAspect;
    double videoAspect;
    if (!(containerW > 1.0 && containerH > 1.0 && videoW > 1.0 && videoH > 1.0)) return 0;
    containerAspect = containerW / containerH;
    videoAspect = videoW / videoH;
    return containerAspect > videoAspect + 0.02;
}

double duo_additional_bottom(double currentTotalBottom, double overlap) {
    if (overlap <= 0) return 0;
    if (currentTotalBottom + 0.5 >= overlap) return 0;
    return overlap - currentTotalBottom;
}

int duo_rect_near(DuoRect a, DuoRect b, double eps) {
    return duo_abs(a.x - b.x) <= eps
        && duo_abs(a.y - b.y) <= eps
        && duo_abs(a.w - b.w) <= eps
        && duo_abs(a.h - b.h) <= eps;
}
