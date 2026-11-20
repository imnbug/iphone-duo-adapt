#ifndef DUO_LAYOUT_H
#define DUO_LAYOUT_H

/* Geometry for the injection tweak.
 * Coordinates are in one view's space. No display size, scale, or device
 * identifier is part of this interface. */

typedef struct {
    double x, y, w, h;
} DuoRect;

typedef struct {
    double top, left, bottom, right;
} DuoInsets;

typedef struct {
    DuoRect bounds;
    DuoInsets safeArea;
    DuoRect keyboard; /* same space as bounds; ignored unless hasKeyboard */
    int hasKeyboard;
} DuoEnv;

typedef enum {
    DUO_AXIS_UNKNOWN = 0,
    DUO_AXIS_HORIZONTAL = 1,
    DUO_AXIS_VERTICAL = 2
} DuoAxis;

static inline DuoRect duo_rect_make(double x, double y, double w, double h) {
    DuoRect r;
    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;
    return r;
}

static inline int duo_rect_contains(DuoRect r, double x, double y) {
    return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
}

DuoAxis duo_bar_axis(DuoRect frame);
DuoRect duo_content_rect(const DuoEnv *env);
int duo_place_bar(const DuoEnv *env, DuoRect current, DuoRect *outFrame);
DuoRect duo_clamp_panel(const DuoEnv *env, DuoRect panel, double margin);
DuoRect duo_hit_rect(DuoRect bounds, double minSide, double maxExpand);
int duo_video_use_fit(double containerW, double containerH, double videoW, double videoH);
double duo_additional_bottom(double currentTotalBottom, double overlap);
int duo_rect_near(DuoRect a, DuoRect b, double eps);

#endif
