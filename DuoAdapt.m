// DuoAdapt
// 注入宿主进程的 UIKit 适配 dylib，不是独立 App，也没有 Bundle ID。
// 布局只读取当前窗口边界、安全区和键盘矩形。
// 不读设备方向，不伪造 idiom / size class，不按机型标识或分辨率分支。
// 最低系统保持 15.0。文件里出现的 27.1 符号只用于确认编译 SDK，不抬高部署目标。
//
// 缺口：Apple 文档把折叠描述成 reserved region（Swift 名为 reservedRegions），
// 并把竖向栏描述成 trait 的 verticalBarEdge。这两处没有给出可编译的
// Objective-C selector，本文件不猜测 selector。系统若把竖向栏或折叠写进
// 窗口安全区，这里会跟着安全区走；安全区没有表达的铰链中缝不会被单独避开。
// 铰链角度 API 是交互输入，文档要求布局不要靠角度，因此这里不调用它。

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <stdint.h>

#import "DuoLayout.h"

#if !defined(__IPHONE_27_1) || __IPHONE_OS_VERSION_MAX_ALLOWED < __IPHONE_27_1
#error "Refusing to compile without the iOS 27.1 SDK. Do not substitute an older SDK."
#endif

static void duo_require_ios_27_1_symbols(void) {
    UIVerticalBarBehavior behavior = UIVerticalBarBehaviorAutomatic;
    behavior = UIVerticalBarBehaviorDisabled;
    UITabBarControllerMode mode = UITabBarControllerModeTabBar;
    if (behavior == UIVerticalBarBehaviorAutomatic && mode == UITabBarControllerModeTabBar) {
        /* 这两个符号必须来自 27.1 头文件。这里不把竖向栏全局关掉。 */
    }
}

static CGRect g_keyboard_screen;
static int g_keyboard_visible;
static _Thread_local int duo_bar_depth;
static _Thread_local int duo_vc_depth;
static _Thread_local int duo_media_depth;

static const void *kDuoOrigInset = &kDuoOrigInset;
static const void *kDuoOrigIndicator = &kDuoOrigIndicator;
static const void *kDuoApplied = &kDuoApplied;
static const void *kDuoOrigFrame = &kDuoOrigFrame;
static const void *kDuoOrigAdditional = &kDuoOrigAdditional;
static const void *kDuoImageFit = &kDuoImageFit;
static const void *kDuoPlayerFit = &kDuoPlayerFit;

static __weak UIScrollView *g_keyboardScroll;
static __weak UIView *g_keyboardPanel;

typedef struct {
    Class cls;
    void (*origLayout)(UIView *, SEL);
    void (*origSetFrame)(UIView *, SEL, CGRect);
} DuoHookSlot;

enum { DUO_SLOT_COUNT = 8 };
static DuoHookSlot g_slots[DUO_SLOT_COUNT];

static DuoHookSlot *duo_slot_for_class(Class cls) {
    for (Class cursor = cls; cursor; cursor = class_getSuperclass(cursor)) {
        for (int i = 0; i < DUO_SLOT_COUNT; i++) {
            if (g_slots[i].cls == cursor) return &g_slots[i];
        }
    }
    return NULL;
}

static CGRect duo_keyboard_in_host(UIView *host) {
    UIWindow *window;
    UIScreen *screen;
    CGRect inWindow;
    if (!g_keyboard_visible || !host || ![NSThread isMainThread]) return CGRectNull;
    window = host.window;
    if (!window) return CGRectNull;
    screen = window.windowScene.screen;
    if (screen) {
        inWindow = [window convertRect:g_keyboard_screen fromCoordinateSpace:screen.coordinateSpace];
    } else {
        inWindow = [window convertRect:g_keyboard_screen fromView:nil];
    }
    if (host == window) return inWindow;
    return [host convertRect:inWindow fromView:window];
}

