//
//  SEBController.m
//  Safe Exam Browser
//
//  Created by Daniel R. Schneider on 29.04.10.
//  Copyright (c) 2010-2013 Daniel R. Schneider, ETH Zurich, 
//  Educational Development and Technology (LET), 
//  based on the original idea of Safe Exam Browser 
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider, 
//  Dirk Bauer, Karsten Burger, Marco Lehre, 
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
//  (c) 2010-2013 Daniel R. Schneider, ETH Zurich, Educational Development
//  and Technology (LET), based on the original idea of Safe Exam Browser 
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//  
//  Contributor(s): ______________________________________.
//

#include <Carbon/Carbon.h>
#import "SEBController.h"

#import <IOKit/pwr_mgt/IOPMLib.h>

#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>

#include <mach/mach_port.h>
#include <mach/mach_interface.h>
#include <mach/mach_init.h>

#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>

#import "MyDocument.h"
#import "BrowserWindow.h"
#import "PrefsBrowserViewController.h"
#import "RNDecryptor.h"
#import "SEBKeychainManager.h"
#import "SEBCryptor.h"
#import "NSWindow+SEBWindow.h"
#import "NSUserDefaults+SEBEncryptedUserDefaults.h"
#import "SEBWindowSizeValueTransformer.h"
#import "BoolValueTransformer.h"
#import "IsEmptyCollectionValueTransformer.h"
#import "MyGlobals.h"
#import "Constants.h"

io_connect_t  root_port; // a reference to the Root Power Domain IOService


OSStatus MyHotKeyHandler(EventHandlerCallRef nextHandler,EventRef theEvent,id sender);
void MySleepCallBack(void * refCon, io_service_t service, natural_t messageType, void * messageArgument);
bool insideMatrix();

@implementation SEBController

@synthesize f3Pressed;	//create getter and setter for F3 key pressed flag
@synthesize quittingMyself;	//create getter and setter for flag that SEB is quitting itself
@synthesize webView;
@synthesize capWindows;

#pragma mark Application Delegate Methods

+ (void) initialize
{
    SEBWindowSizeValueTransformer *windowSizeTransformer = [[SEBWindowSizeValueTransformer alloc] init];
    [NSValueTransformer setValueTransformer:windowSizeTransformer
                                    forName:@"SEBWindowSizeTransformer"];

    BoolValueTransformer *boolValueTransformer = [[BoolValueTransformer alloc] init];
    [NSValueTransformer setValueTransformer:boolValueTransformer
                                    forName:@"BoolValueTransformer"];
    
    IsEmptyCollectionValueTransformer *isEmptyCollectionValueTransformer = [[IsEmptyCollectionValueTransformer alloc] init];
    [NSValueTransformer setValueTransformer:isEmptyCollectionValueTransformer
                                    forName:@"isEmptyCollectionValueTransformer"];
    
}


// Tells the application delegate to open a single file.
// Returning YES if the file is successfully opened, and NO otherwise.
//
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    NSURL *sebFileURL = [NSURL fileURLWithPath:filename];

    // Check if SEB is in exam mode = private UserDefauls are switched on
    if (NSUserDefaults.userDefaultsPrivate) {
        NSRunAlertPanel(NSLocalizedString(@"Loading New SEB Settings Not Allowed!", nil),
                        NSLocalizedString(@"SEB is already running in exam mode at the moment (started by a .seb file) and it is not allowed to interupt this by opening another .seb file. Finish the exam and quit SEB before starting another exam by opening a .seb file.", nil),
                        NSLocalizedString(@"OK", nil), nil, nil);
        return YES;
    }

#ifdef DEBUG
    NSLog(@"Loading .seb settings file with URL %@",sebFileURL);
#endif
    NSData *sebData = [NSData dataWithContentsOfURL:sebFileURL];
    //NSData *decryptedSebData = nil;

    // Getting 4-char prefix
    const char *utfString = [@"    " UTF8String];
    [sebData getBytes:(void *)utfString length:4];

    // Get data without the prefix
    NSRange range = {4, [sebData length]-4};
    sebData = [sebData subdataWithRange:range];
#ifdef DEBUG
    NSLog(@"Outer prefix of .seb settings file: %s",utfString);
    //NSLog(@"Prefix of .seb settings file: %@",[NSString stringWithUTF8String:utfString]);
