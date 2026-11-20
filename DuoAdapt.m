// DuoAdapt.m - iPhone Duo (iOS 27.1) Full Native & UIKit Deep Adaptation for Douyin
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

static BOOL duo_returnYES(id self, SEL _cmd) {
    return YES;
}

// ============================================================================
// 4. Native AWEFoldDeviceDetector Model List
// ============================================================================
static NSArray *duo_foldDeviceModelList(id self, SEL _cmd) {
    return @[
        @"iPhone18,1", @"iPhone18,2", @"iPhone18,3", @"iPhone18,4", @"iPhone18,5",
        @"iPhone19,1", @"iPhone19,2", @"iPhone19,3", @"iPhone19,4", @"iPhone19,5",
        @"iPhone19,6", @"iPhone19,7", @"iPhone19,8", @"iPhone20,1", @"iPhone20,2",
        @"iPhone Duo"
    ];
}

// ============================================================================
// 5. Dynamic Screen Width & Right Interaction Buttons Pinning
// ============================================================================
static CGFloat duo_currentWindowWidth(UIView *view) {
    UIWindow *win = view.window;
    if (win && win.bounds.size.width > 100) {
        return win.bounds.size.width;
    }
    return [UIScreen mainScreen].bounds.size.width;
}

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

// Pin right interaction buttons (Avatar, Like, Comment, Favorite, Share, Mute) to right edge!
static void duo_pinRightViewsInContainer(UIView *rootView, CGFloat containerWidth) {
    if (!rootView || containerWidth < 300) return;
    for (UIView *sub in rootView.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        CGRect f = sub.frame;
        // Check if this is the right interaction stack/container (narrow width 40~110pt, stuck near center 250~550pt on a wide screen >600pt)
        BOOL isRightClass = ([clsName containsString:@"RightElement"] ||
                             [clsName containsString:@"RightContainer"] ||
                             [clsName isEqualToString:@"AWEElementContainer"] ||
                             [clsName isEqualToString:@"AWEElementStackView"]);
        if (containerWidth > 500 && f.size.width >= 36 && f.size.width <= 120 && f.size.height >= 180) {
            if (isRightClass || (f.origin.x > 240 && f.origin.x < containerWidth - f.size.width - 60)) {
                f.origin.x = containerWidth - f.size.width - 8.0;
                sub.frame = f;
            }
        }
        // Also expand full-width interaction overlay containers that were stuck at 375~430pt width
        if (containerWidth > 500 && f.origin.x == 0 && f.size.width >= 350 && f.size.width <= 460 && f.size.height > 300) {
            if ([clsName containsString:@"Interaction"] || [clsName containsString:@"Container"] || [clsName containsString:@"TableView"] || [clsName containsString:@"Cell"]) {
                f.size.width = containerWidth;
                sub.frame = f;
            }
        }
        if (sub.subviews.count > 0 && sub.subviews.count < 30) {
            duo_pinRightViewsInContainer(sub, containerWidth);
        }
    }
}

static void (*orig_playInteraction_viewDidLayoutSubviews)(UIViewController *self, SEL _cmd) = NULL;
static void duo_playInteraction_viewDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    if (orig_playInteraction_viewDidLayoutSubviews) {
        orig_playInteraction_viewDidLayoutSubviews(self, _cmd);
    }
    SEL selFoldUpdate = sel_registerName("awe_updateFoldElementLayoutIfViewSizeChanged");
    if ([self respondsToSelector:selFoldUpdate]) {
        ((void (*)(id, SEL))objc_msgSend)(self, selFoldUpdate);
    }
    SEL selFoldRightUpdate = sel_registerName("awe_updateFoldRightElementLayoutIfNeeded");
    if ([self respondsToSelector:selFoldRightUpdate]) {
        ((void (*)(id, SEL))objc_msgSend)(self, selFoldRightUpdate);
    }
    UIView *v = self.view;
    if (v) {
        CGFloat w = duo_currentWindowWidth(v);
        if (w > 300 && fabs(v.frame.size.width - w) > 1.0) {
            CGRect vf = v.frame;
            vf.size.width = w;
            v.frame = vf;
        }
        duo_pinRightViewsInContainer(v, w);
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
        // 1. Force AWEPad* classes to return NO for isPad / isPadUI / isPadSplitScreen checks
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

        // 2. Enable AWEFoldDeviceDetector
        Class foldDetector = NSClassFromString(@"AWEFoldDeviceDetector");
        if (foldDetector) {
            Class metaFold = object_getClass(foldDetector);
            NSArray<NSString *> *foldSels = @[@"isFoldDevice", @"isFold", @"p_isFoldDevice", @"isDynamicFoldDevice"];
            for (NSString *s in foldSels) {
                SEL sel = sel_registerName(s.UTF8String);
                if (class_getInstanceMethod(foldDetector, sel)) {
                    hookOrAddMethod(foldDetector, sel, (IMP)duo_returnYES, "B@:", NULL);
                }
                if (metaFold && class_getInstanceMethod(metaFold, sel)) {
                    hookOrAddMethod(metaFold, sel, (IMP)duo_returnYES, "B@:", NULL);
                }
            }
            SEL listSel = sel_registerName("foldDeviceModelList");
            SEL defListSel = sel_registerName("defaultFoldDeviceModelList");
            if (class_getInstanceMethod(foldDetector, listSel)) {
                hookOrAddMethod(foldDetector, listSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
            }
            if (class_getInstanceMethod(foldDetector, defListSel)) {
                hookOrAddMethod(foldDetector, defListSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
            }
            if (metaFold && class_getInstanceMethod(metaFold, listSel)) {
                hookOrAddMethod(metaFold, listSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
            }
            if (metaFold && class_getInstanceMethod(metaFold, defListSel)) {
                hookOrAddMethod(metaFold, defListSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
            }
        }

        // 3. Pin AWENormalModeTabBar to bottom and auto-resize across outer/inner display
        Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
        if (aweTabBarCls) {
            hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
        }

        // 4. Pin Right Interaction Buttons (Like, Comment, Favorite, Share) to the right edge of current screen
        Class playInteractionVC = NSClassFromString(@"AWEPlayInteractionViewController");
        if (playInteractionVC) {
            hookOrAddMethod(playInteractionVC, @selector(viewDidLayoutSubviews), (IMP)duo_playInteraction_viewDidLayoutSubviews, "v@:", (IMP *)&orig_playInteraction_viewDidLayoutSubviews);
        }

        // 5. Disable vertical bar on all AWE TabBar/Navigation subclasses
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
        // 0. Ensure LoadControl never disables DuoAdapt.dylib
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:YES forKey:@"LoadControl.Plugin.DuoAdapt.dylib"];
        [ud removeObjectForKey:@"LC_AutoDisabledCulprit"];

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