static int duo_fill_env(UIView *view, DuoEnv *env) {
    UIView *host;
    UIWindow *window;
    CGRect hostBounds;
    CGRect safeInWindow;
    CGRect safeInHost;
    CGRect clipped;
    CGRect keyboard;
    if (!view || !env) return 0;
    host = view.superview;
    window = view.window;
    if (!host || !window) return 0;

    hostBounds = host.bounds;
    env->bounds = duo_rect_make(hostBounds.origin.x, hostBounds.origin.y, hostBounds.size.width, hostBounds.size.height);
    env->safeArea = (DuoInsets){0, 0, 0, 0};
    env->keyboard = duo_rect_make(0, 0, 0, 0);
    env->hasKeyboard = 0;

    safeInWindow = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
    safeInHost = [host convertRect:safeInWindow fromView:window];
    clipped = CGRectIntersection(safeInHost, hostBounds);
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) {
        UIEdgeInsets hostInsets = host.safeAreaInsets;
        env->safeArea.top = hostInsets.top;
        env->safeArea.left = hostInsets.left;
        env->safeArea.bottom = hostInsets.bottom;
        env->safeArea.right = hostInsets.right;
    } else {
        env->safeArea.left = CGRectGetMinX(clipped) - CGRectGetMinX(hostBounds);
        env->safeArea.top = CGRectGetMinY(clipped) - CGRectGetMinY(hostBounds);
        env->safeArea.right = CGRectGetMaxX(hostBounds) - CGRectGetMaxX(clipped);
        env->safeArea.bottom = CGRectGetMaxY(hostBounds) - CGRectGetMaxY(clipped);
    }
    if (env->safeArea.left < 0) env->safeArea.left = 0;
    if (env->safeArea.top < 0) env->safeArea.top = 0;
    if (env->safeArea.right < 0) env->safeArea.right = 0;
    if (env->safeArea.bottom < 0) env->safeArea.bottom = 0;

    keyboard = duo_keyboard_in_host(host);
    if (!CGRectIsNull(keyboard) && !CGRectIsEmpty(keyboard)) {
        env->hasKeyboard = 1;
        env->keyboard = duo_rect_make(keyboard.origin.x, keyboard.origin.y, keyboard.size.width, keyboard.size.height);
    }
    return 1;
}

static CGRect duo_proposed_bar_frame(UIView *view, CGRect proposed) {
    DuoEnv env;
    DuoRect out;
    if (!view || view.hidden) return proposed;
    if (!duo_fill_env(view, &env)) return proposed;
    if (!duo_place_bar(&env, duo_rect_make(proposed.origin.x, proposed.origin.y, proposed.size.width, proposed.size.height), &out)) {
        return proposed;
    }
    return CGRectMake(out.x, out.y, out.w, out.h);
}

static void duo_bar_layout(UIView *self, SEL _cmd) {
    DuoHookSlot *slot = duo_slot_for_class(object_getClass(self));
    CGRect fixed;
    if (!slot) return;
    if (duo_bar_depth > 2) {
        if (slot->origLayout) slot->origLayout(self, _cmd);
        return;
    }
    duo_bar_depth++;
    if (slot->origLayout) slot->origLayout(self, _cmd);
    fixed = duo_proposed_bar_frame(self, self.frame);
    if (!CGRectEqualToRect(fixed, self.frame) && slot->origSetFrame) {
        slot->origSetFrame(self, @selector(setFrame:), fixed);
    }
    duo_bar_depth--;
}

static void duo_bar_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    DuoHookSlot *slot = duo_slot_for_class(object_getClass(self));
    if (!slot) return;
    if (duo_bar_depth == 0) frame = duo_proposed_bar_frame(self, frame);
    if (slot->origSetFrame) slot->origSetFrame(self, _cmd, frame);
}

static DuoHookSlot *duo_super_slot(Class cls) {
    for (Class cursor = class_getSuperclass(cls); cursor; cursor = class_getSuperclass(cursor)) {
        for (int i = 0; i < DUO_SLOT_COUNT; i++) {
            if (g_slots[i].cls == cursor) return &g_slots[i];
        }
    }
    return NULL;
}

