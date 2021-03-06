//
//  CCLoader.xm
//  CCLoader
//
//  Created by Jonas Gessner on 04.01.2014.
//  Copyright (c) 2014 Jonas Gessner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <substrate.h>
#import <objc/runtime.h>

#import "CCLoaderSettings/CCSection-Protocol.h"
#import "CCLoaderSettings/BBWeeAppController-Protocol.h"
#import "CCLoaderSettings/SpringBoardUIServices/_SBUIWidgetViewController.h"


#import "CCLoaderSettings/CCBundleLoader.h"
#import "CCSectionViewController.h"
#import "CCScrollView.h"

#import "ControlCenter/SBControlCenterController.h"
#import "ControlCenter/SBControlCenterViewController.h"
#import "ControlCenter/SBControlCenterContainerView.h"
#import "ControlCenter/SBControlCenterContentContainerView.h"
#import "ControlCenter/SBControlCenterContentView.h"
#import "ControlCenter/SBControlCenterSeparatorView.h"

#import "SBMediaController.h"

#define kCCLoaderSettingsPath [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"Preferences/de.j-gessner.ccloader.plist"]

#define iPad (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)

#define kCCGrabberHeight 25.0f
#define kCCSeparatorHeight 1.5f

static NSMutableDictionary *customSectionViewControllers = nil;

static NSMutableArray *sectionViewControllers = nil;
static NSMutableArray *strippedSectionViewControllers = nil;

static NSMutableArray *landscapeSectionViewControllers = nil;
static NSMutableArray *landscapeStrippedSectionViewControllers = nil;


static BOOL hideMediaControlsInCurrentSession = NO;

static BOOL landscape = NO;

static BOOL contentHeightIsSet = NO;
static CGFloat contentHeight = 0.0f;

static BOOL loadedSections = NO;

static CGFloat realHeight = 0.0f;
static CGFloat fakeHeight = 0.0f;

static BOOL visible = NO;

static CCScrollView *_scroller = nil;

NS_INLINE UIScrollView *scroller(void) {
    if (!_scroller) {
        _scroller = [[CCScrollView alloc] init];
        _scroller.scrollsToTop = NO;
    }
    
    return _scroller;
}

#pragma mark - Helper Functions

NS_INLINE SBControlCenterSectionViewController *stockSectionViewControllerForID(SBControlCenterContentView *contentView, NSString *sectionID) {
    if ([sectionID isEqualToString:@"com.apple.controlcenter.settings"]) {
        return (SBControlCenterSectionViewController *)contentView.settingsSection;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.brightness"]) {
        return (SBControlCenterSectionViewController *)contentView.brightnessSection;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.media-controls"]) {
        return (SBControlCenterSectionViewController *)contentView.mediaControlsSection;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.air-stuff"]) {
        return (SBControlCenterSectionViewController *)contentView.airplaySection;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.quick-launch"]) {
        return (SBControlCenterSectionViewController *)contentView.quickLaunchSection;
    }
    else {
        return nil;
    }
}

NS_INLINE void setStockSectionViewControllerForID(SBControlCenterContentView *contentView, NSString *sectionID, id value) {
    if ([sectionID isEqualToString:@"com.apple.controlcenter.settings"]) {
        contentView.settingsSection = value;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.brightness"]) {
        contentView.brightnessSection = value;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.media-controls"]) {
        contentView.mediaControlsSection = value;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.air-stuff"]) {
        contentView.airplaySection = value;
    }
    else if ([sectionID isEqualToString:@"com.apple.controlcenter.quick-launch"]) {
        contentView.quickLaunchSection = value;
    }
}

NS_INLINE BOOL checkBundleForType(NSBundle *bundle, CCBundleType type) {
    if (type == CCBundleTypeDefault) {
        Class principalClass = [bundle principalClass];
        
        return [principalClass conformsToProtocol:@protocol(CCSection)];
    }
    else if (type == CCBundleTypeBBWeeApp) {
        Class principalClass = [bundle principalClass];
        
        return [principalClass conformsToProtocol:@protocol(BBWeeAppController)];
    }
    else if (type == CCBundleTypeWeeApp) {
        NSDictionary *iOS7Info = [bundle objectForInfoDictionaryKey:@"SBUIWidgetViewControllers"];
        
        Class principalClass = [bundle classNamed:[iOS7Info.allValues lastObject]];
        
        return [principalClass isSubclassOfClass:[_SBUIWidgetViewController class]];
        
    }
    
    return NO;
}