#endif
    
    //
    // Decrypt with cryptographic identity/private key
    //
    if ([[NSString stringWithUTF8String:utfString] isEqualToString:@"pkhs"]) {
        // Get 20 bytes public key hash
        NSRange hashRange = {0, 20};
        NSData *publicKeyHash = [sebData subdataWithRange:hashRange];
    
        SEBKeychainManager *keychainManager = [[SEBKeychainManager alloc] init];
        SecKeyRef privateKeyRef = [keychainManager getPrivateKeyFromPublicKeyHash:publicKeyHash];
        if (!privateKeyRef) {
            NSRunAlertPanel(NSLocalizedString(@"Error Decrypting Settings", nil),
                            NSLocalizedString(@"The private key needed to decrypt settings has not been found in the keychain!", nil),
                            NSLocalizedString(@"OK", nil), nil, nil);
            return YES;
        }
#ifdef DEBUG
        NSLog(@"Private key retrieved with hash: %@", privateKeyRef);
#endif
        NSRange dataRange = {20, [sebData length]-20};
        sebData = [sebData subdataWithRange:dataRange];

        sebData = [keychainManager decryptData:sebData withPrivateKey:privateKeyRef];

        // Getting 4-char prefix again
        [sebData getBytes:(void *)utfString length:4];
#ifdef DEBUG
        NSLog(@"Inner prefix of .seb settings file: %s",utfString);
        //NSLog(@"Prefix of .seb settings file: %@",[NSString stringWithUTF8String:utfString]);
#endif
        // Get remaining data without prefix, which is either plain or still encoded with password
        NSRange range = {4, [sebData length]-4};
        sebData = [sebData subdataWithRange:range];
}
    
    //
    // Decrypt with password
    //
    NSError *error;

    if ([[NSString stringWithUTF8String:utfString] isEqualToString:@"pswd"]) {
#ifdef DEBUG
        //NSLog(@"Dump of encypted .seb settings (without prefix): %@",encryptedSebData);
#endif
        NSData *sebDataDecrypted = nil;
        // Allow up to 5 attempts for entering decoding password
        int i = 5;
        do {
            i--;
            // Prompt for password
            if ([self showEnterPasswordDialog:NSLocalizedString(@"Enter Password:",nil) modalForWindow:nil windowTitle:NSLocalizedString(@"Loading New SEB Settings",nil)] == SEBEnterPasswordCancel) return YES;
            NSString *password = [enterPassword stringValue];
            if (!password) return YES;
            error = nil;
            sebDataDecrypted = [RNDecryptor decryptData:sebData withPassword:password error:&error];
            // in case we get an error we allow the user to try it again
        } while (error && i>0);
        if (error) {
            //wrong password entered in 5th try: stop reading .seb file
            return YES;
        }
        sebData = sebDataDecrypted;
    }
    
    //
    // Configure local client settings
    //
    if ([[NSString stringWithUTF8String:utfString] isEqualToString:@"pwcc"]) {
        //get admin password hash
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        NSString *hashedAdminPassword = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedAdminPassword"];
        //if (!hashedAdminPassword) {
        //   hashedAdminPassword = @"";
        //}
        NSDictionary *sebPreferencesDict = nil;
        error = nil;
        NSData *decryptedSebData = [RNDecryptor decryptData:sebData withPassword:hashedAdminPassword error:&error];
        if (error) {
            //if decryption with admin password didn't work, try it with an empty password
            error = nil;
            decryptedSebData = [RNDecryptor decryptData:sebData withPassword:@"" error:&error];
            if (!error) {
                //Decrypting with empty password worked:                 
                //Check if the openend reconfiguring seb file has the same admin password inside like the current one
                sebPreferencesDict = [NSPropertyListSerialization propertyListWithData:decryptedSebData
                                                                                             options:0
                                                                                              format:NULL
                                                                                               error:&error];
                NSString *sebFileHashedAdminPassword = [sebPreferencesDict objectForKey:@"hashedAdminPassword"];
                if (![hashedAdminPassword isEqualToString:sebFileHashedAdminPassword]) {
                    //No: The admin password inside the .seb file wasn't the same like the current one
                    //now we have to ask for the current admin password and
                    //allow reconfiguring only if the user enters the right one
                    // Allow up to 5 attempts for entering current admin password
                    int i = 5;
                    NSString *password = nil;
                    NSString *hashedPassword;
                    BOOL passwordsMatch;
                    SEBKeychainManager *keychainManager = [[SEBKeychainManager alloc] init];
                    do {
                        i--;
                        // Prompt for password
                        if ([self showEnterPasswordDialog:NSLocalizedString(@"You are trying to reconfigure local SEB settings to an initial configuration, but there is already an administrator password set. You can only reset SEB to the initial configuration if you enter the current SEB administrator password:",nil) modalForWindow:nil windowTitle:NSLocalizedString(@"Reconfiguring Local SEB Settings",nil)] == SEBEnterPasswordCancel) return YES;
                        password = [enterPassword stringValue];
                        hashedPassword = [keychainManager generateSHAHashString:password];
                        passwordsMatch = [hashedAdminPassword isEqualToString:hashedPassword];
                        // in case we get an error we allow the user to try it again
                    } while ((!password || !passwordsMatch) && i>0);
                    if (!passwordsMatch) {
                        //wrong password entered in 5th try: stop reading .seb file
                        return YES;
                    }
                }

            } else {
                //if decryption with admin password didn't work, ask for the password the .seb file was encrypted with
                //empty password means no admin pw on clients and should not be hashed
                //NSData *sebDataDecrypted = nil;
                // Allow up to 3 attempts for entering decoding password
                int i = 3;
                do {
                    i--;
                    // Prompt for password
                    if ([self showEnterPasswordDialog:NSLocalizedString(@"Enter password used to encrypt .seb file:",nil) modalForWindow:nil windowTitle:NSLocalizedString(@"Reconfiguring Local SEB Settings",nil)] == SEBEnterPasswordCancel) return YES;
                    NSString *password = [enterPassword stringValue];
                    if (!password) return YES;
                    error = nil;
                    decryptedSebData = [RNDecryptor decryptData:sebData withPassword:password error:&error];
                    // in case we get an error we allow the user to try it again
                } while (error && i>0);
                if (error) {
                    //wrong password entered in 5th try: stop reading .seb file
                    return YES;
                }
            }
        }
        sebData = decryptedSebData;
        if (!error) {
            // if decryption worked
            //switch to system's UserDefaults
            [NSUserDefaults setUserDefaultsPrivate:NO];
            // Get preferences dictionary from decrypted data
            NSError *error;
            if (!sebPreferencesDict) sebPreferencesDict = [NSPropertyListSerialization propertyListWithData:sebData
                                                                                         options:0
                                                                                          format:NULL
                                                                                           error:&error];
            for (NSString *key in sebPreferencesDict) {
                if ([key isEqualToString:@"allowPreferencesWindow"]) {
                    [preferences setSecureObject:
                     [[sebPreferencesDict objectForKey:key] copy]
                                        forKey:@"org_safeexambrowser_SEB_enablePreferencesWindow"];
                } 
                NSString *keyWithPrefix = [NSString stringWithFormat:@"org_safeexambrowser_SEB_%@", key];
                [preferences setSecureObject:[sebPreferencesDict objectForKey:key] forKey:keyWithPrefix];
            }
            int answer = NSRunAlertPanel(NSLocalizedString(@"SEB Re-Configured",nil), NSLocalizedString(@"The local settings of SEB have been reconfigured. Do you want to start working with SEB now or quit?",nil),
                                         NSLocalizedString(@"Continue",nil), NSLocalizedString(@"Quit",nil), nil);
            switch(answer)
            {
                case NSAlertDefaultReturn:
                    break; //Cancel: don't quit
                default:
					quittingMyself = TRUE; //SEB is terminating itself
                    [NSApp terminate: nil]; //quit SEB
            }
            [[SEBCryptor sharedSEBCryptor] updateEncryptedUserDefaults];
            [self startKioskMode];
            [self requestedRestart:nil];
        }
        return YES; //we're done here
    }
    
    //if decrypting wasn't successfull then stop here
    if (!sebData) return YES;

    // Get preferences dictionary from decrypted data
    //NSDictionary *sebPreferencesDict = [NSKeyedUnarchiver unarchiveObjectWithData:sebData];
    NSDictionary *sebPreferencesDict = [NSPropertyListSerialization propertyListWithData:sebData
                                                                                 options:0
                                                                                  format:NULL
                                                                                   error:&error];
    
    [preferencesController releasePreferencesWindow];

    // Switch to private UserDefaults (saved non-persistantly in memory instead in ~/Library/Preferences)
    NSMutableDictionary *privatePreferences = [NSUserDefaults privateUserDefaults];
    // Use private UserDefaults
    [NSUserDefaults setUserDefaultsPrivate:YES];
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    // Write SEB default values to the private preferences
    for (NSString *key in sebPreferencesDict) {
        if ([key isEqualToString:@"allowPreferencesWindow"]) {
            [preferences setSecureObject:
             [[sebPreferencesDict objectForKey:key] copy]
                                  forKey:@"org_safeexambrowser_SEB_enablePreferencesWindow"];
        }
        NSString *keyWithPrefix = [NSString stringWithFormat:@"org_safeexambrowser_SEB_%@", key];
        id value = [sebPreferencesDict objectForKey:key];
        if (value) [preferences setSecureObject:value forKey:keyWithPrefix];
        //NSString *keypath = [NSString stringWithFormat:@"values.%@", keyWithPrefix];
        //if (value) [[[SEBEncryptedUserDefaultsController sharedSEBEncryptedUserDefaultsController] values] setValue:value forKeyPath:keyWithPrefix];
        //if (value) [[SEBEncryptedUserDefaultsController sharedSEBEncryptedUserDefaultsController] setValue:value forKeyPath:keypath];
    }