static void duo_hook_bar_class(const char *name) {
    Class cls = objc_getClass(name);
    Method layout;
    Method frame;
    IMP layoutImp;
    IMP frameImp;
    DuoHookSlot *superSlot;
    int index;
    if (!cls) return;
    for (int i = 0; i < DUO_SLOT_COUNT; i++) {
        if (g_slots[i].cls == cls) return;
    }
    layout = class_getInstanceMethod(cls, @selector(layoutSubviews));
    frame = class_getInstanceMethod(cls, @selector(setFrame:));
    if (!layout || !frame) return;
    layoutImp = method_getImplementation(layout);
    frameImp = method_getImplementation(frame);
    if (layoutImp == (IMP)duo_bar_layout && frameImp == (IMP)duo_bar_setFrame) return;

    index = -1;
    for (int i = 0; i < DUO_SLOT_COUNT; i++) {
        if (!g_slots[i].cls) {
            index = i;
            break;
        }
    }
    if (index < 0) return;
    superSlot = duo_super_slot(cls);
    g_slots[index].cls = cls;
    g_slots[index].origLayout = layoutImp == (IMP)duo_bar_layout && superSlot
        ? superSlot->origLayout
        : (void (*)(UIView *, SEL))layoutImp;
    g_slots[index].origSetFrame = frameImp == (IMP)duo_bar_setFrame && superSlot
        ? superSlot->origSetFrame
        : (void (*)(UIView *, SEL, CGRect))frameImp;

    if (layoutImp != (IMP)duo_bar_layout) {
        if (!class_addMethod(cls, @selector(layoutSubviews), (IMP)duo_bar_layout, method_getTypeEncoding(layout))) {
            method_setImplementation(layout, (IMP)duo_bar_layout);
        }
    }
    if (frameImp != (IMP)duo_bar_setFrame) {
        if (!class_addMethod(cls, @selector(setFrame:), (IMP)duo_bar_setFrame, method_getTypeEncoding(frame))) {
            method_setImplementation(frame, (IMP)duo_bar_setFrame);
        }
    }
}

static void duo_try_hook_host_classes(void) {
    /* 宿主自定义底栏。类名来自这个仓库原来的注入点，不新增猜测出来的类。 */
    duo_hook_bar_class("AWENormalModeTabBar");
}

static int g_hook_queued;
static void duo_schedule_host_hook(void) {
    if (g_hook_queued) return;
    g_hook_queued = 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        g_hook_queued = 0;
        duo_try_hook_host_classes();
    });
}

static void duo_on_image(const struct mach_header *mh, intptr_t slide) {
    (void)mh;
    (void)slide;
    duo_schedule_host_hook();
}

static BOOL (*orig_pointInside)(UIView *, SEL, CGPoint, UIEvent *);
static BOOL duo_pointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    CGSize size;
    DuoRect hit;
    if (orig_pointInside && orig_pointInside(self, _cmd, point, event)) return YES;
    size = self.bounds.size;
    if (size.width + 0.5 >= 44.0 && size.height + 0.5 >= 44.0) return NO;
    hit = duo_hit_rect(duo_rect_make(self.bounds.origin.x, self.bounds.origin.y, size.width, size.height), 44.0, 16.0);
    return duo_rect_contains(hit, point.x, point.y);
}

