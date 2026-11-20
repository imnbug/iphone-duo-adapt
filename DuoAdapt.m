// DuoAdapt.m - based on 47542b1 (the 22:11 good layout) + safe global hitTest forwarding
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

// ---------- 1. iOS 27.1 vertical bar off ----------
static NSInteger duo_preferredVerticalBarBehavior(id self, SEL _cmd) { return 1; }
static id duo_childForPreferredVerticalBarBehavior(id self, SEL _cmd) { return nil; }

// ---------- 2. TabBarController bottom mode ----------
static NSInteger duo_tabBarControllerMode(id self, SEL _cmd) { return 1; }
static void duo_setTabBarControllerMode(id self, SEL _cmd, NSInteger mode) {}

// ---------- 3. Phone idiom / compact ----------
static NSInteger duo_userInterfaceIdiom(id self, SEL _cmd) { return 0; }
static NSInteger duo_horizontalSizeClass(id self, SEL _cmd) { return 1; }
static NSInteger duo_verticalSizeClass(id self, SEL _cmd) { return 2; }
static BOOL duo_returnNO(id self, SEL _cmd) { return NO; }

// ---------- 4. Bottom TabBar guard ----------
static BOOL gInTabBarSetFrame = NO;
static void (*orig_tabBar_setFrame)(UIView *, SEL, CGRect) = NULL;
static void duo_tabBar_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    if (!gInTabBarSetFrame) {
        gInTabBarSetFrame = YES;
        UIWindow *win = self.window;
        if (win) {
            CGRect wb = win.bounds;
            if (frame.size.height > 20 && frame.size.height < 130 && wb.size.height > 200) {
                frame.origin.x = 0;
                frame.origin.y = wb.size.height - frame.size.height;
                frame.size.width = wb.size.width;
            }
        }
        gInTabBarSetFrame = NO;
    }
    if (orig_tabBar_setFrame) orig_tabBar_setFrame(self, _cmd, frame);
}

// ---------- 5. Safe global hitTest forwarding ----------
// Hooked ONCE on UIView only. Subclasses calling [super hitTest:] land here and we always
// call UIView's real implementation -> no missing-IMP, no recursion. Runs only on touches.
static const void *kDuoForwardKey = &kDuoForwardKey;
static UIView *(*orig_UIView_hitTest)(UIView *, SEL, CGPoint, UIEvent *) = NULL;
static UIView *duo_UIView_hitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    UIView *hit = orig_UIView_hitTest(self, _cmd, point, event);
    if (hit) return hit;
    NSHashTable *targets = objc_getAssociatedObject(self, kDuoForwardKey);
    if (!targets || targets.count == 0) return nil;
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    for (UIView *t in targets) {
        if (!t || t.hidden || !t.userInteractionEnabled || t.alpha < 0.01 || !t.window) continue;
        if (![t isDescendantOfView:self]) continue;
        CGPoint p = [self convertPoint:point toView:t];
        if ([t pointInside:p withEvent:event]) {
            UIView *h = [t hitTest:p withEvent:event];
            if (h) return h;
        }
    }
    return nil;
}