#ifdef DEBUG
    NSLog(@"Private preferences set: %@", privatePreferences);
#endif
    [[SEBCryptor sharedSEBCryptor] updateEncryptedUserDefaults];
    [preferencesController initPreferencesWindow];
    [self startKioskMode];
    [self requestedRestart:nil];
    
    return YES;
}


#pragma mark Initialization

- (id)init {
    self = [super init];
    if (self) {
        // Add your subclass-specific initialization here.
        // If an error occurs here, send a [self release] message and return nil.
        
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        // Set flag for displaying alert to new users
        if ([preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"] == nil) {
            firstStart = YES;
        } else {
            firstStart = NO;
        }
        // Set default preferences for the case there are no user prefs yet
        //SEBnewBrowserWindowLink newBrowserWindowLinkPolicy = openInNewWindow;
        NSDictionary *appDefaults = [preferences sebDefaultSettings];
        [preferences registerDefaults:appDefaults];
        [[SEBCryptor sharedSEBCryptor] updateEncryptedUserDefaults];
#ifdef DEBUG
        NSLog(@"Registred Defaults");
#endif        
    }
    return self;
}


- (void)awakeFromNib {	
	// Flag initializing
	quittingMyself = FALSE; //flag to know if quit application was called externally
    
    // Terminate invisibly running applications
    if ([NSRunningApplication respondsToSelector:@selector(terminateAutomaticallyTerminableApplications)]) {
        [NSRunningApplication terminateAutomaticallyTerminableApplications];
    }

    // Save the bundle ID of all currently running apps which are visible in a array
	NSArray *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
    NSRunningApplication *iterApp;
    visibleApps = [NSMutableArray array]; //array for storing bundleIDs of visible apps

    for (iterApp in runningApps) 
    {
        BOOL isHidden = [iterApp isHidden];
        NSString *appBundleID = [iterApp valueForKey:@"bundleIdentifier"];
        if ((appBundleID != nil) & !isHidden) {
            [visibleApps addObject:appBundleID]; //add ID of the visible app
        }
    }

// Setup Notifications and Kiosk Mode    
    
    // Add an observer for the notification that another application became active (SEB got inactive)
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(regainActiveStatus:) 
												 name:NSApplicationDidResignActiveNotification 
                                               object:NSApp];
	
#ifndef DEBUG
    // Add an observer for the notification that another application was unhidden by the finder
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	[[workspace notificationCenter] addObserver:self
                                       selector:@selector(regainActiveStatus:)
                                           name:NSWorkspaceDidActivateApplicationNotification
                                         object:workspace];
	
    // Add an observer for the notification that another application was unhidden by the finder
	[[workspace notificationCenter] addObserver:self
                                       selector:@selector(regainActiveStatus:)
                                           name:NSWorkspaceDidUnhideApplicationNotification
                                         object:workspace];
	
    // Add an observer for the notification that another application was unhidden by the finder
	[[workspace notificationCenter] addObserver:self
                                       selector:@selector(regainActiveStatus:)
                                           name:NSWorkspaceWillLaunchApplicationNotification
                                         object:workspace];
	
    // Add an observer for the notification that another application was unhidden by the finder
	[[workspace notificationCenter] addObserver:self
                                       selector:@selector(regainActiveStatus:)
                                           name:NSWorkspaceDidLaunchApplicationNotification
                                         object:workspace];
	
#endif
    // Add an observer for the notification that SEB became active
    // With third party apps and Flash fullscreen it can happen that SEB looses its 
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SEBgotActive:)
												 name:NSApplicationDidBecomeActiveNotification 
                                               object:NSApp];
	
    // Hide all other applications
	[[NSWorkspace sharedWorkspace] performSelectorOnMainThread:@selector(hideOtherApplications)
													withObject:NULL waitUntilDone:NO];
	
// Switch to kiosk mode by setting the proper presentation options
	[self startKioskMode];
	
    // Add an observer for changes of the Presentation Options
	[NSApp addObserver:self
			forKeyPath:@"currentSystemPresentationOptions"
			   options:NSKeyValueObservingOptionNew
			   context:NULL];
		