static void (*orig_image_layout)(UIImageView *, SEL);
static void duo_image_layout(UIImageView *self, SEL _cmd) {
    UIImage *image;
    UIWindow *window;
    CGSize bounds;
    CGSize windowSize;
    BOOL wantFit;
    NSNumber *flag;
    if (orig_image_layout) orig_image_layout(self, _cmd);
    if (duo_media_depth > 1) return;
    image = self.image;
    window = self.window;
    if (!image || !window) return;
    bounds = self.bounds.size;
    windowSize = window.bounds.size;
    if (windowSize.width < 1 || windowSize.height < 1) return;
    if (bounds.width < windowSize.width * 0.7 || bounds.height < windowSize.height * 0.7) return;
    wantFit = duo_video_use_fit(bounds.width, bounds.height, image.size.width, image.size.height);
    flag = objc_getAssociatedObject(self, kDuoImageFit);
    if (wantFit) {
        if (self.contentMode == UIViewContentModeScaleAspectFill || self.contentMode == UIViewContentModeScaleToFill) {
            duo_media_depth++;
            objc_setAssociatedObject(self, kDuoImageFit, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            self.contentMode = UIViewContentModeScaleAspectFit;
            duo_media_depth--;
        }
    } else if (flag.boolValue) {
        duo_media_depth++;
        self.contentMode = UIViewContentModeScaleAspectFill;
        objc_setAssociatedObject(self, kDuoImageFit, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        duo_media_depth--;
    }
}

static void (*orig_player_layout)(CALayer *, SEL);
static void duo_player_layout(CALayer *self, SEL _cmd) {
    AVPlayerLayer *layer;
    CGSize video;
    CGSize bounds;
    if (orig_player_layout) orig_player_layout(self, _cmd);
    if (duo_media_depth > 1) return;
    if (![self isKindOfClass:[AVPlayerLayer class]]) return;
    layer = (AVPlayerLayer *)self;
    video = layer.player.currentItem.presentationSize;
    bounds = layer.bounds.size;
    if (!duo_video_use_fit(bounds.width, bounds.height, video.width, video.height)) {
        if (objc_getAssociatedObject(layer, kDuoPlayerFit)) {
            duo_media_depth++;
            layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            objc_setAssociatedObject(layer, kDuoPlayerFit, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            duo_media_depth--;
        }
        return;
    }
    if (![layer.videoGravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        duo_media_depth++;
        objc_setAssociatedObject(layer, kDuoPlayerFit, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        layer.videoGravity = AVLayerVideoGravityResizeAspect;
        duo_media_depth--;
    }
}

static void duo_update_keyboard_inset(UIViewController *vc) {
    NSValue *saved;
    UIEdgeInsets original;
    CGRect keyboard;
    CGRect overlapRect;
    double overlap = 0;
    double systemBottom;
    double extra;
    UIEdgeInsets insets;
    if (!vc.isViewLoaded || !vc.view) return;
    saved = objc_getAssociatedObject(vc, kDuoOrigAdditional);
    if (g_keyboard_visible) {
        keyboard = duo_keyboard_in_host(vc.view);
        if (!CGRectIsNull(keyboard)) {
            overlapRect = CGRectIntersection(vc.view.bounds, keyboard);
            if (!CGRectIsNull(overlapRect) && !CGRectIsEmpty(overlapRect)) overlap = overlapRect.size.height;
        }
    }
    if (!saved && overlap < 1.0) return;
    if (saved) {
        original = saved.UIEdgeInsetsValue;
    } else {
        original = vc.additionalSafeAreaInsets;
        objc_setAssociatedObject(vc, kDuoOrigAdditional, [NSValue valueWithUIEdgeInsets:original], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    systemBottom = vc.view.safeAreaInsets.bottom - vc.additionalSafeAreaInsets.bottom;
    if (systemBottom < 0) systemBottom = 0;
    extra = duo_additional_bottom(systemBottom + original.bottom, overlap);
    insets = original;
    insets.bottom = original.bottom + extra;
    if (!UIEdgeInsetsEqualToEdgeInsets(insets, vc.additionalSafeAreaInsets)) {
        vc.additionalSafeAreaInsets = insets;
    }
    if (overlap < 1.0 && UIEdgeInsetsEqualToEdgeInsets(insets, original)) {
        objc_setAssociatedObject(vc, kDuoOrigAdditional, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void duo_clamp_offscreen_presentation(UIViewController *vc) {
    UIView *view;
    UIView *host;
    CGRect hostBounds;
    CGRect frame;
    DuoEnv env;
    DuoRect clamped;
    BOOL offscreen;
    if (!vc.presentingViewController || !vc.isViewLoaded) return;
    switch (vc.modalPresentationStyle) {
        case UIModalPresentationFormSheet:
        case UIModalPresentationPageSheet:
        case UIModalPresentationPopover:
        case UIModalPresentationAutomatic:
            break;
        default:
            return;
    }
    view = vc.view;
    host = view.superview;
    if (!view || !host) return;
    hostBounds = host.bounds;
    frame = view.frame;
    offscreen = CGRectGetMinX(frame) < CGRectGetMinX(hostBounds) - 0.5
        || CGRectGetMinY(frame) < CGRectGetMinY(hostBounds) - 0.5
        || CGRectGetMaxX(frame) > CGRectGetMaxX(hostBounds) + 0.5
        || CGRectGetMaxY(frame) > CGRectGetMaxY(hostBounds) + 0.5;
    if (!offscreen) return;
    if (!duo_fill_env(view, &env)) return;
    clamped = duo_clamp_panel(&env, duo_rect_make(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height), 8.0);
    if (duo_rect_near(duo_rect_make(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height), clamped, 1.0)) return;
    view.frame = CGRectMake(clamped.x, clamped.y, clamped.w, clamped.h);
}

static void (*orig_vc_layout)(UIViewController *, SEL);
static void duo_vc_layout(UIViewController *self, SEL _cmd) {
    if (orig_vc_layout) orig_vc_layout(self, _cmd);
    if (duo_vc_depth > 2) return;
    duo_vc_depth++;
    duo_clamp_offscreen_presentation(self);
    duo_update_keyboard_inset(self);
    duo_vc_depth--;
}

static UIView *duo_first_responder_in(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = duo_first_responder_in(sub);
        if (found) return found;
    }
    return nil;
}

static UIView *duo_find_first_responder(void) {
    if (![NSThread isMainThread]) return nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIView *found = duo_first_responder_in(window);
            if (found) return found;
        }
    }
    return nil;
}

static void duo_layout_windows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            [window layoutIfNeeded];
        }
    }
}

static UIScrollView *duo_enclosing_scroll(UIView *view, UIWindow *window) {
    for (UIView *cursor = view; cursor && cursor != window; cursor = cursor.superview) {
        if ([cursor isKindOfClass:[UITextView class]]) continue;
        if ([cursor isKindOfClass:[UIScrollView class]]) return (UIScrollView *)cursor;
    }
    return nil;
}

static void duo_restore_scroll(UIScrollView *scroll) {
    NSValue *content;
    NSValue *indicator;
    if (!scroll) return;
    content = objc_getAssociatedObject(scroll, kDuoOrigInset);
    indicator = objc_getAssociatedObject(scroll, kDuoOrigIndicator);
    if (content) scroll.contentInset = content.UIEdgeInsetsValue;
    if (indicator) scroll.verticalScrollIndicatorInsets = indicator.UIEdgeInsetsValue;
    objc_setAssociatedObject(scroll, kDuoOrigInset, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scroll, kDuoOrigIndicator, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scroll, kDuoApplied, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void duo_apply_scroll(UIScrollView *scroll, UIView *responder) {
    UIEdgeInsets original;
    UIEdgeInsets indicator;
    UIEdgeInsets insets;
    CGRect keyboard;
    CGRect overlapRect;
    NSNumber *applied;
    double overlap = 0;
    double base;
    double extra;
    if (!scroll) return;
    if (!objc_getAssociatedObject(scroll, kDuoOrigInset)) {
        objc_setAssociatedObject(scroll, kDuoOrigInset, [NSValue valueWithUIEdgeInsets:scroll.contentInset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(scroll, kDuoOrigIndicator, [NSValue valueWithUIEdgeInsets:scroll.verticalScrollIndicatorInsets], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    original = ((NSValue *)objc_getAssociatedObject(scroll, kDuoOrigInset)).UIEdgeInsetsValue;
    keyboard = duo_keyboard_in_host(scroll);
    if (!CGRectIsNull(keyboard)) {
        overlapRect = CGRectIntersection(scroll.bounds, keyboard);
        if (!CGRectIsNull(overlapRect) && !CGRectIsEmpty(overlapRect)) overlap = overlapRect.size.height;
    }
    applied = objc_getAssociatedObject(scroll, kDuoApplied);
    base = scroll.adjustedContentInset.bottom;
    if (applied) base -= applied.doubleValue;
    if (base < 0) base = 0;
    extra = duo_additional_bottom(base, overlap);
    insets = original;
    insets.bottom = original.bottom + extra;
    scroll.contentInset = insets;
    indicator = ((NSValue *)objc_getAssociatedObject(scroll, kDuoOrigIndicator)).UIEdgeInsetsValue;
    indicator.bottom = original.bottom + extra;
    scroll.verticalScrollIndicatorInsets = indicator;
    objc_setAssociatedObject(scroll, kDuoApplied, @(extra), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (extra > 0 && responder) {
        CGRect rect = [scroll convertRect:responder.bounds fromView:responder];
        [scroll scrollRectToVisible:CGRectInset(rect, 0, -8) animated:NO];
    }
}

static void duo_restore_panel(UIView *panel) {
    NSValue *saved;
    if (!panel) return;
    saved = objc_getAssociatedObject(panel, kDuoOrigFrame);
    if (saved) panel.frame = saved.CGRectValue;
    objc_setAssociatedObject(panel, kDuoOrigFrame, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void duo_place_custom_panel(UIView *panel) {
    NSValue *saved;
    CGRect original;
    DuoEnv env;
    DuoRect clamped;
    CGRect next;
    if (!panel.superview) return;
    saved = objc_getAssociatedObject(panel, kDuoOrigFrame);
    if (!saved) {
        saved = [NSValue valueWithCGRect:panel.frame];
        objc_setAssociatedObject(panel, kDuoOrigFrame, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    original = saved.CGRectValue;
    if (!duo_fill_env(panel, &env)) return;
    clamped = duo_clamp_panel(&env, duo_rect_make(original.origin.x, original.origin.y, original.size.width, original.size.height), 8.0);
    next = CGRectMake(clamped.x, clamped.y, clamped.w, clamped.h);
    if (!CGRectEqualToRect(next, panel.frame)) panel.frame = next;
}

static UIView *duo_panel_covering_keyboard(UIView *responder) {
    UIWindow *window = responder.window;
    UIView *panel = nil;
    CGRect keyboard;
    if (!window) return nil;
    keyboard = duo_keyboard_in_host(window);
    if (CGRectIsNull(keyboard)) return nil;
    for (UIView *cursor = responder; cursor && cursor != window; cursor = cursor.superview) {
        UIView *host = cursor.superview;
        CGRect inWindow;
        if (!host || duo_slot_for_class(object_getClass(cursor))) continue;
        if (host.bounds.size.height < 1 || cursor.frame.size.height >= host.bounds.size.height * 0.92) continue;
        if (cursor.frame.size.width < host.bounds.size.width * 0.5) continue;
        inWindow = [window convertRect:cursor.frame fromView:host];
        if (CGRectIntersectsRect(inWindow, keyboard)) panel = cursor;
    }
    return panel;
}

static BOOL duo_keyboard_hits_a_window(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            CGRect keyboard = duo_keyboard_in_host(window);
            if (!CGRectIsNull(keyboard) && CGRectIntersectsRect(window.bounds, keyboard)) return YES;
        }
    }
    return NO;
}

static void duo_handle_keyboard(NSNotification *note) {
    NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
    UIView *responder;
    UIScrollView *scroll;
    UIView *panel;
    g_keyboard_screen = value ? value.CGRectValue : CGRectZero;
    g_keyboard_visible = ![note.name isEqualToString:UIKeyboardWillHideNotification];
    if (g_keyboard_visible && !duo_keyboard_hits_a_window()) g_keyboard_visible = 0;
    duo_layout_windows();
    if (!g_keyboard_visible) {
        duo_restore_scroll(g_keyboardScroll);
        g_keyboardScroll = nil;
        duo_restore_panel(g_keyboardPanel);
        g_keyboardPanel = nil;
        return;
    }
    responder = duo_find_first_responder();
    if (!responder) return;
    scroll = duo_enclosing_scroll(responder, responder.window);
    if (g_keyboardScroll && g_keyboardScroll != scroll) duo_restore_scroll(g_keyboardScroll);
    g_keyboardScroll = scroll;
    duo_apply_scroll(scroll, responder);
    panel = duo_panel_covering_keyboard(responder);
    if (!panel) panel = g_keyboardPanel;
    if (g_keyboardPanel && g_keyboardPanel != panel) duo_restore_panel(g_keyboardPanel);
    g_keyboardPanel = panel;
    if (panel) duo_place_custom_panel(panel);
}

static NSInteger (*orig_tab_mode)(id, SEL);
static void (*orig_tab_set_mode)(id, SEL, NSInteger);

static NSInteger duo_tab_mode(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return UITabBarControllerModeTabBar;
}

static void duo_tab_set_mode(id self, SEL _cmd, NSInteger mode) {
    (void)mode;
    if (orig_tab_set_mode) orig_tab_set_mode(self, _cmd, UITabBarControllerModeTabBar);
}

static void duo_hook_method(Class cls, SEL sel, IMP imp, IMP *origOut) {
    Method method;
    if (!cls) return;
    method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    if (origOut) *origOut = method_getImplementation(method);
    if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(method))) {
        method_setImplementation(method, imp);
    }
}

static void duo_hook_tab_mode(void) {
    Class cls = objc_getClass("UITabBarController");
    Method getter;
    Method setter;
    if (!cls) return;
    getter = class_getInstanceMethod(cls, @selector(mode));
    setter = class_getInstanceMethod(cls, @selector(setMode:));
    /* iOS 15–17 没有这个方法。只替换系统已经提供的实现，不给旧系统补一个方法。 */
    if (!getter || !setter) return;
    orig_tab_mode = (NSInteger (*)(id, SEL))method_getImplementation(getter);
    orig_tab_set_mode = (void (*)(id, SEL, NSInteger))method_getImplementation(setter);
    (void)orig_tab_mode;
    if (!class_addMethod(cls, @selector(mode), (IMP)duo_tab_mode, method_getTypeEncoding(getter))) {
        method_setImplementation(getter, (IMP)duo_tab_mode);
    }
    if (!class_addMethod(cls, @selector(setMode:), (IMP)duo_tab_set_mode, method_getTypeEncoding(setter))) {
        method_setImplementation(setter, (IMP)duo_tab_set_mode);
    }
}

__attribute__((constructor))
static void duo_adapt_init(void) {
    @autoreleasepool {
        NSNotificationCenter *center;
        duo_require_ios_27_1_symbols();
        duo_hook_method(objc_getClass("UIControl"), @selector(pointInside:withEvent:), (IMP)duo_pointInside, (IMP *)&orig_pointInside);
        duo_hook_method(objc_getClass("UIImageView"), @selector(layoutSubviews), (IMP)duo_image_layout, (IMP *)&orig_image_layout);
        duo_hook_method(objc_getClass("AVPlayerLayer"), @selector(layoutSublayers), (IMP)duo_player_layout, (IMP *)&orig_player_layout);
        duo_hook_method(objc_getClass("UIViewController"), @selector(viewDidLayoutSubviews), (IMP)duo_vc_layout, (IMP *)&orig_vc_layout);
        duo_hook_tab_mode();
        duo_hook_bar_class("UIToolbar");
        duo_hook_bar_class("UINavigationBar");
        duo_hook_bar_class("UITabBar");
        duo_try_hook_host_classes();
        _dyld_register_func_for_add_image(duo_on_image);
        duo_schedule_host_hook();
        center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            duo_handle_keyboard(note);
        }];
        [center addObserverForName:UIKeyboardWillHideNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            duo_handle_keyboard(note);
        }];
    }
}
