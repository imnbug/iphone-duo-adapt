// DuoAdapt.m - iPhone Duo (iOS 27.1) Safe & Non-Blocking UIKit Adaptation for Douyin
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
// 4. Native AWEFoldDeviceDetector Disabled (Keep Right Buttons at Right Edge!)
// ============================================================================
static NSArray *duo_emptyFoldDeviceModelList(id self, SEL _cmd) {
    return @[];
}

// ============================================================================
// 5. Query iOS 27.1 Notification Bar / Occlusion Region Safe Bounds Dynamically
// ============================================================================
// Queries iOS 27.1's UIViewReservedRegion (occlusionRegionKind) or statusBarFrame
// to find the exact bounding box of the top-right notification/status pill.
static CGRect duo_queryTopRightNotificationRect(UIView *view) {
    if (!view) return CGRectZero;
    UIWindow *win = view.window;
    UIView *refView = win ? (UIView *)win : view;
    CGFloat winW = refView.bounds.size.width;
    if (winW < 200) return CGRectZero;

    // 1. Try iOS 27.1 official UIViewReservedRegion API: [refView reservedRegionsOfKind:[UIViewReservedRegionKind occlusionRegionKind]]
    Class kindCls = NSClassFromString(@"UIViewReservedRegionKind");
    SEL selOccKind = sel_registerName("occlusionRegionKind");
    SEL selResRegions = sel_registerName("reservedRegionsOfKind:");
    if (kindCls && [kindCls respondsToSelector:selOccKind] && [refView respondsToSelector:selResRegions]) {
        id occKind = ((id (*)(id, SEL))objc_msgSend)(kindCls, selOccKind);
        if (occKind) {
            NSArray *regions = ((NSArray * (*)(id, SEL, id))objc_msgSend)(refView, selResRegions, occKind);
            if ([regions isKindOfClass:[NSArray class]]) {
                SEL selFrame = @selector(frame);
                for (id reg in regions) {
                    if ([reg respondsToSelector:selFrame]) {
                        CGRect r = ((CGRect (*)(id, SEL))objc_msgSend)(reg, selFrame);
                        // Check if this occlusion region is in the top-right corner
                        if (r.origin.y < 80.0 && r.size.width > 20.0 && (r.origin.x + r.size.width) > winW * 0.55) {
                            return r;
                        }
                    }
                }
            }
        }
    }

    // 2. Fallback: Query windowScene.statusBarManager.statusBarFrame
    if (win && win.windowScene && win.windowScene.statusBarManager) {
        CGRect sbFrame = win.windowScene.statusBarManager.statusBarFrame;
        if (sbFrame.size.height > 0 && sbFrame.size.height < 90.0) {
            // If statusBarFrame is a top-right pill, use its exact rect;
            // if it spans full width, the actual right status cluster occupies the rightmost ~106pt.
            if (sbFrame.origin.x > winW * 0.5 && sbFrame.size.width > 20.0) {
                return sbFrame;
            }
            return CGRectMake(winW - 106.0, sbFrame.origin.y, 106.0, sbFrame.size.height);
        }
    }
    return CGRectZero;
}

