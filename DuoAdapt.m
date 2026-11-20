// DuoAdapt.m - iPhone Duo (iOS 27.1) Zero-Overhead Transform + HitTest UIKit Adaptation for Douyin
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

// ============================================================================
// 1. iOS 27.1 UIKit Vertical Side-Bar Suppression (Outer & Inner Landscape)
// ============================================================================
static NSInteger duo_preferredVerticalBarBehavior(id self, SEL _cmd) {
    return 1; // UIVerticalBarBehaviorDisabled (.disabled)
}

static id duo_childForPreferredVerticalBarBehavior(id self, SEL _cmd) {
    return nil; // Do not let child VCs re-enable vertical bar
}

// ============================================================================
// 2. iOS 18+ / 27.1 UITabBarController Bottom Mode Lock
// ============================================================================
static NSInteger duo_tabBarControllerMode(id self, SEL _cmd) {
    return 1; // UITabBarControllerModeTabBar
}

static void duo_setTabBarControllerMode(id self, SEL _cmd, NSInteger mode) {
    // Block switching to automatic (0) or tabSidebar (2)
}

// ============================================================================
// 3. Pure iPhone Idiom & Compact Horizontal Size Class Enforcement
// ============================================================================
static NSInteger duo_userInterfaceIdiom(id self, SEL _cmd) {
    return 0; // UIUserInterfaceIdiomPhone
}

static NSInteger duo_horizontalSizeClass(id self, SEL _cmd) {
    return 1; // UIUserInterfaceSizeClassCompact
}

static NSInteger duo_verticalSizeClass(id self, SEL _cmd) {
    return 2; // UIUserInterfaceSizeClassRegular
}

static BOOL duo_returnNO(id self, SEL _cmd) {
    return NO;
}

// ============================================================================
// 4. Bottom TabBar Width & Position Guard
// ============================================================================
static BOOL gInTabBarSetFrame = NO;
static void (*orig_tabBar_setFrame)(UIView *self, SEL _cmd, CGRect frame) = NULL;
static void duo_tabBar_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    if (!gInTabBarSetFrame) {
        gInTabBarSetFrame = YES;
        UIWindow *win = self.window;
        if (win) {
            CGRect winBounds = win.bounds;
            if (frame.size.height > 20 && frame.size.height < 130 && winBounds.size.height > 200) {
                frame.origin.x = 0;
                frame.origin.y = winBounds.size.height - frame.size.height;
                frame.size.width = winBounds.size.width;
            }
        }
        gInTabBarSetFrame = NO;
    }
    if (orig_tabBar_setFrame) {
        orig_tabBar_setFrame(self, _cmd, frame);
    }
}

// ============================================================================
// 5. HitTest Forwarding for Transformed Views Outside Parent Bounds
// ============================================================================
static const void *kDuoForwardedViewsKey = &kDuoForwardedViewsKey;
static const void *kDuoOrigHitTestKey = &kDuoOrigHitTestKey;
static const void *kDuoLastAlignedSizeKey = &kDuoLastAlignedSizeKey;

static UIView *duo_forwardHitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    NSValue *origVal = objc_getAssociatedObject([self class], kDuoOrigHitTestKey);
    UIView *hit = nil;
    if (origVal) {
        UIView *(*origIMP)(id, SEL, CGPoint, UIEvent *) = (UIView *(*)(id, SEL, CGPoint, UIEvent *))[origVal pointerValue];
        if (origIMP) {
            hit = origIMP(self, _cmd, point, event);
        }
    }
    if (hit) return hit;

    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    NSHashTable<UIView *> *targets = objc_getAssociatedObject(self, kDuoForwardedViewsKey);
    if (targets && targets.count > 0) {
        for (UIView *target in targets) {
            if (!target || target.hidden || !target.userInteractionEnabled || target.alpha < 0.01 || !target.window) {
                continue;
            }
            CGPoint ptInTarget = [self convertPoint:point toView:target];
            if ([target pointInside:ptInTarget withEvent:event]) {
                UIView *subHit = [target hitTest:ptInTarget withEvent:event];
                if (subHit) return subHit;
            }
        }
    }
    return nil;
}

static void duo_ensureHitTestHookOnClass(Class cls) {
    if (!cls || cls == [UIView class] || cls == [UIWindow class]) return;
    if (objc_getAssociatedObject(cls, kDuoOrigHitTestKey)) return;
    Method m = class_getInstanceMethod(cls, @selector(hitTest:withEvent:));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    if (orig == (IMP)duo_forwardHitTest) return;
    objc_setAssociatedObject(cls, kDuoOrigHitTestKey, [NSValue valueWithPointer:orig], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)duo_forwardHitTest, method_getTypeEncoding(m))) {
        method_setImplementation(m, (IMP)duo_forwardHitTest);
    }
}