// Cover all attached screens with cap windows to prevent clicks on desktop making finder active
	[self coverScreens];
    
    // Add a observer for changes of the screen configuration
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adjustScreenLocking:) 
												 name:NSApplicationDidChangeScreenParametersNotification 
                                               object:NSApp];

	// Add an observer for the request to conditionally exit SEB
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(exitSEB:)
                                                 name:@"requestExitNotification" object:nil];
	
    // Add an observer for the request to conditionally quit SEB without asking quit password
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestedQuitWoPwd:)
                                                 name:@"requestQuitWoPwdNotification" object:nil];
	
    // Add an observer for the request to unconditionally quit SEB
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestedQuit:)
                                                 name:@"requestQuitNotification" object:nil];
	
    // Add an observer for the request to reload start URL
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestedRestart:)
                                                 name:@"requestRestartNotification" object:nil];
	
    // Add an observer for the request to show about panel
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestedShowAbout:)
                                                 name:@"requestShowAboutNotification" object:nil];
	
    // Add an observer for the request to close about panel
    [[NSNotificationCenter defaultCenter] addObserver:aboutWindow
                                             selector:@selector(closeAboutWindow:)
                                                 name:@"requestCloseAboutWindowNotification" object:nil];
	
    // Add an observer for the request to show help
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestedShowHelp:)
                                                 name:@"requestShowHelpNotification" object:nil];

    // Add an observer for the request to switch plugins on
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(switchPluginsOn:)
                                                 name:@"switchPluginsOn" object:nil];
    
    // Add an observer for the notification that preferences were closed
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(preferencesClosed:)
                                                 name:@"preferencesClosed" object:nil];
    //[self startTask];

// Prevent display sleep
#ifndef DEBUG
    IOPMAssertionCreateWithName(
		kIOPMAssertionTypeNoDisplaySleep,										   
		kIOPMAssertionLevelOn, 
		CFSTR("Safe Exam Browser Kiosk Mode"), 
		&assertionID1); 
#else
    IOReturn success = IOPMAssertionCreateWithName(
                                                   kIOPMAssertionTypeNoDisplaySleep,										   
                                                   kIOPMAssertionLevelOn, 
                                                   CFSTR("Safe Exam Browser Kiosk Mode"), 
                                                   &assertionID1);
	if (success == kIOReturnSuccess) {
		NSLog(@"Display sleep is switched off now.");
	}
#endif		
	
/*	// Prevent idle sleep
	success = IOPMAssertionCreateWithName(
		kIOPMAssertionTypeNoIdleSleep, 
		kIOPMAssertionLevelOn, 
		CFSTR("Safe Exam Browser Kiosk Mode"), 
		&assertionID2); 
#ifdef DEBUG
	if (success == kIOReturnSuccess) {
		NSLog(@"Idle sleep is switched off now.");
	}
#endif		
*/	
	// Installing I/O Kit sleep/wake notification to cancel sleep
	
	IONotificationPortRef notifyPortRef; // notification port allocated by IORegisterForSystemPower
    io_object_t notifierObject; // notifier object, used to deregister later
    void* refCon; // this parameter is passed to the callback
	
    // register to receive system sleep notifications

    root_port = IORegisterForSystemPower( refCon, &notifyPortRef, MySleepCallBack, &notifierObject );
    if ( root_port == 0 )
    {
        NSLog(@"IORegisterForSystemPower failed");
    } else {
	    // add the notification port to the application runloop
		CFRunLoopAddSource( CFRunLoopGetCurrent(),
					   IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes ); 
	}
	
// Check if SEB is running inside a virtual machine
    SInt32		myAttrs;
	OSErr		myErr = noErr;
	
	// Get details for the present operating environment
	// by calling Gestalt (Userland equivalent to CPUID)
	myErr = Gestalt(gestaltX86AdditionalFeatures, &myAttrs);
	if (myErr == noErr) {
		if ((myAttrs & (1UL << 31)) | (myAttrs == 0x209)) {
			// Bit 31 is set: VMware Hypervisor running (?)
            // or gestaltX86AdditionalFeatures values of VirtualBox detected
#ifdef DEBUG
            NSLog(@"SERIOUS SECURITY ISSUE DETECTED: SEB was started up in a virtual machine! gestaltX86AdditionalFeatures = %X", myAttrs);
#endif
            NSRunAlertPanel(NSLocalizedString(@"Virtual Machine detected!", nil),
                            NSLocalizedString(@"You are not allowed to run SEB inside a virtual machine!", nil), 
                            NSLocalizedString(@"Quit", nil), nil, nil);
            quittingMyself = TRUE; //SEB is terminating itself
            [NSApp terminate: nil]; //quit SEB
            
#ifdef DEBUG
		} else {
            NSLog(@"SEB is running on a native system (no VM) gestaltX86AdditionalFeatures = %X", myAttrs);
#endif
        }
	}
    
    bool    virtualMachine = false;
	// STR or SIDT code?
	virtualMachine = insideMatrix();
    if (virtualMachine) {
        NSLog(@"SERIOUS SECURITY ISSUE DETECTED: SEB was started up in a virtual machine (Test2)!");
    }


// Clear Pasteboard, but save the current content in case it is a NSString
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard]; 
    //NSArray *classes = [[NSArray alloc] initWithObjects:[NSString class], [NSAttributedString class], nil];
    NSArray *classes = [[NSArray alloc] initWithObjects:[NSString class], nil];
    NSDictionary *options = [NSDictionary dictionary];
    NSArray *copiedItems = [pasteboard readObjectsForClasses:classes options:options];
    if ((copiedItems != nil) && [copiedItems count]) {
        // if there is a NSSting in the pasteboard, save it for later use
        //[[MyGlobals sharedMyGlobals] setPasteboardString:[copiedItems objectAtIndex:0]];
        [[MyGlobals sharedMyGlobals] setValue:[copiedItems objectAtIndex:0] forKey:@"pasteboardString"];
#ifdef DEBUG
        NSLog(@"String saved from pasteboard");
#endif
    } else {
        [[MyGlobals sharedMyGlobals] setValue:@"" forKey:@"pasteboardString"];
    }
#ifdef DEBUG
    NSString *stringFromPasteboard = [[MyGlobals sharedMyGlobals] pasteboardString];
    NSLog(@"Saved string from Pasteboard: %@", stringFromPasteboard);
#endif
    //NSInteger changeCount = [pasteboard clearContents];
    [pasteboard clearContents];
    
// Set up SEB Browser 
    [self openMainBrowserWindow];
    
	// Due to the infamous Flash plugin we completely disable plugins in the 32-bit build
#ifdef __i386__        // 32-bit Intel build
	[[self.webView preferences] setPlugInsEnabled:NO];
#endif
	
/*	if (firstStart) {
		NSString *titleString = NSLocalizedString(@"Important Notice for First Time Users", nil);
		NSString *messageString = NSLocalizedString(@"FirstTimeUserNotice", nil);
		NSRunAlertPanel(titleString, messageString, NSLocalizedString(@"OK", nil), nil, nil);
#ifdef DEBUG
        NSLog(@"%@\n%@",titleString, messageString);
#endif
	}*/
    
