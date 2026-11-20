// DuoAdapt.m - iPhone Duo (iOS 27.1) Deep UIKit Adaptation for Douyin
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 1. Force UIVerticalBarBehavior.disabled (1) on all UIViewControllers
// This completely suppresses the iOS 27.1 vertical side-bar on both Outer Display and Inner Landscape.
static NSInteger duo_preferredVerticalBarBehavior(id self, SEL _cmd) {
    return 1; // UIVerticalBarBehaviorDisabled
}

static id duo_childForPreferredVerticalBarBehavior(id self, SEL _cmd) {
    return nil; // Do not delegate to child VCs; enforce .disabled at container level
}

// 2. Force UITabBarController.mode = UITabBarControllerModeTabBar (1)
// Prevents iOS 18+ / 27.1 from turning the bottom TabBar into a top floating bar or sidebar.
static NSInteger duo_tabBarControllerMode(id self, SEL _cmd) {
    return 1; // UITabBarControllerModeTabBar
}

static void duo_setTabBarControllerMode(id self, SEL _cmd, NSInteger mode) {
    // Ignore attempts to switch to automatic (0) or tabSidebar (2)
}

// 3. Force UIDevice.userInterfaceIdiom to UIUserInterfaceIdiomPhone (0)
// Prevents Douyin from entering broken half-iPad mode when unfolded.
static NSInteger duo_userInterfaceIdiom(id self, SEL _cmd) {
    return 0; // UIUserInterfaceIdiomPhone
}

// 4. Force UITraitCollection.horizontalSizeClass to UIUserInterfaceSizeClassCompact (1)
// Keeps Douyin's feed, comments, and tab bar in standard iPhone layout on both screens.
static NSInteger duo_horizontalSizeClass(id self, SEL _cmd) {
    return 1; // UIUserInterfaceSizeClassCompact
}

static NSInteger duo_verticalSizeClass(id self, SEL _cmd) {
    return 2; // UIUserInterfaceSizeClassRegular
}

// 5. Dynamic Screen & Window Bounds Sync for AWENormalModeTabBar on Fold/Unfold
static void (*orig_tabBar_layoutSubviews)(UIView *self, SEL _cmd) = NULL;
static void duo_tabBar_layoutSubviews(UIView *self, SEL _cmd) {
    UIWindow *win = self.window;
    if (win) {
        CGRect winBounds = win.bounds;
        CGRect f = self.frame;
        if (f.size.height > 0 && f.size.height < 120) {
            CGFloat targetY = winBounds.size.height - f.size.height;
            if (fabs(f.origin.y - targetY) > 1.0 || fabs(f.size.width - winBounds.size.width) > 1.0 || f.origin.x != 0) {
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

__attribute__((constructor))
static void duo_adapt_init(void) {
    @autoreleasepool {
        // 1. Disable iOS 27.1 vertical side-bar globally
        SEL selVertBehavior = sel_registerName("preferredVerticalBarBehavior");
        SEL selChildVert = sel_registerName("childForPreferredVerticalBarBehavior");
        NSArray<NSString *> *vcClasses = @[
            @"UIViewController",
            @"UINavigationController",
            @"UITabBarController",
            @"AWEBaseTabBarController",
            @"AWENormalModeTabBarController"
        ];
        for (NSString *clsName in vcClasses) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                hookOrAddMethod(cls, selVertBehavior, (IMP)duo_preferredVerticalBarBehavior, "q@:", NULL);
                hookOrAddMethod(cls, selChildVert, (IMP)duo_childForPreferredVerticalBarBehavior, "@@:", NULL);
            }
        }

        // 2. Lock UITabBarController to bottom tab bar mode
        Class tabVCCls = NSClassFromString(@"UITabBarController");
        if (tabVCCls) {
            hookOrAddMethod(tabVCCls, sel_registerName("mode"), (IMP)duo_tabBarControllerMode, "q@:", NULL);
            hookOrAddMethod(tabVCCls, sel_registerName("setMode:"), (IMP)duo_setTabBarControllerMode, "v@:q", NULL);
        }

        // 3. Force Phone Idiom & Compact Horizontal Size Class
        Class deviceCls = NSClassFromString(@"UIDevice");
        if (deviceCls) {
            hookOrAddMethod(deviceCls, sel_registerName("userInterfaceIdiom"), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
        }
        Class traitCls = NSClassFromString(@"UITraitCollection");
        if (traitCls) {
            hookOrAddMethod(traitCls, sel_registerName("userInterfaceIdiom"), (IMP)duo_userInterfaceIdiom, "q@:", NULL);
            hookOrAddMethod(traitCls, sel_registerName("horizontalSizeClass"), (IMP)duo_horizontalSizeClass, "q@:", NULL);
            hookOrAddMethod(traitCls, sel_registerName("verticalSizeClass"), (IMP)duo_verticalSizeClass, "q@:", NULL);
        }

        // 4. Pin AWENormalModeTabBar & UITabBar to bottom and match current screen width on fold/unfold
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class aweTabBarCls = NSClassFromString(@"AWENormalModeTabBar");
            if (aweTabBarCls) {
                hookOrAddMethod(aweTabBarCls, @selector(layoutSubviews), (IMP)duo_tabBar_layoutSubviews, "v@:", (IMP *)&orig_tabBar_layoutSubviews);
                hookOrAddMethod(aweTabBarCls, @selector(setFrame:), (IMP)duo_tabBar_setFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", (IMP *)&orig_tabBar_setFrame);
            }
        });
    }
}