// ============================================================================
// 6. One-Way setFrame: Input Adjustment (Zero layoutSubviews hooks = Zero Freeze!)
// ============================================================================
static BOOL gInTopBarSetFrame = NO;
static void (*orig_topBar_setFrame)(UIView *self, SEL _cmd, CGRect frame) = NULL;
static void duo_topBar_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    if (!gInTopBarSetFrame) {
        gInTopBarSetFrame = YES;
        UIWindow *win = self.window;
        CGFloat winW = (win && win.bounds.size.width > 200) ? win.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
        CGRect notifRect = duo_queryTopRightNotificationRect(self);
        if (notifRect.size.width > 0 && notifRect.origin.x > 200) {
            CGFloat safeMaxWidth = notifRect.origin.x - 8.0;
            if (frame.origin.x <= 20.0 && frame.size.width > safeMaxWidth) {
                frame.size.width = safeMaxWidth - frame.origin.x;
            }
            // Align topBar vertically with the notification bar center if topBar is in the top zone
            if (frame.origin.y >= 0 && frame.origin.y < 90.0 && frame.size.height > 20.0 && frame.size.height < 80.0 && notifRect.size.height > 10.0) {
                CGFloat alignedY = notifRect.origin.y + (notifRect.size.height - frame.size.height) * 0.5;
                if (alignedY < 4.0) alignedY = 4.0;
                frame.origin.y = alignedY;
            }
        } else if (winW > 300 && frame.origin.x <= 20.0 && frame.size.width > winW - 108.0) {
            frame.size.width = (winW - 108.0) - frame.origin.x;
        }
        gInTopBarSetFrame = NO;
    }
    if (orig_topBar_setFrame) {
        orig_topBar_setFrame(self, _cmd, frame);
    }
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
        // 1. Force AWEPad* AND AWEFold* layout classes to return NO so Douyin never pushes
        // the right interaction buttons (Like/Comment/Favorite/Share) to the middle of the screen!
        NSArray<NSString *> *padAndFoldClasses = @[
            @"AWEPadModuleAdapter", @"AWEPadBizUIAdapter", @"AWEPadFullPageAdapter",
            @"AWEPadSplitScreenAdapter", @"AWEPadSplitScreenAdapterImpl",
            @"AWEPadTabBarControllerAdapter", @"AWEPadTabBarAdapter",
            @"AWEPadUIAdaptor", @"AWEPadUIAdaption", @"AWEPadLeftSideBarAdapter",
            @"AWEPadUserPageAdapter", @"AWEPadDetailTableAdapter", @"AWEPadPureModeAdapter",
            @"AWEDeviceManager", @"UIDevice",
            @"AWEFoldDeviceDetector", @"AWEPlayInteractionFoldElementLayoutService",
            @"AWEPlayInteractionFoldRightElementLayout", @"AWEPlayInteractionElementContainer",
            @"AWEPlayInteractionRightElementContainer", @"AWEPlayInteractionViewController",
            @"AWEDetailFoldAdaptUtil", @"AWEDCFeedPadFoldUtil"
        ];
        NSArray<NSString *> *disableSelectors = @[
            @"isPad", @"isIPad", @"isIpad", @"isiPad", @"isPadDevice", @"isIPadDevice",
            @"awe_isIpad", @"btd_isPadDevice", @"iesll_isPadDevice", @"acc_isIPad",
            @"cj_isPad", @"deviceIsIpad", @"checkIsPad", @"htslive_isiPad",
            @"puzzle_isiPad", @"sc_isPadDevice", @"isPadUI", @"isPadSplitScreen",
            @"isPadSplit", @"isPadSplitStyle", @"isPadLayout", @"isPadAdaptionMode",
            @"isInSplitScreen",
            @"isFoldDevice", @"isFold", @"p_isFoldDevice", @"isDynamicFoldDevice",
            @"shouldUseFoldElementLayout", @"shouldUseFoldableLayout",
            @"isPadOrFold", @"isPadOrFoldDevice", @"isPadOrFoldAdaptationEnabled",
            @"padOrFoldLayoutEnabled", @"shouldAdaptPadFoldLayout"
        ];
        for (NSString *clsName in padAndFoldClasses) {
            Class cls = NSClassFromString(clsName);
            if (!cls) continue;
            Class metaCls = object_getClass(cls);
            for (NSString *selName in disableSelectors) {
                SEL sel = sel_registerName(selName.UTF8String);
                if (class_getInstanceMethod(cls, sel)) {
                    hookOrAddMethod(cls, sel, (IMP)duo_returnNO, "B@:", NULL);
                }
                if (metaCls && class_getInstanceMethod(metaCls, sel)) {
                    hookOrAddMethod(metaCls, sel, (IMP)duo_returnNO, "B@:", NULL);
                }
            }
        }

        Class foldDetector = NSClassFromString(@"AWEFoldDeviceDetector");
        if (foldDetector) {
            Class metaFold = object_getClass(foldDetector);
            SEL listSel = sel_registerName("foldDeviceModelList");
            SEL defListSel = sel_registerName("defaultFoldDeviceModelList");
            if (class_getInstanceMethod(foldDetector, listSel)) {
                hookOrAddMethod(foldDetector, listSel, (IMP)duo_emptyFoldDeviceModelList, "@@:", NULL);
            }
            if (class_getInstanceMethod(foldDetector, defListSel)) {
                hookOrAddMethod(foldDetector, defListSel, (IMP)duo_emptyFoldDeviceModelList, "@@:", NULL);
            }
            if (metaFold && class_getInstanceMethod(metaFold, listSel)) {
                hookOrAddMethod(metaFold, listSel, (IMP)duo_emptyFoldDeviceModelList, "@@:", NULL);
            }
            if (metaFold && class_getInstanceMethod(metaFold, defListSel)) {
                hookOrAddMethod(metaFold, defListSel, (IMP)duo_emptyFoldDeviceModelList, "@@:", NULL);
            }
        }

        // 2. Pin AWENormalModeTabBar to bottom via setFrame: only
        Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
        if (aweTabBarCls) {
            hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
        }

        // 3. Adjust AWEFeedTopBarContainer via setFrame: only (using queried notification bar bounds, zero layoutSubviews loop!)
        Class topBarCls = NSClassFromString(@"AWEFeedTopBarContainer");
        if (topBarCls) {
            hookOrAddMethod(topBarCls, @selector(setFrame:), (IMP)duo_topBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_topBar_setFrame);
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