static void duo_registerForwardedTargetOnAncestors(UIView *target, UIView *stopAtRoot) {
    if (!target) return;
    UIView *cur = target.superview;
    int hops = 0;
    while (cur && hops < 8) {
        Class cls = [cur class];
        if (cls != [UIView class] && cls != [UIWindow class]) {
            duo_ensureHitTestHookOnClass(cls);
            NSHashTable<UIView *> *set = objc_getAssociatedObject(cur, kDuoForwardedViewsKey);
            if (!set) {
                set = [NSHashTable weakObjectsHashTable];
                objc_setAssociatedObject(cur, kDuoForwardedViewsKey, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [set addObject:target];
        }
        if (cur == stopAtRoot || [cur isKindOfClass:[UITableViewCell class]]) break;
        cur = cur.superview;
        hops++;
    }
}

// ============================================================================
// 6. Zero-Overhead Transform-Only Right Buttons & Left Description Alignment
// ============================================================================
// - Uses C-string class_getName() (zero NSString allocations)
// - Never resets transform to Identity before reading (computes raw coords via tx/ty)
// - Only writes transform when delta >= 1.0pt (zero GPU layer re-composite / zero heat!)
// - Skips entirely if already aligned for the current window size!
static BOOL duo_alignInteractionViews(UIView *rootView, UIView *vcRoot, UIWindow *win, int depth) {
    if (!rootView || !win || depth > 5) return NO;
    CGFloat winW = win.bounds.size.width;
    CGFloat winH = win.bounds.size.height;
    BOOL alignedAny = NO;

    if (winW <= 480.0) {
        for (UIView *sub in rootView.subviews) {
            if (sub.tag == 271001 || sub.tag == 271002) {
                if (!CGAffineTransformIsIdentity(sub.transform)) {
                    sub.transform = CGAffineTransformIdentity;
                }
                sub.tag = 0;
                alignedAny = YES;
            }
            if (sub.subviews.count > 0 && sub.subviews.count < 20) {
                if (duo_alignInteractionViews(sub, vcRoot, win, depth + 1)) alignedAny = YES;
            }
        }
        return alignedAny;
    }

    CGFloat targetBottomY = winH - 104.0;
    BOOL isTallInnerScreen = (winH > 760.0);

    for (UIView *sub in rootView.subviews) {
        CGRect b = sub.bounds;
        const char *clsName = class_getName([sub class]);
        if (!clsName) continue;

        BOOL isRightStack = (b.size.width >= 36.0 && b.size.width <= 130.0 && b.size.height >= 160.0) &&
                            (strstr(clsName, "RightElement") != NULL ||
                             strstr(clsName, "RightContainer") != NULL ||
                             strcmp(clsName, "AWEElementStackView") == 0 ||
                             strcmp(clsName, "AWEElementContainer") == 0);

        if (isRightStack) {
            CGAffineTransform curT = sub.transform;
            CGRect rectInWin = [sub convertRect:b toView:win];
            // Compute untransformed screen origin without mutating sub.transform!
            CGFloat rawOriginX = rectInWin.origin.x - curT.tx;
            CGFloat rawMaxY = CGRectGetMaxY(rectInWin) - curT.ty;

            CGFloat desiredX = winW - rectInWin.size.width - 18.0;
            CGFloat dx = desiredX - rawOriginX;
            if (dx < 20.0) dx = 0.0;

            CGFloat dy = 0.0;
            if (isTallInnerScreen) {
                CGFloat diffY = targetBottomY - rawMaxY;
                if (diffY > 40.0 && diffY < winH * 0.48) {
                    dy = diffY;
                }
            }

            if (fabs(curT.tx - dx) >= 1.0 || fabs(curT.ty - dy) >= 1.0) {
                if (dx > 0.5 || dy > 0.5) {
                    sub.transform = CGAffineTransformMakeTranslation(dx, dy);
                    sub.tag = 271001;
                } else {
                    sub.transform = CGAffineTransformIdentity;
                    if (sub.tag == 271001) sub.tag = 0;
                }
            }
            if (dx > 0.5 || dy > 0.5) {
                duo_registerForwardedTargetOnAncestors(sub, vcRoot);
            }
            alignedAny = YES;
            continue;
        }

        BOOL isLeftStack = isTallInnerScreen &&
                           (b.size.width >= 150.0 && b.size.width <= 460.0 && b.size.height >= 40.0 && b.size.height <= 360.0) &&
                           (strstr(clsName, "LeftElement") != NULL ||
                            strstr(clsName, "LeftContainer") != NULL ||
                            strcmp(clsName, "AWEElementStackView") == 0 ||
                            strcmp(clsName, "AWEElementContainer") == 0);

        if (isLeftStack) {
            CGAffineTransform curT = sub.transform;
            CGRect rectInWin = [sub convertRect:b toView:win];
            CGFloat rawOriginX = rectInWin.origin.x - curT.tx;
            CGFloat rawOriginY = rectInWin.origin.y - curT.ty;
            CGFloat rawMaxY = CGRectGetMaxY(rectInWin) - curT.ty;

            if (rawOriginY > winH * 0.25 && rawOriginX < winW * 0.45) {
                CGFloat diffY = targetBottomY - rawMaxY;
                if (diffY > 40.0 && diffY < winH * 0.48) {
                    if (fabs(curT.ty - diffY) >= 1.0 || fabs(curT.tx) >= 1.0) {
                        sub.transform = CGAffineTransformMakeTranslation(0, diffY);
                        sub.tag = 271002;
                    }
                    duo_registerForwardedTargetOnAncestors(sub, vcRoot);
                    alignedAny = YES;
                    continue;
                }
            }
            if (sub.tag == 271002) {
                if (!CGAffineTransformIsIdentity(curT)) {
                    sub.transform = CGAffineTransformIdentity;
                }
                sub.tag = 0;
            }
        }

        if (sub.subviews.count > 0 && sub.subviews.count < 20) {
            if (duo_alignInteractionViews(sub, vcRoot, win, depth + 1)) alignedAny = YES;
        }
    }
    return alignedAny;
}

static void (*orig_playInteraction_viewDidLayoutSubviews)(UIViewController *self, SEL _cmd) = NULL;
static void duo_playInteraction_viewDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    if (orig_playInteraction_viewDidLayoutSubviews) {
        orig_playInteraction_viewDidLayoutSubviews(self, _cmd);
    }
    UIView *v = self.view;
    UIWindow *win = v ? v.window : nil;
    if (!win) return;

    // Fast-path cache: skip completely if already aligned for this exact window size!
    CGSize curSize = win.bounds.size;
    NSValue *lastVal = objc_getAssociatedObject(self, kDuoLastAlignedSizeKey);
    if (lastVal) {
        CGSize lastSize = [lastVal CGSizeValue];
        if (fabs(lastSize.width - curSize.width) < 1.0 && fabs(lastSize.height - curSize.height) < 1.0) {
            return;
        }
    }

    if (duo_alignInteractionViews(v, v, win, 0)) {
        objc_setAssociatedObject(self, kDuoLastAlignedSizeKey, [NSValue valueWithCGSize:curSize], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_vc_viewDidAppear)(UIViewController *self, SEL _cmd, BOOL animated) = NULL;
static void duo_vc_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_vc_viewDidAppear) {
        orig_vc_viewDidAppear(self, _cmd, animated);
    }
    // Reset alignment cache on appear so recycled cells align once for current screen size
    if (objc_getAssociatedObject(self, kDuoLastAlignedSizeKey)) {
        objc_setAssociatedObject(self, kDuoLastAlignedSizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SEL selRefreshVert = sel_registerName("setNeedsUpdateOfVerticalBarConfiguration");
    if ([self respondsToSelector:selRefreshVert]) {
        ((void (*)(id, SEL))objc_msgSend)(self, selRefreshVert);
    }
}

// ============================================================================
// Helper: Hook or add instance/class methods safely (Once only)
// ============================================================================
static void hookOrAddMethod(Class cls, SEL sel, IMP imp, const char *types, IMP *origOut) {
    if (!cls || !sel || !imp) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        IMP cur = method_getImplementation(m);
        if (cur == imp) return;
        if (origOut && *origOut == NULL) {
            *origOut = cur;
        }
        if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) {
            method_setImplementation(m, imp);
        }
    } else {
        class_addMethod(cls, sel, imp, types);
    }
}

static void applyAwemeCoreDeepAdaptation(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *padClasses = @[
            @"AWEPadModuleAdapter", @"AWEPadBizUIAdapter", @"AWEPadFullPageAdapter",
            @"AWEPadSplitScreenAdapter", @"AWEPadSplitScreenAdapterImpl",
            @"AWEPadTabBarControllerAdapter", @"AWEPadTabBarAdapter",
            @"AWEPadUIAdaptor", @"AWEPadUIAdaption", @"AWEPadLeftSideBarAdapter",
            @"AWEPadUserPageAdapter", @"AWEPadDetailTableAdapter", @"AWEPadPureModeAdapter",
            @"AWEDeviceManager", @"UIDevice"
        ];
        NSArray<NSString *> *isPadSelectors = @[
            @"isPad", @"isIPad", @"isIpad", @"isiPad", @"isPadDevice", @"isIPadDevice",
            @"awe_isIpad", @"btd_isPadDevice", @"iesll_isPadDevice", @"acc_isIPad",
            @"cj_isPad", @"deviceIsIpad", @"checkIsPad", @"htslive_isiPad",
            @"puzzle_isiPad", @"sc_isPadDevice", @"isPadUI", @"isPadSplitScreen",
            @"isPadSplit", @"isPadSplitStyle", @"isPadLayout", @"isPadAdaptionMode",
            @"isInSplitScreen"
        ];
        for (NSString *clsName in padClasses) {
            Class cls = NSClassFromString(clsName);
            if (!cls) continue;
            Class metaCls = object_getClass(cls);
            for (NSString *selName in isPadSelectors) {
                SEL sel = sel_registerName(selName.UTF8String);
                if (class_getInstanceMethod(cls, sel)) {
                    hookOrAddMethod(cls, sel, (IMP)duo_returnNO, "B@:", NULL);
                }
                if (metaCls && class_getInstanceMethod(metaCls, sel)) {
                    hookOrAddMethod(metaCls, sel, (IMP)duo_returnNO, "B@:", NULL);
                }
            }
        }

        Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
        if (aweTabBarCls) {
            hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
        }

        Class playInteractionVC = NSClassFromString(@"AWEPlayInteractionViewController");
        if (playInteractionVC) {
            hookOrAddMethod(playInteractionVC, @selector(viewDidLayoutSubviews), (IMP)duo_playInteraction_viewDidLayoutSubviews, "v@:", (IMP *)&orig_playInteraction_viewDidLayoutSubviews);
        }

        SEL selVertBehavior = sel_registerName("preferredVerticalBarBehavior");
        SEL selChildVert = sel_registerName("childForPreferredVerticalBarBehavior");
        NSArray<NSString *> *aweVCClasses = @[
            @"AWEBaseTabBarController",
            @"AWENormalModeTabBarController",
            @"AWEBasicModeTabBarController",
            @"AWETeenModeTabBarController"
        ];
        for (NSString *clsName in aweVCClasses) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                hookOrAddMethod(cls, selVertBehavior, (IMP)duo_preferredVerticalBarBehavior, "q@:", NULL);
                hookOrAddMethod(cls, selChildVert, (IMP)duo_childForPreferredVerticalBarBehavior, "@@:", NULL);
            }
        }
    });
}