NS_INLINE NSMutableArray *sectionViewControllersForIDs(NSArray *IDs, NSDictionary *replacements, SBControlCenterViewController *viewController, SBControlCenterContentView *contentView, NSUInteger *mediaControlsIndex, BOOL cleanUnusedSections) {
    CCBundleLoader *loader = [CCBundleLoader sharedInstance];
    
    NSMutableArray *_sectionViewControllers = [[NSMutableArray alloc] initWithCapacity:IDs.count];
    
    NSSet *stockLayout = kCCLoaderStockSections;
    
    NSMutableSet *bundles = loader.bundles.mutableCopy;
    
    NSMutableSet *NCBundles = loader.NCBundles.mutableCopy;
    
    NSMutableSet *oldNCBundles = loader.oldNCBundles.mutableCopy;
    
    NSDictionary *replacingBundles = loader.replacingBundles;
    
    if (!customSectionViewControllers) {
        customSectionViewControllers = [[NSMutableDictionary alloc] init];
    }
    
    NSMutableSet *usedCustomSections = (cleanUnusedSections ? [NSMutableSet setWithArray:customSectionViewControllers.allKeys] : nil);
    
    CCSectionViewController *(^loadCustomSection)(NSString *sectionIdentifier, NSBundle *loadingBundle, CCBundleType type) = ^CCSectionViewController * (NSString *sectionIdentifier, NSBundle *loadingBundle, CCBundleType type) {
        if (!checkBundleForType(loadingBundle, type)) {
            [loadingBundle unload];
            
            return nil;
        }
        else {
            CCSectionViewController *sectionViewController = customSectionViewControllers[sectionIdentifier];
            
            if (!sectionViewController) {
                sectionViewController = [[%c(CCSectionViewController) alloc] initWithCCLoaderBundle:loadingBundle type:type];
                [sectionViewController setDelegate:viewController];
                
                customSectionViewControllers[sectionIdentifier] = sectionViewController;
                
                [sectionViewController release];
            }
            
            if (cleanUnusedSections) {
                [usedCustomSections removeObject:sectionIdentifier];
            }
            
            [_sectionViewControllers addObject:sectionViewController];
            
            [bundles removeObject:loadingBundle];
            
            return sectionViewController;
        }
    };
    
    for (NSString *sectionID in IDs) {
        if ([stockLayout containsObject:sectionID]) {
            if ([sectionID isEqualToString:@"com.apple.controlcenter.media-controls"]) {
                if (mediaControlsIndex) {
                    *mediaControlsIndex = _sectionViewControllers.count;
                }
            }
            
            NSBundle *replacingBundle = nil;
            
            
            NSString *replacingID = replacements[sectionID];
            
            if ([replacingID isEqualToString:@"de.j-gessner.ccloader.reserved.defaultStockSection"]) {
                [_sectionViewControllers addObject:stockSectionViewControllerForID(contentView, sectionID)];
            }
            else {
                if (replacingID) {
                    for (NSBundle *bundle in replacingBundles[sectionID]) {
                        if ([bundle.bundleIdentifier isEqualToString:replacingID]) {
                            replacingBundle = bundle;
                            break;
                        }
                    }
                }
                
                if (replacingBundle) {
                    CCSectionViewController *section = loadCustomSection(replacingID, replacingBundle, CCBundleTypeDefault);
                    
                    [section _CCLoader_setReplacingSectionViewController:stockSectionViewControllerForID(contentView, sectionID)];
                }
                else {
                    [_sectionViewControllers addObject:stockSectionViewControllerForID(contentView, sectionID)];
                }
            }
        }
        else {
            BOOL added = NO;
            
            for (NSBundle *bundle in bundles) {
                if ([bundle.bundleIdentifier isEqualToString:sectionID]) {
                    loadCustomSection(sectionID, bundle, CCBundleTypeDefault);
                    added = YES;
                    break;
                }
            }
            
            if (!added) {
                for (NSBundle *bundle in NCBundles) {
                    if ([bundle.bundleIdentifier isEqualToString:sectionID]) {
                        loadCustomSection(sectionID, bundle, CCBundleTypeWeeApp);
                        added = YES;
                        break;
                    }
                }
                
                if (!added) {
                    for (NSBundle *bundle in oldNCBundles) {
                        if ([bundle.bundleIdentifier isEqualToString:sectionID]) {
                            loadCustomSection(sectionID, bundle, CCBundleTypeBBWeeApp);
                            added = YES;
                            break;
                        }
                    }
                }
            }
        }
    }
    
    [bundles release];
    [NCBundles release];
    [oldNCBundles release];
    
    if (cleanUnusedSections) {
        for (NSString *unusedSection in usedCustomSections) {
            [customSectionViewControllers removeObjectForKey:unusedSection];
        }
    }
    
    if (!customSectionViewControllers.count) {
        [customSectionViewControllers release];
        customSectionViewControllers = nil;
    }
    
    return _sectionViewControllers;
}

