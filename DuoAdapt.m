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
// 4. Native AWEFoldDeviceDetector & iPhone Duo Adaptation Enabling
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
// 5. Dynamic Fold/Unfold Window & TabBar Relayout Observer
// ============================================================================
static void (*orig_tabBar_layoutSubviews)(UIView *self, SEL _cmd) = NULL;
static void duo_tabBar_layoutSubviews(UIView *self, SEL _cmd) {
    UIWindow *win = self.window;
    if (win) {
        CGRect winBounds = win.bounds;
        CGRect f = self.frame;
        if (f.size.height > 0 && f.size.height < 120 && winBounds.size.height > 200) {
            CGFloat targetY = winBounds.size.height - f.size.height;
            if (fabs(f.origin.y - targetY) > 0.5 || fabs(f.size.width - winBounds.size.width) > 0.5 || f.origin.x != 0) {
                f.origin.x = 0;
                f.origin.y = targetY;
                f.size.width = winBounds.size.width;
                self.frame = f;
            }
        }
    }
    if (orig_tabBar_layoutSubviews) {
        orig_tabBar_layoutSubviews(self, _cmd);
    }
}

static void (*orig_tabBar_setFrame)(UIView *self, SEL _cmd, CGRect frame) = NULL;
static void duo_tabBar_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    UIWindow *win = self.window;
    if (win) {
        CGRect winBounds = win.bounds;
        if (frame.size.height > 0 && frame.size.height < 120 && winBounds.size.height > 200) {
            frame.origin.x = 0;
            frame.origin.y = winBounds.size.height - frame.size.height;
            frame.size.width = winBounds.size.width;
        }
    }
    if (orig_tabBar_setFrame) {
        orig_tabBar_setFrame(self, _cmd, frame);
    }
}

static void duo_relayoutViewHierarchy(UIView *view, CGRect winBounds) {
    if (!view) return;
    NSString *clsName = NSStringFromClass([view class]);
    if ([clsName isEqualToString:@"AWENormalModeTabBar"] || [view isKindOfClass:[UITabBar class]]) {
        CGRect f = view.frame;
        if (f.size.height > 0 && f.size.height < 120) {
            f.origin.x = 0;
            f.origin.y = winBounds.size.height - f.size.height;
            f.size.width = winBounds.size.width;
            view.frame = f;
        }
    }
    [view setNeedsLayout];
    for (UIView *sub in view.subviews) {
        if (sub.subviews.count > 0) {
            duo_relayoutViewHierarchy(sub, winBounds);
        }
    }
}

static void (*orig_window_setFrame)(UIWindow *self, SEL _cmd, CGRect frame) = NULL;
static void duo_window_setFrame(UIWindow *self, SEL _cmd, CGRect frame) {
    CGRect oldBounds = self.bounds;
    if (orig_window_setFrame) {
        orig_window_setFrame(self, _cmd, frame);
    }
    if (!CGSizeEqualToSize(oldBounds.size, frame.size)) {
        SEL selRefreshVert = sel_registerName("setNeedsUpdateOfVerticalBarConfiguration");
        if (self.rootViewController && [self.rootViewController respondsToSelector:selRefreshVert]) {
            ((void (*)(id, SEL))objc_msgSend)(self.rootViewController, selRefreshVert);
        }
        duo_relayoutViewHierarchy(self, self.bounds);
    }
}

static void (*orig_window_layoutSubviews)(UIWindow *self, SEL _cmd) = NULL;
static void duo_window_layoutSubviews(UIWindow *self, SEL _cmd) {
    if (orig_window_layoutSubviews) {
        orig_window_layoutSubviews(self, _cmd);
    }
    SEL selRefreshVert = sel_registerName("setNeedsUpdateOfVerticalBarConfiguration");
    if (self.rootViewController && [self.rootViewController respondsToSelector:selRefreshVert]) {
        ((void (*)(id, SEL))objc_msgSend)(self.rootViewController, selRefreshVert);
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
// Helper: Hook or add instance/class methods safely
// ============================================================================
static void hookOrAddMethod(Class cls, SEL sel, IMP imp, const char *types, IMP *origOut) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        if (origOut) *origOut = method_getImplementation(m);
        if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) {
            method_setImplementation(m, imp);
        }
    } else {
        class_addMethod(cls, sel, imp, types);
    }
}

static void hookAllMethodsMatching(Class cls, BOOL (^predicate)(NSString *selName), IMP imp) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL s = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(s);
        const char *enc = method_getTypeEncoding(methods[i]);
        if (enc && (enc[0] == 'B' || enc[0] == 'c') && predicate(name)) {
            method_setImplementation(methods[i], imp);
        }
    }
    if (methods) free(methods);
}

static void applyAwemeCoreDeepAdaptation(void) {
    // 1. Force all AWEPad* classes to return NO for isPad / isPadUI / isPadSplitScreen checks
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

    // 2. Enable AWEFoldDeviceDetector & Native iPhone Duo Adaptation switches
    Class foldDetector = NSClassFromString(@"AWEFoldDeviceDetector");
    if (foldDetector) {
        Class metaFold = object_getClass(foldDetector);
        NSArray<NSString *> *foldSels = @[@"isFoldDevice", @"isFold", @"p_isFoldDevice", @"isDynamicFoldDevice"];
        for (NSString *s in foldSels) {
            SEL sel = sel_registerName(s.UTF8String);
            hookOrAddMethod(foldDetector, sel, (IMP)duo_returnYES, "B@:", NULL);
            if (metaFold) hookOrAddMethod(metaFold, sel, (IMP)duo_returnYES, "B@:", NULL);
        }
        SEL listSel = sel_registerName("foldDeviceModelList");
        SEL defListSel = sel_registerName("defaultFoldDeviceModelList");
        hookOrAddMethod(foldDetector, listSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
        hookOrAddMethod(foldDetector, defListSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
        if (metaFold) {
            hookOrAddMethod(metaFold, listSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
            hookOrAddMethod(metaFold, defListSel, (IMP)duo_foldDeviceModelList, "@@:", NULL);
        }
    }

    // 3. Pin AWENormalModeTabBar to bottom and auto-resize across outer/inner display
    Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
    if (aweTabBarCls) {
        hookOrAddMethod(aweTabBarCls, @selector(layoutSubviews), (IMP)duo_tabBar_layoutSubviews, "v@:", (IMP *)&orig_tabBar_layoutSubviews);
        hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
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

        // 4. Hook UIWindow frame/layout changes to dynamically adapt when folding/unfolding
        hookOrAddMethod([UIWindow class], @selector(setFrame:), (IMP)duo_window_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_window_setFrame);
        hookOrAddMethod([UIWindow class], @selector(layoutSubviews), (IMP)duo_window_layoutSubviews, "v@:", (IMP *)&orig_window_layoutSubviews);

        // 5. Apply AwemeCore deep adaptation immediately and on main queue launch
        applyAwemeCoreDeepAdaptation();
        dispatch_async(dispatch_get_main_queue(), ^{
            applyAwemeCoreDeepAdaptation();
        });
    }
}
