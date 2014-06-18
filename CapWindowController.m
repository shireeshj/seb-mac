//
//  CapWindowController.m
//  SafeExamBrowser
//
//  Created by Daniel R. Schneider on 11.03.14.
//  Copyright (c) 2010-2014 Daniel R. Schneider, ETH Zurich,
//  Educational Development and Technology (LET),
//  based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider,
//  Dirk Bauer, Kai Reuter, Tobias Halbherr, Karsten Burger, Marco Lehre,
//  Brigitte Schmucki, Oliver Rahs. French localization: Nicolas Dunand
//
//  ``The contents of this file are subject to the Mozilla Public License
//  Version 1.1 (the "License"); you may not use this file except in
//  compliance with the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
//
//  Software distributed under the License is distributed on an "AS IS"
//  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
//  License for the specific language governing rights and limitations
//  under the License.
//
//  The Original Code is Safe Exam Browser for Mac OS X.
//
//  The Initial Developer of the Original Code is Daniel R. Schneider.
//  Portions created by Daniel R. Schneider are Copyright
//  (c) 2010-2014 Daniel R. Schneider, ETH Zurich, Educational Development
//  and Technology (LET), based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//
//  Contributor(s): ______________________________________.
//


#import "CapWindowController.h"
#import "CapWindow.h"
#import "NSUserDefaults+SEBEncryptedUserDefaults.h"


@implementation CapWindowController

@synthesize frameForNonFullScreenMode;


- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorCanJoinAllSpaces];
}


// -------------------------------------------------------------------------------
//	awakeFromNib
// -------------------------------------------------------------------------------
- (void)awakeFromNib
{
    // To specify we want our given window to be the full screen primary one, we can
    // use the following:
    //[self.window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    //
    // But since we have already set this in our xib file for our NSWindow object
    //  (Full Screen -> Primary Window) this line of code it not needed.
    
	// listen for these notifications so we can update our image based on the full-screen state
    
    [self.window setSharingType:NSWindowSharingNone];
}

// -------------------------------------------------------------------------------
//	window:willUseFullScreenContentSize:proposedSize
//
//  A window's delegate can optionally override this method, to specify a different
//  Full Screen size for the window. This delegate method override's the window's full
//  screen content size to include a border around it.
// -------------------------------------------------------------------------------
- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)proposedSize
{
    // leave a border around our full screen window
    //return NSMakeSize(proposedSize.width - 180, proposedSize.height - 100);
    NSSize idealWindowSize = NSMakeSize(proposedSize.width, proposedSize.height);
    
    // Constrain that ideal size to the available area (proposedSize).
    NSSize customWindowSize;
    customWindowSize.width  = MIN(idealWindowSize.width,  proposedSize.width);
    customWindowSize.height = MIN(idealWindowSize.height, proposedSize.height);
    
    // Return the result.
    return customWindowSize;
}

// -------------------------------------------------------------------------------
//	window:willUseFullScreenPresentationOptions:proposedOptions
//
//  Delegate method to determine the presentation options the window will use when
//  transitioning to full-screen mode.
// -------------------------------------------------------------------------------
- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
    // customize the appearance when entering full screen:
    // Set a global flag that we're transitioning to full screen
    //[[MyGlobals sharedMyGlobals] setTransitioningToFullscreen:YES];
    
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	BOOL allowSwitchToThirdPartyApps = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"];
	BOOL showMenuBar = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_showMenuBar"];
	BOOL enableToolbar = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_enableBrowserWindowToolbar"];
	BOOL hideToolbar = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_hideBrowserWindowToolbar"];
    
    if (!allowSwitchToThirdPartyApps) {
		// if switching to third party apps not allowed
        NSApplicationPresentationOptions options =
        NSApplicationPresentationHideDock +
        NSApplicationPresentationFullScreen +
        (enableToolbar && hideToolbar ?
         NSApplicationPresentationAutoHideToolbar + NSApplicationPresentationAutoHideMenuBar :
         (showMenuBar ? NSApplicationPresentationDisableAppleMenu : NSApplicationPresentationHideMenuBar)) +
        NSApplicationPresentationDisableProcessSwitching +
        NSApplicationPresentationDisableForceQuit +
        NSApplicationPresentationDisableSessionTermination;
        return options;
    } else {
		// if switching to third party apps allowed
        NSApplicationPresentationOptions options =
        NSApplicationPresentationHideDock +
        NSApplicationPresentationFullScreen +
        (enableToolbar && hideToolbar ?
         NSApplicationPresentationAutoHideToolbar + NSApplicationPresentationAutoHideMenuBar :
         (showMenuBar ? NSApplicationPresentationDisableAppleMenu : NSApplicationPresentationHideMenuBar)) +
        NSApplicationPresentationDisableForceQuit +
        NSApplicationPresentationDisableSessionTermination;
        return options;
    }
}