NS_INLINE void loadCCSections(SBControlCenterViewController *viewController, SBControlCenterContentView *contentView) {
    NSCParameterAssert(contentView);
    NSCParameterAssert(viewController);
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kCCLoaderSettingsPath];
    
    NSArray *sectionsToLoad = (iPad ? kCCLoaderStockOrderedSections : prefs[@"EnabledSections"]);
    
    NSDictionary *replacements = prefs[@"ReplacingBundles"];
    
    if (!sectionsToLoad) {
        sectionsToLoad = kCCLoaderStockOrderedSections;
    }
    
    NSMutableOrderedSet *landscapeSectionsToLoad = [NSMutableOrderedSet orderedSetWithArray:sectionsToLoad];
    
    [landscapeSectionsToLoad removeObject:@"com.apple.controlcenter.settings"];
    [landscapeSectionsToLoad removeObject:@"com.apple.controlcenter.quick-launch"];
    
    [landscapeSectionsToLoad insertObject:@"com.apple.controlcenter.settings" atIndex:0];
    [landscapeSectionsToLoad insertObject:@"com.apple.controlcenter.quick-launch" atIndex:landscapeSectionsToLoad.count];
    
    BOOL hideMediaControlsIfStopped = [prefs[@"HideMediaControls"] boolValue];
    BOOL hideSeparators = [prefs[@"HideSeparators"] boolValue];
    
    
    NSUInteger mediaControlsIndex = NSNotFound;
    NSUInteger landscapeMediaControlsIndex = NSNotFound;
    
    //Remove current section view controllers
    for (SBControlCenterSectionViewController *sectionViewController in landscapeSectionViewControllers) {
        [contentView _removeSectionController:sectionViewController];
    }
    
    [sectionViewControllers release];
    sectionViewControllers = nil;
    
    [landscapeStrippedSectionViewControllers release];
    landscapeStrippedSectionViewControllers = nil;
    
    sectionViewControllers = sectionViewControllersForIDs(sectionsToLoad, replacements, viewController, contentView, &mediaControlsIndex, NO);
    
    landscapeSectionViewControllers = sectionViewControllersForIDs(landscapeSectionsToLoad.array, replacements, viewController, contentView, &landscapeMediaControlsIndex, YES);
    
    
    [landscapeStrippedSectionViewControllers release];
    landscapeStrippedSectionViewControllers = nil;
    
    [strippedSectionViewControllers release];
    strippedSectionViewControllers = nil;
    
    if (hideMediaControlsIfStopped) {
        if (mediaControlsIndex != NSNotFound) {
            strippedSectionViewControllers = sectionViewControllers.mutableCopy;
            [strippedSectionViewControllers removeObjectAtIndex:mediaControlsIndex];
        }
        
        if (landscapeMediaControlsIndex != NSNotFound) {
            landscapeStrippedSectionViewControllers = landscapeSectionViewControllers.mutableCopy;
            [landscapeStrippedSectionViewControllers removeObjectAtIndex:landscapeMediaControlsIndex];
        }
    }
    
    NSMutableArray *separators = MSHookIvar<NSMutableArray *>(contentView, "_dividerViews");
    
    NSUInteger expectedCount = landscapeSectionViewControllers.count;
    
    if (expectedCount > 1 && !hideSeparators) {
        while (separators.count > expectedCount-1) {
            SBControlCenterSeparatorView *separator = [separators lastObject];
            
            [separator removeFromSuperview];
            [separators removeLastObject];
        }
        
        while (separators.count < expectedCount-1) {
            SBControlCenterSeparatorView *separator = [[%c(SBControlCenterSeparatorView) alloc] initWithFrame:CGRectZero];
            
            [contentView addSubview:separator];
            
            [separators addObject:separator];
        }
    }
    else {
        for (SBControlCenterSeparatorView *separator in separators) {
            [separator removeFromSuperview];
        }
        
        [separators removeAllObjects];
    }
}