__attribute__((constructor))
static void duo_adapt_init(void) {
    @autoreleasepool {
        SEL selVertBehavior = sel_registerName("preferredVerticalBarBehavior");
        SEL selChildVert = sel_registerName("childForPreferredVerticalBarBehavior");
        NSArray<NSString *> *baseVCs = @[
            @"UIViewController",
            @"UINavigationController",
            @"UITabBarController"
        ];
        for (NSString *clsName in baseVCs) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                hookOrAddMethod(cls, selVertBehavior, (IMP)duo_preferredVerticalBarBehavior, "q@:", NULL);
                hookOrAddMethod(cls, selChildVert, (IMP)duo_childForPreferredVerticalBarBehavior, "@@:", NULL);
            }
        }
        hookOrAddMethod([UIViewController class], @selector(viewDidAppear:), (IMP)duo_vc_viewDidAppear, "v@:B", (IMP *)&orig_vc_viewDidAppear);

        Class tabVCCls = [UITabBarController class];
        if (tabVCCls) {
            hookOrAddMethod(tabVCCls, sel_registerName("mode"), (IMP)duo_tabBarControllerMode, "q@:", NULL);
            hookOrAddMethod(tabVCCls, sel_registerName("setMode:"), (IMP)duo_setTabBarControllerMode, "v@:q", NULL);
        }

        hookOrAddMethod([UIDevice class], @selector(userInterfaceIdiom), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        hookOrAddMethod([UITraitCollection class], @selector(userInterfaceIdiom), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        hookOrAddMethod([UITraitCollection class], @selector(horizontalSizeClass), (IMP)duo_horizontalSizeClass, "q@:", NULL);
        hookOrAddMethod([UITraitCollection class], @selector(verticalSizeClass), (IMP)duo_verticalSizeClass, "q@:", NULL);

        applyAwemeCoreDeepAdaptation();
    }
}