// Handling of Hotkeys for Preferences-Window
	
	// Register Carbon event handlers for the required hotkeys
	f3Pressed = FALSE; //Initialize flag for first hotkey
	EventHotKeyRef gMyHotKeyRef;
	EventHotKeyID gMyHotKeyID;
	EventTypeSpec eventType;
	eventType.eventClass=kEventClassKeyboard;
	eventType.eventKind=kEventHotKeyPressed;
	InstallApplicationEventHandler((void*)MyHotKeyHandler, 1, &eventType, (__bridge void*)(SEBController*)self, NULL);
    //Pass pointer to flag for F3 key to the event handler
	// Register F3 as a hotkey
	gMyHotKeyID.signature='htk1';
	gMyHotKeyID.id=1;
	RegisterEventHotKey(99, 0, gMyHotKeyID,
						GetApplicationEventTarget(), 0, &gMyHotKeyRef);
	// Register F6 as a hotkey
	gMyHotKeyID.signature='htk2';
	gMyHotKeyID.id=2;
	RegisterEventHotKey(97, 0, gMyHotKeyID,
						GetApplicationEventTarget(), 0, &gMyHotKeyRef);
    
    // Show the About SEB Window
    [aboutWindow showAboutWindowForSeconds:3];

}



#pragma mark Methods

// Method executed when hotkeys are pressed
OSStatus MyHotKeyHandler(EventHandlerCallRef nextHandler,EventRef theEvent,
						  id userData)
{
	EventHotKeyID hkCom;
	GetEventParameter(theEvent,kEventParamDirectObject,typeEventHotKeyID,NULL,
					  sizeof(hkCom),NULL,&hkCom);
	int l = hkCom.id;
	id self = userData;
	
	switch (l) {
		case 1: //F3 pressed
			[self setF3Pressed:TRUE];	//F3 was pressed
			
			break;
		case 2: //F6 pressed
			if ([self f3Pressed]) {	//if F3 got pressed before
				[self setF3Pressed:FALSE];
				[self openPreferences:self]; //show preferences window
			}
			break;
	}
	return noErr;
}


// Method called by I/O Kit power management
void MySleepCallBack( void * refCon, io_service_t service, natural_t messageType, void * messageArgument )
{
    printf( "messageType %08lx, arg %08lx\n",
		   (long unsigned int)messageType,
		   (long unsigned int)messageArgument );
	
    switch ( messageType )
    {
			
        case kIOMessageCanSystemSleep:
            /* Idle sleep is about to kick in. This message will not be sent for forced sleep.
			 Applications have a chance to prevent sleep by calling IOCancelPowerChange.
			 Most applications should not prevent idle sleep.
			 
			 Power Management waits up to 30 seconds for you to either allow or deny idle sleep.
			 If you don't acknowledge this power change by calling either IOAllowPowerChange
			 or IOCancelPowerChange, the system will wait 30 seconds then go to sleep.
			 */
			
            // cancel idle sleep
            IOCancelPowerChange( root_port, (long)messageArgument );
            // uncomment to allow idle sleep
            //IOAllowPowerChange( root_port, (long)messageArgument );
            break;
			
        case kIOMessageSystemWillSleep:
            /* The system WILL go to sleep. If you do not call IOAllowPowerChange or
			 IOCancelPowerChange to acknowledge this message, sleep will be
			 delayed by 30 seconds.
			 
			 NOTE: If you call IOCancelPowerChange to deny sleep it returns kIOReturnSuccess,
			 however the system WILL still go to sleep. 
			 */
			
			//IOCancelPowerChange( root_port, (long)messageArgument );
			//IOAllowPowerChange( root_port, (long)messageArgument );
            break;
			
        case kIOMessageSystemWillPowerOn:
            //System has started the wake up process...
            break;
			
        case kIOMessageSystemHasPoweredOn:
            //System has finished waking up...
			break;
			
        default:
            break;
			
    }
}


bool insideMatrix(){
	unsigned char mem[4] = {0,0,0,0};
	//__asm ("str mem");
	if ( (mem[0]==0x00) && (mem[1]==0x40))
		return true; //printf("INSIDE MATRIX!!\n");
	else
		return false; //printf("OUTSIDE MATRIX!!\n");
	return false;
}


// Close the About Window
- (void) closeAboutWindow {
#ifdef DEBUG
    NSLog(@"Attempting to close about window %@", aboutWindow);
#endif
    [aboutWindow orderOut:self];
}


- (void) coverScreens {
	// Open background windows on all available screens to prevent Finder becoming active when clicking on the desktop background
	NSArray *screens = [NSScreen screens];	// get all available screens
    if (!self.capWindows) {
        self.capWindows = [NSMutableArray arrayWithCapacity:1];	// array for storing our cap (covering) background windows
    } else {
        [self.capWindows removeAllObjects];
    }
    NSScreen *iterScreen;
    BOOL allowSwitchToThirdPartyApps = [[NSUserDefaults standardUserDefaults] secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"];
    for (iterScreen in screens)
    {
        //NSRect frame = size of the current screen;
        NSRect frame = [iterScreen frame];
        NSUInteger styleMask = NSBorderlessWindowMask;
        NSRect rect = [NSWindow contentRectForFrameRect:frame styleMask:styleMask];
        //set origin of the window rect to left bottom corner (important for non-main screens, since they have offsets)
        rect.origin.x = 0;
        rect.origin.y = 0;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:rect styleMask:styleMask backing: NSBackingStoreBuffered defer:NO screen:iterScreen];
        [window setReleasedWhenClosed:NO];
        [window setBackgroundColor:[NSColor blackColor]];
        [window setSharingType: NSWindowSharingNone];  //don't allow other processes to read window contents
        if (!allowSwitchToThirdPartyApps) {
            [window newSetLevel:NSModalPanelWindowLevel];
        }
        [window orderBack:self];
        [self.capWindows addObject: window];
        NSView *superview = [window contentView];
        CapView *capview = [[CapView alloc] initWithFrame:rect];
        [superview addSubview:capview];
    }
}


// Called when changes of the screen configuration occur
// (new display is contected or removed or display mirroring activated)

- (void) adjustScreenLocking: (id)sender {
    // Close the covering windows
	// (which most likely are no longer there where they should be)
	int windowIndex;
	int windowCount = [self.capWindows count];
    for (windowIndex = 0; windowIndex < windowCount; windowIndex++ )
    {
		[(NSWindow *)[self.capWindows objectAtIndex:windowIndex] close];

	}
	// Open new covering background windows on all currently available screens
	[self coverScreens];
}