NS_INLINE void reloadCCSections(void) {
    SBControlCenterController *controller = [%c(SBControlCenterController) sharedInstanceIfExists];
    
    NSCParameterAssert(controller);
    
    SBControlCenterViewController *viewController = MSHookIvar<SBControlCenterViewController *>(controller, "_viewController");
    
    SBControlCenterContentView *contentView = MSHookIvar<SBControlCenterContentView *>(viewController, "_contentView");
    
    loadCCSections(viewController, contentView);
}


#define TIME_MEASURE_START(i) CFTimeInterval start##i = CFAbsoluteTimeGetCurrent()
#define TIME_MEASURE_END(i) NSLog(@"ELAPSED TIME (%i) %f", i, CFAbsoluteTimeGetCurrent()-start##i)

#pragma mark - Swizzles

%group main

%hook SBControlCenterContentView

- (void)layoutSubviews {
    if (scroller().superview != self) {
        [self addSubview:scroller()];
    }
    
    
    CGRect frame = self.bounds;
    
    frame.origin.y = kCCGrabberHeight;
    frame.size.height = fakeHeight-kCCGrabberHeight;
    scroller().frame = frame;
    
    frame.size.height = realHeight-kCCGrabberHeight;
    scroller().contentSize = frame.size;
    
    
    
    %orig;
    
    
    
    NSUInteger index = 0;
    
    NSArray *sections = self._allSections;
    
    UIViewController *previous = nil;
    
    while (index < sections.count) {
        UIViewController *viewController = sections[index];
        
        UIView *view = viewController.view;
        
        CGRect frame = view.frame;
        
        BOOL landscapeSideSection = (landscape && (index == 0 || index == sections.count-1));
        
        
        if (landscapeSideSection) {
            frame.size.height = fakeHeight;
        }
        else {
            frame.origin.y = CGRectGetMaxY(previous.view.frame)+kCCSeparatorHeight;
            
            if (view.superview && view.superview != scroller()) {
                [scroller() addSubview:view];
            }
        }
        
        view.frame = frame;
        
        
        UIView *separator = [self _separatorAtIndex:index];
        
        if (separator) {
            CGRect separatorFrame = separator.frame;
            
            separatorFrame.origin.y -= kCCGrabberHeight;
            
            separator.frame = separatorFrame;
            
            if (separator.superview && separator.superview != scroller()) {
                [scroller() addSubview:separator];
            }
        }
        
        
        
        if (!landscapeSideSection) {
            previous = viewController;
        }
        
        index++;
    }
}

- (void)_removeSectionController:(SBControlCenterSectionViewController *)controller {
    %orig;
    
    [controller willMoveToParentViewController:nil];
    [controller.view removeFromSuperview];
    [controller removeFromParentViewController];
}

- (void)setFrame:(CGRect)frame {
    frame.size.height = realHeight;
    
    %orig;
}

- (NSMutableArray *)_allSections {
    if (landscape) {
        if (hideMediaControlsInCurrentSession) {
            return landscapeStrippedSectionViewControllers;
        }
        else {
            return landscapeSectionViewControllers;
        }
    }
    else {
        if (hideMediaControlsInCurrentSession) {
            return strippedSectionViewControllers;
        }
        else {
            return sectionViewControllers;
        }
    }
}

%end


%hook SBControlCenterController

+ (id)_sharedInstanceCreatingIfNeeded:(BOOL)needed {
    SBControlCenterController *controller = %orig;
    
    if (controller && !loadedSections) {
        loadedSections = YES;
        
        SBControlCenterViewController *viewController = MSHookIvar<SBControlCenterViewController *>(controller, "_viewController");
        
        SBControlCenterContentView *contentView = MSHookIvar<SBControlCenterContentView *>(viewController, "_contentView");
        
        loadCCSections(viewController, contentView);
    }
    
    return controller;
}