static void duo_registerForward(UIView *target, UIView *stopAt) {
    UIView *cur = target.superview;
    int hops = 0;
    while (cur && hops < 10) {
        NSHashTable *set = objc_getAssociatedObject(cur, kDuoForwardKey);
        if (!set) {
            set = [NSHashTable weakObjectsHashTable];
            objc_setAssociatedObject(cur, kDuoForwardKey, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![set containsObject:target]) [set addObject:target];
        if (cur == stopAt) break;
        cur = cur.superview;
        hops++;
    }
}

// ---------- 6. Align right buttons + left text (transform only, write only on change) ----------
static const void *kDuoMovedKey = &kDuoMovedKey;

static void duo_setTranslation(UIView *v, CGFloat dx, CGFloat dy) {
    CGAffineTransform t = v.transform;
    if (fabs(t.tx - dx) < 1.0 && fabs(t.ty - dy) < 1.0 && t.a == 1 && t.d == 1 && t.b == 0 && t.c == 0) return;
    v.transform = (fabs(dx) < 0.5 && fabs(dy) < 0.5) ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(dx, dy);
}

static void duo_align(UIView *root, UIView *vcRoot, UIWindow *win, int depth) {
    if (!root || depth > 6) return;
    CGFloat W = win.bounds.size.width, H = win.bounds.size.height;
    BOOL wide = W > 480.0;
    BOOL tall = H > 760.0;
    CGFloat targetBottom = H - 104.0;

    for (UIView *sub in root.subviews) {
        CGRect b = sub.bounds;
        const char *cn = class_getName([sub class]);
        if (!cn) continue;

        BOOL isRight = (b.size.width >= 36 && b.size.width <= 130 && b.size.height >= 160) &&
            (strstr(cn, "RightElement") || strstr(cn, "RightContainer") ||
             !strcmp(cn, "AWEElementStackView") || !strcmp(cn, "AWEElementContainer"));

        BOOL isLeft = !isRight && (b.size.width >= 150 && b.size.width <= 460 && b.size.height >= 40 && b.size.height <= 360) &&
            (strstr(cn, "LeftElement") || strstr(cn, "LeftContainer") ||
             !strcmp(cn, "AWEElementStackView") || !strcmp(cn, "AWEElementContainer"));

        if (isRight || isLeft) {
            if (!wide) {
                if (objc_getAssociatedObject(sub, kDuoMovedKey)) {
                    duo_setTranslation(sub, 0, 0);
                    objc_setAssociatedObject(sub, kDuoMovedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                continue;
            }
            CGAffineTransform t = sub.transform;
            CGRect r = [sub convertRect:b toView:win];
            CGFloat rawX = r.origin.x - t.tx;
            CGFloat rawY = r.origin.y - t.ty;
            CGFloat rawMaxY = CGRectGetMaxY(r) - t.ty;

            // Safety guard: if the view is off-screen (e.g. preloading cell or horizontal swipe transition),
            // reset transform to identity and never kick it off-screen!
            if (rawX < -10.0 || rawX + b.size.width > W + 10.0 || rawY < -10.0 || rawMaxY > H + 10.0) {
                duo_setTranslation(sub, 0, 0);
                continue;
            }

            CGFloat dx = 0, dy = 0;
            if (isRight) {
                CGFloat targetX = W - b.size.width - 18.0;
                dx = targetX - rawX;
                if (dx < 20.0 || dx > W * 0.55) dx = 0;
            } else if (rawX > W * 0.45 || rawY < H * 0.25) {
                // not the bottom-left caption block
                if (sub.subviews.count > 0 && sub.subviews.count < 25) duo_align(sub, vcRoot, win, depth + 1);
                continue;
            }
            if (tall) {
                CGFloat diff = targetBottom - rawMaxY;
                if (diff > 40.0 && diff < H * 0.45 && (rawMaxY + diff) <= H - 80.0) dy = diff;
            }
            duo_setTranslation(sub, dx, dy);
            if (dx > 0.5 || dy > 0.5) {
                objc_setAssociatedObject(sub, kDuoMovedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                duo_registerForward(sub, vcRoot);
            }
            continue;
        }
        if (sub.subviews.count > 0 && sub.subviews.count < 25) duo_align(sub, vcRoot, win, depth + 1);
    }
}

static void (*orig_pi_viewDidLayoutSubviews)(UIViewController *, SEL) = NULL;
static void duo_pi_viewDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    if (orig_pi_viewDidLayoutSubviews) orig_pi_viewDidLayoutSubviews(self, _cmd);
    UIView *v = self.view;
    if (v.window) duo_align(v, v, v.window, 0);
}

static void (*orig_vc_viewDidAppear)(UIViewController *, SEL, BOOL) = NULL;
static void duo_vc_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_vc_viewDidAppear) orig_vc_viewDidAppear(self, _cmd, animated);
    SEL s = sel_registerName("setNeedsUpdateOfVerticalBarConfiguration");
    if ([self respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(self, s);
}

// ---------- helper ----------
static void hookOrAdd(Class cls, SEL sel, IMP imp, const char *types, IMP *origOut) {
    if (!cls || !sel || !imp) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        IMP cur = method_getImplementation(m);
        if (cur == imp) return;
        if (origOut && *origOut == NULL) *origOut = cur;
        if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) method_setImplementation(m, imp);
    } else {
        class_addMethod(cls, sel, imp, types);
    }
}

__attribute__((constructor))
static void duo_adapt_init(void) {
    @autoreleasepool {
        SEL sVB = sel_registerName("preferredVerticalBarBehavior");
        SEL sCVB = sel_registerName("childForPreferredVerticalBarBehavior");
        for (NSString *n in @[@"UIViewController", @"UINavigationController", @"UITabBarController",
                              @"AWEBaseTabBarController", @"AWENormalModeTabBarController",
                              @"AWEBasicModeTabBarController", @"AWETeenModeTabBarController"]) {
            Class c = NSClassFromString(n);
            if (c) {
                hookOrAdd(c, sVB, (IMP)duo_preferredVerticalBarBehavior, "q@:", NULL);
                hookOrAdd(c, sCVB, (IMP)duo_childForPreferredVerticalBarBehavior, "@@:", NULL);
            }
        }
        hookOrAdd([UIViewController class], @selector(viewDidAppear:), (IMP)duo_vc_viewDidAppear, "v@:B", (IMP *)&orig_vc_viewDidAppear);

        hookOrAdd([UITabBarController class], sel_registerName("mode"), (IMP)duo_tabBarControllerMode, "q@:", NULL);
        hookOrAdd([UITabBarController class], sel_registerName("setMode:"), (IMP)duo_setTabBarControllerMode, "v@:q", NULL);

        hookOrAdd([UIDevice class], @selector(userInterfaceIdiom), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        hookOrAdd([UITraitCollection class], @selector(userInterfaceIdiom), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        hookOrAdd([UITraitCollection class], @selector(horizontalSizeClass), (IMP)duo_horizontalSizeClass, "q@:", NULL);
        hookOrAdd([UITraitCollection class], @selector(verticalSizeClass), (IMP)duo_verticalSizeClass, "q@:", NULL);

        // global, single hitTest hook on UIView
        Method hm = class_getInstanceMethod([UIView class], @selector(hitTest:withEvent:));
        if (hm) {
            orig_UIView_hitTest = (void *)method_getImplementation(hm);
            method_setImplementation(hm, (IMP)duo_UIView_hitTest);
        }

        NSArray *padClasses = @[@"AWEPadModuleAdapter", @"AWEPadBizUIAdapter", @"AWEPadFullPageAdapter",
            @"AWEPadSplitScreenAdapter", @"AWEPadSplitScreenAdapterImpl", @"AWEPadTabBarControllerAdapter",
            @"AWEPadTabBarAdapter", @"AWEPadUIAdaptor", @"AWEPadUIAdaption", @"AWEPadLeftSideBarAdapter",
            @"AWEPadUserPageAdapter", @"AWEPadDetailTableAdapter", @"AWEPadPureModeAdapter",
            @"AWEDeviceManager", @"UIDevice"];
        NSArray *padSels = @[@"isPad", @"isIPad", @"isIpad", @"isiPad", @"isPadDevice", @"isIPadDevice",
            @"awe_isIpad", @"btd_isPadDevice", @"iesll_isPadDevice", @"acc_isIPad", @"cj_isPad",
            @"deviceIsIpad", @"checkIsPad", @"htslive_isiPad", @"puzzle_isiPad", @"sc_isPadDevice",
            @"isPadUI", @"isPadSplitScreen", @"isPadSplit", @"isPadSplitStyle", @"isPadLayout",
            @"isPadAdaptionMode", @"isInSplitScreen"];
        for (NSString *n in padClasses) {
            Class c = NSClassFromString(n);
            if (!c) continue;
            Class mc = object_getClass(c);
            for (NSString *s in padSels) {
                SEL sel = sel_registerName(s.UTF8String);
                if (class_getInstanceMethod(c, sel)) hookOrAdd(c, sel, (IMP)duo_returnNO, "B@:", NULL);
                if (mc && class_getInstanceMethod(mc, sel)) hookOrAdd(mc, sel, (IMP)duo_returnNO, "B@:", NULL);
            }
        }

        Class tb = NSClassFromString(@"AWENormalModeTabBar");
        if (tb) hookOrAdd(tb, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);

        Class pi = NSClassFromString(@"AWEPlayInteractionViewController");
        if (pi) hookOrAdd(pi, @selector(viewDidLayoutSubviews), (IMP)duo_pi_viewDidLayoutSubviews, "v@:", (IMP *)&orig_pi_viewDidLayoutSubviews);
    }
}
