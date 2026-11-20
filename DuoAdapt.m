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
// 4. Query iOS 27.1 Notification Bar / Occlusion Region Safe Bounds Dynamically
// ============================================================================
static CGRect duo_queryTopRightNotificationRect(UIView *view) {
    if (!view) return CGRectZero;
    UIWindow *win = view.window;
    UIView *refView = win ? (UIView *)win : view;
    CGFloat winW = refView.bounds.size.width;
    if (winW < 200) return CGRectZero;

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
                        if (r.origin.y < 80.0 && r.size.width > 20.0 && (r.origin.x + r.size.width) > winW * 0.55) {
                            return r;
                        }
                    }
                }
            }
        }
    }

    if (win && win.windowScene && win.windowScene.statusBarManager) {
        CGRect sbFrame = win.windowScene.statusBarManager.statusBarFrame;
        if (sbFrame.size.height > 0 && sbFrame.size.height < 90.0) {
            if (sbFrame.origin.x > winW * 0.5 && sbFrame.size.width > 20.0) {
                return sbFrame;
            }
            return CGRectMake(winW - 108.0, sbFrame.origin.y, 108.0, sbFrame.size.height);
        }
    }
    return CGRectZero;
}

// ============================================================================
// 5. One-Way setFrame: Input Adjustment (Zero layoutSubviews hook = Zero Freeze)
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

// ============================================================================
// 6. Safe Transform-Based Right Interaction Buttons Alignment (Never Freezes!)
// ============================================================================
// Modifying CGAffineTransform does NOT trigger AutoLayout or layoutSubviews recursion!
static void duo_alignRightStackWithTransform(UIView *rootView, UIWindow *win) {
    if (!rootView || !win) return;
    CGFloat winW = win.bounds.size.width;
    if (winW <= 500) {
        // Outer screen: reset any translation transform if present
        for (UIView *sub in rootView.subviews) {
            NSString *clsName = NSStringFromClass([sub class]);
            if ([clsName containsString:@"RightElement"] || [clsName isEqualToString:@"AWEElementStackView"]) {
                if (!CGAffineTransformIsIdentity(sub.transform)) {
                    sub.transform = CGAffineTransformIdentity;
                }
            }
            if (sub.subviews.count > 0 && sub.subviews.count < 25) {
                duo_alignRightStackWithTransform(sub, win);
            }
        }
        return;
    }

    for (UIView *sub in rootView.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        CGRect bounds = sub.bounds;
        // Identify the narrow vertical stack of right buttons (Avatar, Like, Comment, Favorite, Share)
        BOOL isRightTarget = ([clsName containsString:@"RightElementContainer"] ||
                              [clsName isEqualToString:@"AWEElementStackView"]);
        if (isRightTarget && bounds.size.width >= 36 && bounds.size.width <= 125 && bounds.size.height >= 180) {
            // Compute where this view actually sits on screen WITHOUT transform
            CGAffineTransform saved = sub.transform;
            sub.transform = CGAffineTransformIdentity;
            CGRect rectInWin = [sub convertRect:sub.bounds toView:win];
            CGFloat targetX = winW - rectInWin.size.width - 10.0;
            CGFloat dx = targetX - rectInWin.origin.x;
            if (dx > 40.0) {
                sub.transform = CGAffineTransformMakeTranslation(dx, 0);
            } else {
                sub.transform = saved;
            }
            continue;
        }
        if (sub.subviews.count > 0 && sub.subviews.count < 25) {
            duo_alignRightStackWithTransform(sub, win);
        }
    }
}

static void (*orig_playInteraction_viewDidAppear)(UIViewController *self, SEL _cmd, BOOL animated) = NULL;
static void duo_playInteraction_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_playInteraction_viewDidAppear) {
        orig_playInteraction_viewDidAppear(self, _cmd, animated);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.view && self.view.window) {
            duo_alignRightStackWithTransform(self.view, self.view.window);
        }
    });
}