- (void)dealloc {
    %orig;
    
    [scroller() removeFromSuperview];
    [scroller() release];
    _scroller = nil;
    
    realHeight = 0.0f;
    fakeHeight = 0.0f;
    
    landscape = NO;
    
    hideMediaControlsInCurrentSession = NO;
    
    
    [customSectionViewControllers release];
    customSectionViewControllers = nil;
    
    [sectionViewControllers release];
    sectionViewControllers = nil;
    
    [strippedSectionViewControllers release];
    strippedSectionViewControllers = nil;
    
    [landscapeSectionViewControllers release];
    landscapeSectionViewControllers = nil;
    
    [landscapeStrippedSectionViewControllers release];
    landscapeStrippedSectionViewControllers = nil;
    
    
    loadedSections = NO;
}

%end


%hook SBControlCenterViewController

- (CGFloat)contentHeightForOrientation:(UIInterfaceOrientation)orientation {
    if (!contentHeightIsSet) {
        landscape = UIInterfaceOrientationIsLandscape(orientation);
        
        CGFloat height = %orig;
        
        if (landscape) {
            realHeight = kCCGrabberHeight;
            
            NSArray *search = (hideMediaControlsInCurrentSession ? landscapeStrippedSectionViewControllers : landscapeSectionViewControllers);
            
            for (NSUInteger i = 1; i < search.count-1; i++) {
                SBControlCenterSectionViewController *controller = search[i];
                
                realHeight += [controller contentSizeForOrientation:orientation].height+(i == 1 ? kCCSeparatorHeight : 0.0f);
            }
            
            fakeHeight = height;
            
            if (fakeHeight > realHeight) {
                realHeight = fakeHeight;
            }
        }
        else {
            realHeight = height;
            
            CGFloat screenHeight = self.view.frame.size.height;
            
            if (height > screenHeight) {
                height = screenHeight;
            }
            
            fakeHeight = height;
        }
        
        contentHeight = height;
        
        contentHeightIsSet = YES;
    }
    
    return contentHeight;
}

%new
- (void)_CCLoader_reloadContentHeight {
    SBControlCenterContentView *contentView = MSHookIvar<SBControlCenterContentView *>(self, "_contentView");
    
    [contentView setNeedsLayout];
    [contentView layoutIfNeeded];
    
    contentHeightIsSet = NO;
    [self _updateContentFrame];
    
    [UIView animateWithDuration:0.2 delay:0.0 options:(UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
        [contentView setNeedsLayout];
        [contentView layoutIfNeeded];
        [contentView updateEnabledSections];
    } completion:nil];
}

- (void)controlCenterWillBeginTransition {
    if (visible) {
//        visible = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CCLoaderCCWillDisappearNotification" object:nil];
    }
    
    %orig;
}

- (void)controlCenterDidFinishTransition {
    %orig;
    
    BOOL open = self.presented;
    
    if (open && !visible) {
        visible = YES;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CCLoaderCCDidAppearNotification" object:nil];
    }
}

- (void)controlCenterWillPresent {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_CCLoader_reloadContentHeight) name:@"CCLoaderReloadControlCenterHeight" object:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CCLoaderCCWillAppearNotification" object:nil];
    
    hideMediaControlsInCurrentSession = (strippedSectionViewControllers && ![[%c(SBMediaController) sharedInstance] nowPlayingApplication]);
    
    SBControlCenterContentView *contentView = MSHookIvar<SBControlCenterContentView *>(self, "_contentView");
    
    if (hideMediaControlsInCurrentSession) {
        [contentView _removeSectionController:contentView.mediaControlsSection];
    }
    
    %orig;
}

- (void)controlCenterDidDismiss {
    %orig;
    
    if (landscape) {
        SBControlCenterContentView *contentView = MSHookIvar<SBControlCenterContentView *>(self, "_contentView");
        
        [contentView _removeSectionController:contentView.settingsSection];
        [contentView _removeSectionController:contentView.quickLaunchSection];
    }
    
//    [scroller() removeFromSuperview];
    
    scroller().contentOffset = CGPointZero;
    
    realHeight = 0.0f;
    fakeHeight = 0.0f;
    
    landscape = NO;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CCLoaderCCDidDisappearNotification" object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"CCLoaderReloadControlCenterHeight" object:nil];
    
    contentHeightIsSet = NO;
    
    visible = NO;
}

%end

%end

#pragma mark - Constructor