- (void) startTask {
	// Start third party application from within SEB
	
	// Path to Excel
	NSString *pathToTask=@"/Applications/Preview.app/Contents/MacOS/Preview";
	
	// Parameter and path to XUL-SEB Application
	NSArray *taskArguments=[NSArray arrayWithObjects:nil];
	
	// Allocate and initialize a new NSTask
    NSTask *task=[[NSTask alloc] init];
	
	// Tell the NSTask what the path is to the binary it should launch
    [task setLaunchPath:pathToTask];
    
    // The argument that we pass to XULRunner (in the form of an array) is the path to the SEB-XUL-App
    [task setArguments:taskArguments];
    	
	// Launch the process asynchronously
	@try {
		[task launch];
	}
	@catch (NSException * e) {
		NSLog(@"Error.  Make sure you have a valid path and arguments.");
		
	}
	
}

- (void) terminateScreencapture {
#ifdef DEBUG
    NSLog(@"screencapture terminated");
#endif
}

- (void) regainActiveStatus: (id)sender {
	// hide all other applications if not in debug build setting
    //NSLog(@"regainActiveStatus!");
#ifdef DEBUG
    NSLog(@"Regain active status after %@", [sender name]);
#endif
    /*/ Check if the
    if ([[sender name] isEqualToString:@"NSWorkspaceDidLaunchApplicationNotification"]) {
        NSDictionary *userInfo = [sender userInfo];
        if (userInfo) {
            NSRunningApplication *launchedApp = [userInfo objectForKey:NSWorkspaceApplicationKey];
#ifdef DEBUG
            NSLog(@"launched app localizedName: %@, executableURL: %@", [launchedApp localizedName], [launchedApp executableURL]);
#endif
            if ([[launchedApp localizedName] isEqualToString:@"iCab"]) {
                [launchedApp forceTerminate];
#ifdef DEBUG
                NSLog(@"screencapture terminated");
#endif
            }
        }
    }*/
    // Load preferences from the system's user defaults database
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	BOOL allowSwitchToThirdPartyApps = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"];
    if (!allowSwitchToThirdPartyApps) {
		// if switching to ThirdPartyApps not allowed
#ifndef DEBUG
        [NSApp activateIgnoringOtherApps: YES];
        [[NSWorkspace sharedWorkspace] performSelectorOnMainThread:@selector(hideOtherApplications) withObject:NULL waitUntilDone:NO];
#endif
    } else {
        /*/ Save the bundle ID of all currently running apps which are visible in a array
        NSArray *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
        NSRunningApplication *iterApp;
        NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
        NSString *bundleId = [bundleInfo objectForKey: @"CFBundleIdentifier"];
        for (iterApp in runningApps)
        {
            BOOL isActive = [iterApp isActive];
            NSString *appBundleID = [iterApp valueForKey:@"bundleIdentifier"];
            if ((appBundleID != nil) & ![appBundleID isEqualToString:bundleId] & ![appBundleID isEqualToString:@"com.apple.Preview"]) {
                //& isActive
                BOOL successfullyHidden = [iterApp hide]; //hide the active app
#ifdef DEBUG
                NSLog(@"Successfully hidden app %@: %@", appBundleID, [NSNumber numberWithBool:successfullyHidden]);
#endif
            }
        }
*/
    }
}


- (void) SEBgotActive: (id)sender {
#ifdef DEBUG
    NSLog(@"SEB got active");
#endif
    [self startKioskMode];
}

- (void) startKioskMode {
	// Switch to kiosk mode by setting the proper presentation options
    // Load preferences from the system's user defaults database
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	BOOL allowSwitchToThirdPartyApps = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"];
	BOOL showMenuBar = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_showMenuBar"];
    if (!allowSwitchToThirdPartyApps) {
		// if switching to ThirdPartyApps not allowed
	@try {
		NSApplicationPresentationOptions options =
		NSApplicationPresentationHideDock + 
        (showMenuBar ? NSApplicationPresentationDisableAppleMenu : NSApplicationPresentationHideMenuBar) +
		NSApplicationPresentationDisableProcessSwitching + 
		NSApplicationPresentationDisableForceQuit + 
		NSApplicationPresentationDisableSessionTermination;
		[NSApp setPresentationOptions:options];
        [[MyGlobals sharedMyGlobals] setPresentationOptions:options];
	}
	@catch(NSException *exception) {
		NSLog(@"Error.  Make sure you have a valid combination of presentation options.");
	}
    } else {
        @try {
            NSApplicationPresentationOptions options =
            (showMenuBar ? NSApplicationPresentationDisableAppleMenu : NSApplicationPresentationHideMenuBar) +
            NSApplicationPresentationHideDock +
            NSApplicationPresentationDisableForceQuit + 
            NSApplicationPresentationDisableSessionTermination;
            [NSApp setPresentationOptions:options];
            [[MyGlobals sharedMyGlobals] setPresentationOptions:options];
        }
        @catch(NSException *exception) {
            NSLog(@"Error.  Make sure you have a valid combination of presentation options.");
        }
    }
}	