static BOOL gInRightContainerSetFrame = NO;
static void (*orig_rightContainer_setFrame)(UIView *self, SEL _cmd, CGRect frame) = NULL;
static void duo_rightContainer_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    if (!gInRightContainerSetFrame) {
        gInRightContainerSetFrame = YES;
        UIWindow *win = self.window;
        if (win && win.bounds.size.width > 500 && frame.size.width >= 36 && frame.size.width <= 125 && frame.size.height >= 180) {
            // Check superview width; if superview is full width, push frame.origin.x directly
            UIView *sup = self.superview;
            if (sup && sup.bounds.size.width > 500) {
                CGFloat targetX = sup.bounds.size.width - frame.size.width - 10.0;
                if (frame.origin.x < targetX - 40.0) {
                    frame.origin.x = targetX;
                }
            }
        }
        gInRightContainerSetFrame = NO;
    }
    if (orig_rightContainer_setFrame) {
        orig_rightContainer_setFrame(self, _cmd, frame);
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
        // 1. Force AWEPad* & AWEFold* checks to return NO
        NSArray<NSString *> *padAndFoldClasses = @[
            @"AWEPadModuleAdapter", @"AWEPadBizUIAdapter", @"AWEPadFullPageAdapter",
            @"AWEPadSplitScreenAdapter", @"AWEPadSplitScreenAdapterImpl",
            @"AWEPadTabBarControllerAdapter", @"AWEPadTabBarAdapter",
            @"AWEPadUIAdaptor", @"AWEPadUIAdaption", @"AWEPadLeftSideBarAdapter",
            @"AWEPadUserPageAdapter", @"AWEPadDetailTableAdapter", @"AWEPadPureModeAdapter",
            @"AWEDeviceManager", @"UIDevice",
            @"AWEFoldDeviceDetector", @"AWEPlayInteractionFoldElementLayoutService",
            @"AWEPlayInteractionFoldRightElementLayout"
        ];
        NSArray<NSString *> *disableSelectors = @[
            @"isPad", @"isIPad", @"isIpad", @"isiPad", @"isPadDevice", @"isIPadDevice",
            @"awe_isIpad", @"btd_isPadDevice", @"iesll_isPadDevice", @"acc_isIPad",
            @"cj_isPad", @"deviceIsIpad", @"checkIsPad", @"htslive_isiPad",
            @"puzzle_isiPad", @"sc_isPadDevice", @"isPadUI", @"isPadSplitScreen",
            @"isPadSplit", @"isPadSplitStyle", @"isPadLayout", @"isPadAdaptionMode",
            @"isInSplitScreen", @"isFoldDevice", @"isFold", @"p_isFoldDevice",
            @"isDynamicFoldDevice", @"shouldUseFoldElementLayout", @"shouldUseFoldableLayout"
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

        // 2. Pin AWENormalModeTabBar to bottom via setFrame:
        Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
        if (aweTabBarCls) {
            hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
        }

        // 3. Adjust AWEFeedTopBarContainer via setFrame:
        Class topBarCls = NSClassFromString(@"AWEFeedTopBarContainer");
        if (topBarCls) {
            hookOrAddMethod(topBarCls, @selector(setFrame:), (IMP)duo_topBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_topBar_setFrame);
        }

        // 4. Pin Right Interaction Buttons safely via setFrame: + CGAffineTransform on viewDidAppear:
        Class rightContainerCls = NSClassFromString(@"AWEPlayInteractionRightElementContainer");
        if (rightContainerCls) {
            hookOrAddMethod(rightContainerCls, @selector(setFrame:), (IMP)duo_rightContainer_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_rightContainer_setFrame);
        }
        Class playInteractionVC = NSClassFromString(@"AWEPlayInteractionViewController");
        if (playInteractionVC) {
            hookOrAddMethod(playInteractionVC, @selector(viewDidAppear:), (IMP)duo_playInteraction_viewDidAppear, "v@:B", (IMP *)&orig_playInteraction_viewDidAppear);
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