%ctor {
	@autoreleasepool {
        CCBundleLoader *loader = [CCBundleLoader sharedInstance];
        
        [loader loadBundlesAndReplacements:YES loadNames:NO checkBundles:NO];
        
        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kCCLoaderSettingsPath];
        
        if (!prefs) {
            prefs = [NSMutableDictionary dictionary];
        }
        
        NSMutableArray *enabledSections = [prefs[@"EnabledSections"] mutableCopy];
        
        if (!enabledSections) {
            enabledSections = kCCLoaderStockOrderedSections.mutableCopy;
        }
        
        NSMutableArray *disabledSections = [prefs[@"DisabledSections"] mutableCopy];
        
        if (!disabledSections) {
            disabledSections = [[NSMutableArray alloc] init];
        }
        
        NSMutableOrderedSet *allIDs = [NSMutableOrderedSet orderedSetWithSet:loader.bundleIDs];
        
        if (!allIDs) {
            allIDs = [NSMutableOrderedSet orderedSet];
        }
        
        [allIDs addObjectsFromArray:loader.NCBundleIDs.allObjects];
        
        [allIDs addObjectsFromArray:kCCLoaderStockOrderedSections];
        
        //Remove deleted bundles
        NSUInteger i = 0;
        
        while (enabledSections.count > 0 && i < enabledSections.count) {
            NSString *ID = enabledSections[i];
            
            if (![allIDs containsObject:ID]) {
                [enabledSections removeObjectAtIndex:i];
            }
            else {
                i++;
            }
        }
        
        i = 0;
        
        while (disabledSections.count > 0 && i < disabledSections.count) {
            NSString *ID = disabledSections[i];
            
            if (![allIDs containsObject:ID]) {
                [disabledSections removeObjectAtIndex:i];
            }
            else {
                i++;
            }
        }
        
        //Add new bundles
        [allIDs minusSet:[NSSet setWithArray:enabledSections]];
        [allIDs minusSet:[NSSet setWithArray:disabledSections]];
        
        NSSet *immutableAllIds = allIDs.copy;
        
        //Add new NC bundles to disabled sections
        for (NSString *remaining in immutableAllIds) {
            if ([loader.NCBundleIDs containsObject:remaining]) {
                [disabledSections addObject:remaining];
                
                [allIDs removeObject:remaining];
            }
        }
        
        [immutableAllIds release];
        
        [enabledSections addObjectsFromArray:allIDs.array];
        
        if (enabledSections) {
            prefs[@"EnabledSections"] = enabledSections;
        }
        else {
            [prefs removeObjectForKey:@"EnabledSections"];
        }
        
        if (disabledSections) {
            prefs[@"DisabledSections"] = disabledSections;
        }
        else {
            [prefs removeObjectForKey:@"DisabledSections"];
        }
        
        
        
        NSMutableDictionary *replacing = loader.replacingBundles.mutableCopy;
        
        if (!replacing.count) {
            [prefs removeObjectForKey:@"ReplacingBundles"];
        }
        else {
            NSMutableDictionary *replacements = [prefs[@"ReplacingBundles"] mutableCopy];
            
            if (!replacements) {
                replacements = [[NSMutableDictionary alloc] init];
            }
            
            for (NSString *key in [replacements.copy autorelease]) {
                NSArray *replacementBundles = replacing[key];
                
                NSString *setReplacementID = replacements[key];
                
                if (replacementBundles) {
                    BOOL found = NO;
                    
                    for (NSBundle *bundle in replacementBundles) {
                        if ([bundle.bundleIdentifier isEqualToString:setReplacementID]) {
                            found = YES;
                            break;
                        }
                    }
                    
                    if (!found) {
                        replacements[key] = [replacementBundles.firstObject bundleIdentifier];
                    }
                    
                    [replacing removeObjectForKey:key];
                }
                else {
                    [replacements removeObjectForKey:key];
                }
            }
            
            for (NSString *key in replacing) {
                NSArray *replacementBundles = replacing[key];
                
                replacements[key] = [replacementBundles.firstObject bundleIdentifier];
            }
            
            prefs[@"ReplacingBundles"] = replacements;
            
            [replacements release];
        }
        
        
        [prefs writeToFile:kCCLoaderSettingsPath atomically:YES];
        
        [replacing release];
        [enabledSections release];
        [disabledSections release];
        
		%init(main);
        
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadCCSections, CFSTR("de.j-gessner.ccloader.settingschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}
}