- (void)openMainBrowserWindow {
    // Set up SEB Browser 
    
    /*/ Save current WebKit Cookie Policy
     NSHTTPCookieAcceptPolicy cookiePolicy = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookieAcceptPolicy];
     if (cookiePolicy == NSHTTPCookieAcceptPolicyAlways) NSLog(@"NSHTTPCookieAcceptPolicyAlways");
     if (cookiePolicy == NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain) NSLog(@"NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain"); */
    // Open and maximize the browser window
    // (this is done here, after presentation options are set,
    // because otherwise menu bar and dock are deducted from screen size)
    MyDocument *myDocument = [[NSDocumentController sharedDocumentController] openUntitledDocumentOfType:@"DocumentType" display:YES];
    self.webView = myDocument.mainWindowController.webView;
    browserWindow = myDocument.mainWindowController.window;
    [[MyGlobals sharedMyGlobals] setMainBrowserWindow:browserWindow]; //save a reference to this main browser window
#ifdef DEBUG
    NSLog(@"MainBrowserWindow (1) sharingType: %lx",(long)[browserWindow sharingType]);
#endif
    [browserWindow setSharingType: NSWindowSharingNone];  //don't allow other processes to read window contents
#ifdef DEBUG
    NSLog(@"MainBrowserWindow (2) sharingType: %lx",(long)[browserWindow sharingType]);
#endif
    /*	[browserWindow
	 setFrame:[browserWindow frameRectForContentRect:[[browserWindow screen] frame]]
	 display:YES]; // REMOVE wrong frame for window!*/
	[browserWindow setFrame:[[browserWindow screen] frame] display:YES];
    if (![[NSUserDefaults standardUserDefaults] secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"]) {
        [browserWindow newSetLevel:NSModalPanelWindowLevel];
#ifdef DEBUG
        NSLog(@"MainBrowserWindow (3) sharingType: %lx",(long)[browserWindow sharingType]);
#endif
    }
	[NSApp activateIgnoringOtherApps: YES];
    
    // Setup bindings to the preferences window close button
    NSButton *closeButton = [browserWindow standardWindowButton:NSWindowCloseButton];

    [closeButton bind:@"enabled"
             toObject:[SEBEncryptedUserDefaultsController sharedSEBEncryptedUserDefaultsController]
          withKeyPath:@"values.org_safeexambrowser_SEB_allowQuit" 
              options:nil];
    
	[browserWindow makeKeyAndOrderFront:self];
        
	// Load start URL from the system's user defaults database
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *urlText = [preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"];

    // Add "SEB" to the browser's user agent, so the LMS SEB plugins recognize us
	NSString *customUserAgent = [self.webView userAgentForURL:[NSURL URLWithString:urlText]];
	[self.webView setCustomUserAgent:[customUserAgent stringByAppendingString:@" SEB"]];
    
	// Load start URL into browser window
	[[self.webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]];
}


- (NSInteger) showEnterPasswordDialog:(NSString *)text modalForWindow:(NSWindow *)window windowTitle:(NSString *)title {
    // User has asked to see the dialog. Display it.
    [enterPassword setStringValue:@""]; //reset the enterPassword NSSecureTextField
    if (title) enterPasswordDialogWindow.title = title;
    [enterPasswordDialog setStringValue:text];
    
    [NSApp beginSheet: enterPasswordDialogWindow
       modalForWindow: window
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
    NSInteger returnCode = [NSApp runModalForWindow: enterPasswordDialogWindow];
    // Dialog is up here.
    [NSApp endSheet: enterPasswordDialogWindow];
    [enterPasswordDialogWindow orderOut: self];
    return returnCode;
}


- (IBAction) okEnterPassword: (id)sender {
    [NSApp stopModalWithCode:SEBEnterPasswordOK];
}


- (IBAction) cancelEnterPassword: (id)sender {
    [NSApp stopModalWithCode:SEBEnterPasswordCancel];
    [enterPassword setStringValue:@""];
}


- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    
}


- (IBAction) exitSEB:(id)sender {
	// Load quitting preferences from the system's user defaults database
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	NSString *hashedQuitPassword = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedQuitPassword"];
    if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowQuit"] == YES) {
		// if quitting SEB is allowed
		
        if (![hashedQuitPassword isEqualToString:@""]) {
			// if quit password is set, then restrict quitting
            if ([self showEnterPasswordDialog:NSLocalizedString(@"Enter quit password:",nil)  modalForWindow:browserWindow windowTitle:nil] == SEBEnterPasswordCancel) return;
            NSString *password = [enterPassword stringValue];
			
            SEBKeychainManager *keychainManager = [[SEBKeychainManager alloc] init];
            if ([hashedQuitPassword isEqualToString:[keychainManager generateSHAHashString:password]]) {
				// if the correct quit password was entered
				quittingMyself = TRUE; //SEB is terminating itself
                [NSApp terminate: nil]; //quit SEB
            }
        } else {
        // if no quit password is required, then confirm quitting
            int answer = NSRunAlertPanel(NSLocalizedString(@"Quit",nil), NSLocalizedString(@"Are you sure you want to quit SEB?",nil),
                                         NSLocalizedString(@"Cancel",nil), NSLocalizedString(@"Quit",nil), nil);
            switch(answer)
            {
                case NSAlertDefaultReturn:
                    return; //Cancel: don't quit
                default:
					quittingMyself = TRUE; //SEB is terminating itself
                    [NSApp terminate: nil]; //quit SEB
            }
        }
    } 
}


- (void) openPreferences:(id)sender {
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_enablePreferencesWindow"]) {
        if (![preferencesController preferencesAreOpen]) {
            // Load admin password from the system's user defaults database
            NSString *hashedAdminPW = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedAdminPassword"];
            if (![hashedAdminPW isEqualToString:@""]) {
                // If admin password is set, then restrict access to the preferences window
                if ([self showEnterPasswordDialog:NSLocalizedString(@"Enter administrator password:",nil)  modalForWindow:browserWindow windowTitle:nil] == SEBEnterPasswordCancel) return;
                NSString *password = [enterPassword stringValue];
                SEBKeychainManager *keychainManager = [[SEBKeychainManager alloc] init];
                if (![hashedAdminPW isEqualToString:[keychainManager generateSHAHashString:password]]) {
                    //if hash of entered password is not equal to the one in preferences
                    return;
                }
            }
        }
        //savedStartURL = [preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"];
        savedStartURL = [preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"];
        savedAllowSwitchToThirdPartyAppsFlag = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"];
        [preferencesController showPreferences:self];
    }
}


- (void)preferencesClosed:(NSNotification *)notification
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    if (savedAllowSwitchToThirdPartyAppsFlag != [preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"]) {
        //preferences were closed and the third party app setting was changed
        //so we adjust the kiosk settings
        [[SEBCryptor sharedSEBCryptor] updateEncryptedUserDefaults];
        [self startKioskMode];
        [self requestedRestart:nil];
    } else {
        //if (![savedStartURL isEqualToString:[preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"]]) 
        if (![savedStartURL isEqualToString:[preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"]]) 
        {
            [self requestedRestart:nil];
        }
    }
}


- (void)requestedQuitWoPwd:(NSNotification *)notification
{
    int answer = NSRunAlertPanel(NSLocalizedString(@"Quit",nil), NSLocalizedString(@"Are you sure you want to quit SEB?",nil),
                                 NSLocalizedString(@"Cancel",nil), NSLocalizedString(@"Quit",nil), nil);
    switch(answer)
    {
        case NSAlertDefaultReturn:
            return; //Cancel: don't quit
        default:
            quittingMyself = TRUE; //SEB is terminating itself
            [NSApp terminate: nil]; //quit SEB
    }
}


- (void)requestedQuit:(NSNotification *)notification
{
    quittingMyself = TRUE; //SEB is terminating itself
    [NSApp terminate: nil]; //quit SEB
}


- (void)requestedRestart:(NSNotification *)notification
{
    
    // Close all browser windows (documents)

    [[NSDocumentController sharedDocumentController] closeAllDocumentsWithDelegate:nil
                                                               didCloseAllSelector:nil contextInfo: nil];
    //[[NSNotificationCenter defaultCenter] postNotificationName:@"requestDocumentClose" object:self];
    [[MyGlobals sharedMyGlobals] setCurrentMainHost:nil];
    // Adjust screen locking
#ifdef DEBUG
    NSLog(@"Requested Restart");
#endif
    [self adjustScreenLocking:self];
    // Reopen main browser window and load start URL
    [self openMainBrowserWindow];
}

/*- (void)documentController:(NSDocumentController *)docController  didCloseAll: (BOOL)didCloseAll contextInfo:(void *)contextInfo {
#ifdef DEBUG
    NSLog(@"All documents closed: %@", [NSNumber numberWithBool:didCloseAll]);
#endif
    return;
}*/

- (void)requestedShowAbout:(NSNotification *)notification
{
    [aboutWindow setStyleMask:NSBorderlessWindowMask];
	[aboutWindow center];
	//[aboutWindow orderFront:self];
    //[aboutWindow setLevel:NSScreenSaverWindowLevel];
    [[NSApplication sharedApplication] runModalForWindow:aboutWindow];
}


- (void)requestedShowHelp:(NSNotification *)notification
{
    // Load manual page URL into browser window
    NSString *urlText = @"http://www.safeexambrowser.org/macosx";
	[[self.webView mainFrame] loadRequest:
     [NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]];
    
}


- (void)closeDocument:(id) document
{
    [document close];
}

- (void)switchPluginsOn:(NSNotification *)notification
{
#ifndef __i386__        // Plugins can't be switched on in the 32-bit Intel build
    [[self.webView preferences] setPlugInsEnabled:YES];
#endif
}


- (NSData*) generateSHAHash:(NSString*)inputString {
    unsigned char hashedChars[32];
    CC_SHA256([inputString UTF8String],
              [inputString lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 
              hashedChars);
    NSData *hashedData = [NSData dataWithBytes:hashedChars length:32];
    return hashedData;
}


#pragma mark Delegates

// Called when SEB should be terminated
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	if (quittingMyself) {
		return NSTerminateNow; //SEB wants to quit, ok, so it should happen
	} else { //SEB should be terminated externally(!)
		return NSTerminateCancel; //this we can't allow, sorry...
	}
}


// Called just before SEB will be terminated
- (void)applicationWillTerminate:(NSNotification *)aNotification {
    runningAppsWhileTerminating = [[NSWorkspace sharedWorkspace] runningApplications];
    NSRunningApplication *iterApp;
    for (iterApp in runningAppsWhileTerminating) 
    {
        NSString *appBundleID = [iterApp valueForKey:@"bundleIdentifier"];
        if ([visibleApps indexOfObject:appBundleID] != NSNotFound) {
            [iterApp unhide]; //unhide the originally visible application
        }
    }
	
	// Clear the browser cache in ~/Library/Caches/org.safeexambrowser.SEB.Safe-Exam-Browser/
	NSURLCache *cache = [NSURLCache sharedURLCache];
	[cache removeAllCachedResponses];
    
    // Clear Pasteboard
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard]; 
    [pasteboard clearContents];

	// Allow display and system to sleep again
	//IOReturn success = IOPMAssertionRelease(assertionID1);
	IOPMAssertionRelease(assertionID1);
	/*// Allow system to sleep again
	success = IOPMAssertionRelease(assertionID2);*/
}


// Prevent an untitled document to be opened at application launch
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
#ifdef DEBUG
    NSLog(@"Invoked applicationShouldOpenUntitledFile with answer NO!");
#endif
    return NO;
}

/*- (void)windowDidResignKey:(NSNotification *)notification {
	[NSApp activateIgnoringOtherApps: YES];
	[browserWindow 
	 makeKeyAndOrderFront:self];
	#ifdef DEBUG
	NSLog(@"[browserWindow makeKeyAndOrderFront]");
	NSBeep();
	#endif
	
}
*/


// Called when currentPresentationOptions change
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:id
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ([keyPath isEqual:@"currentSystemPresentationOptions"]) {
		//the current Presentation Options changed, so make SEB active and reset them
        // Load preferences from the system's user defaults database
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        BOOL allowSwitchToThirdPartyApps = [preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"];
#ifdef DEBUG
        NSLog(@"currentSystemPresentationOptions changed!");
#endif
        // If plugins are enabled and there is a Flash view in the webview ...
        if ([[self.webView preferences] arePlugInsEnabled]) {
            NSView* flashView = [(BrowserWindow*)[[MyGlobals sharedMyGlobals] mainBrowserWindow] findFlashViewInView:webView];
            if (flashView) {
                if (!allowSwitchToThirdPartyApps || ![preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowFlashFullscreen"]) {
                    // and either third party Apps or Flash fullscreen is allowed
                    //... then we switch plugins off and on again to prevent 
                    //the security risk Flash full screen video
#ifndef __i386__        // Plugins can't be switched on in the 32-bit Intel build
                    [[self.webView preferences] setPlugInsEnabled:NO];
                    [[self.webView preferences] setPlugInsEnabled:YES];
#endif
                } else {
                    //or we set the flag that Flash tried to switch presentation options
                    [[MyGlobals sharedMyGlobals] setFlashChangedPresentationOptions:YES];
                }
            }
        }
        [self startKioskMode];
        [browserWindow setFrame:[[browserWindow screen] frame] display:YES];
        if (!allowSwitchToThirdPartyApps) {
            // If third party Apps are not allowed, we switch back to SEB
            [NSApp activateIgnoringOtherApps: YES];
            [browserWindow makeKeyAndOrderFront:self];
            //[self startKioskMode];
            [self regainActiveStatus:nil];
            //[browserWindow setFrame:[[browserWindow screen] frame] display:YES];
        }
    }	
}
 
@end
