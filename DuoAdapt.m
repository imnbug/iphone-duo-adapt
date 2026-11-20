// DuoAdapt.m - iPhone Duo (iOS 27.1) Safe Transform-Based UIKit Adaptation for Douyin
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
// 5. Safe Transform-Only Right Interaction Buttons Alignment (ZERO layout loop!)
// ============================================================================
// IMPORTANT: Modifying `transform` NEVER triggers AutoLayout or layoutSubviews recursion!
// We ONLY touch `sub.transform`, never `sub.frame` or `sub.bounds`.
static void duo_pushRightButtonsToEdge(UIView *rootView, UIWindow *win, int depth) {
    if (!rootView || !win || depth > 6) return;
    CGFloat winW = win.bounds.size.width;
    if (winW <= 480.0) {
        // On outer compact screen: reset transform if we applied one earlier
        for (UIView *sub in rootView.subviews) {
            if (sub.tag == 271001) {
                sub.transform = CGAffineTransformIdentity;
                sub.tag = 0;
            }
            if (sub.subviews.count > 0 && sub.subviews.count < 25) {
                duo_pushRightButtonsToEdge(sub, win, depth + 1);
            }
        }
        return;
    }

    for (UIView *sub in rootView.subviews) {
        CGRect b = sub.bounds;
        NSString *clsName = NSStringFromClass([sub class]);
        BOOL isCandidate = (b.size.width >= 36.0 && b.size.width <= 130.0 && b.size.height >= 160.0) &&
                           ([clsName containsString:@"RightElement"] ||
                            [clsName containsString:@"RightContainer"] ||
                            [clsName isEqualToString:@"AWEElementStackView"] ||
                            [clsName isEqualToString:@"AWEElementContainer"]);
        if (isCandidate) {
            // Calculate untransformed position in window coordinates
            CGAffineTransform prev = sub.transform;
            if (!CGAffineTransformIsIdentity(prev)) {
                sub.transform = CGAffineTransformIdentity;
            }
            CGRect rectInWin = [sub convertRect:b toView:win];
            CGFloat desiredX = winW - rectInWin.size.width - 12.0;
            CGFloat dx = desiredX - rectInWin.origin.x;
            if (dx > 25.0) {
                sub.transform = CGAffineTransformMakeTranslation(dx, 0);
                sub.tag = 271001;
            } else {
                sub.transform = CGAffineTransformIdentity;
                if (sub.tag == 271001) sub.tag = 0;
            }
            continue;
        }
        if (sub.subviews.count > 0 && sub.subviews.count < 25) {
            duo_pushRightButtonsToEdge(sub, win, depth + 1);
        }
    }
}

static void (*orig_playInteraction_viewDidLayoutSubviews)(UIViewController *self, SEL _cmd) = NULL;
static void duo_playInteraction_viewDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    if (orig_playInteraction_viewDidLayoutSubviews) {
        orig_playInteraction_viewDidLayoutSubviews(self, _cmd);
    }
    UIView *v = self.view;
    if (v && v.window) {
        duo_pushRightButtonsToEdge(v, v.window, 0);
    }
}

static void (*orig_vc_viewDidAppear)(UIViewController *self, SEL _cmd, BOOL animated) = NULL;
static void duo_vc_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_vc_viewDidAppear) {
        orig_vc_viewDidAppear(self, _cmd, animated);
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
        // 1. Force AWEPad* classes to return NO (keep native AWEFoldDeviceDetector untouched!)
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

        // 2. Pin AWENormalModeTabBar to bottom via setFrame:
        Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
        if (aweTabBarCls) {
            hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
        }

        // 3. Push Right Interaction Buttons to right edge using safe CGAffineTransform in viewDidLayoutSubviews
        Class playInteractionVC = NSClassFromString(@"AWEPlayInteractionViewController");
        if (playInteractionVC) {
            hookOrAddMethod(playInteractionVC, @selector(viewDidLayoutSubviews), (IMP)duo_playInteraction_viewDidLayoutSubviews, "v@:", (IMP *)&orig_playInteraction_viewDidLayoutSubviews);
        }

        // 4. Disable vertical bar on all AWE TabBar/Navigation subclasses
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
        // 1. Globally disable iOS 27.1 vertical side-bar on UIKit base classes
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

        // 2. Lock UITabBarController to standard bottom tabBar mode
        Class tabVCCls = [UITabBarController class];
        if (tabVCCls) {
            hookOrAddMethod(tabVCCls, sel_registerName("mode"), (IMP)duo_tabBarControllerMode, "q@:", NULL);
            hookOrAddMethod(tabVCCls, sel_registerName("setMode:"), (IMP)duo_setTabBarControllerMode, "v@:q", NULL);
        }

        // 3. Force Phone Idiom & Compact Horizontal Size Class
        hookOrAddMethod([UIDevice class], @selector(userInterfaceIdiom), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        hookOrAddMethod([UITraitCollection class], @selector(userInterfaceIdiom), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        hookOrAddMethod([UITraitCollection class], @selector(horizontalSizeClass), (IMP)duo_horizontalSizeClass, "q@:", NULL);
        hookOrAddMethod([UITraitCollection class], @selector(verticalSizeClass), (IMP)duo_verticalSizeClass, "q@:", NULL);

        // 4. Apply AwemeCore deep adaptation once on launch
        applyAwemeCoreDeepAdaptation();
    }
}