#pragma mark -
#pragma mark Enter Full Screen

// as a window delegate, window delegate we provide a list of windows involved in our custom animation,
// in our case we animate just the one primary window.
//
- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    self.frameForNonFullScreenMode = [window frame];
    [self invalidateRestorableState];
    
    NSInteger previousWindowLevel = [window level];
    [window setLevel:(NSModalPanelWindowLevel + 1)];
    
    [window setStyleMask:([window styleMask] | NSFullScreenWindowMask)];
    
    NSScreen *screen = [[NSScreen screens] objectAtIndex:0];
    NSRect screenFrame = [screen frame];
    
    NSRect proposedFrame = screenFrame;
    proposedFrame.size = [self window:window willUseFullScreenContentSize:proposedFrame.size];
    
    proposedFrame.origin.x += floor(0.5 * (NSWidth(screenFrame) - NSWidth(proposedFrame)));
    proposedFrame.origin.y += floor(0.5 * (NSHeight(screenFrame) - NSHeight(proposedFrame)));
    
    // The center frame for each window is used during the 1st half of the fullscreen animation and is
    // the window at its original size but moved to the center of its eventual full screen frame.
    NSRect centerWindowFrame = [window frame];
    centerWindowFrame.origin.x = proposedFrame.size.width/2 - centerWindowFrame.size.width/2;
    centerWindowFrame.origin.y = proposedFrame.size.height/2 - centerWindowFrame.size.height/2;
    
    // If our window animation takes the same amount of time as the system's animation,
    // a small black flash will occur atthe end of your animation.  However, if we
    // leave some extra time between when our animation completes and when the system's animation
    // completes we can avoid this.
    duration -= 0.2;
    
    // Our animation will be broken into two stages.  First, we'll move the window to the center
    // of the primary screen and then we'll enlarge it its full screen size.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        
        [context setDuration:duration/2];
        [[window animator] setFrame:centerWindowFrame display:YES];
        
    } completionHandler:^{
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context){
            
            [context setDuration:duration/2];
            [[window animator] setFrame:proposedFrame display:YES];
            
        } completionHandler:^{
            
            [self.window setLevel:previousWindowLevel];
        }];
    }];
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
    // If we had any cleanup to perform in the event of failure to enter Full Screen,
    // this would be the place to do it.
    //
    // One case would be if the user attempts to move to full screen but then
    // immediately switches to Dashboard.
}


#pragma mark -
#pragma mark Exit Full Screen

- (NSArray *)customWindowsToExitFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    [(CapWindow *)window setConstrainingToScreenSuspended:YES];
    
    NSInteger previousWindowLevel = [window level];
    [window setLevel:(NSModalPanelWindowLevel + 1)];
    
    [window setStyleMask:([window styleMask] & ~NSFullScreenWindowMask)];
    
    // The center frame for each window is used during the 1st half of the fullscreen animation and is
    // the window at its original size but moved to the center of its eventual full screen frame.
    NSRect centerWindowFrame = self.frameForNonFullScreenMode;
    centerWindowFrame.origin.x = window.frame.size.width/2 - self.frameForNonFullScreenMode.size.width/2;
    centerWindowFrame.origin.y = window.frame.size.height/2 - self.frameForNonFullScreenMode.size.height/2;
    
    // Our animation will be broken into two stages.  First, we'll restore the window
    // to its original size while centering it and then we'll move it back to its initial
    // position.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context)
     {
         [context setDuration:duration/2];
         [[window animator] setFrame:centerWindowFrame display:YES];
         
     } completionHandler:^{
         
         [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context){
             [context setDuration:duration/2];
             [[window animator] setFrame:self.frameForNonFullScreenMode display:YES];
             
         } completionHandler:^{
             
             [(CapWindow *)window setConstrainingToScreenSuspended:NO];
             
             [self.window setLevel:previousWindowLevel];
         }];
         
     }];
}

- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
    // If we had any cleanup to perform in the event of failure to exit Full Screen,
    // this would be the place to do it.
    // ...
}


#pragma mark -
#pragma mark Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray *)restorableStateKeyPaths
{
    return [[super restorableStateKeyPaths] arrayByAddingObject:@"frameForNonFullScreenMode"];
}


@end