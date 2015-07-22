//
//  AppDelegate.m
//  test2
//
//  Created by Alari on 9/15/13.
//  Copyright (c) 2013 TogglDesktop developers. All rights reserved.
//

#import "AppDelegate.h"

#import "AboutWindowController.h"
#import "AutocompleteItem.h"
#import "AutotrackerRuleItem.h"
#import "Bugsnag.h"
#import "ConsoleViewController.h"
#import "CrashReporter.h"
#import "DisplayCommand.h"
#import "FeedbackWindowController.h"
#import "IdleEvent.h"
#import "IdleNotificationWindowController.h"
#import "MASShortcut+UserDefaults.h"
#import "MainWindowController.h"
#import "MenuItemTags.h"
#import "PreferencesWindowController.h"
#import "Settings.h"
#import "Sparkle.h"
#import "TimeEntryViewItem.h"
#import "UIEvents.h"
#import "Utils.h"
#import "ViewItem.h"
#import "idler.h"
#import "toggl_api.h"

@interface AppDelegate ()
@property (nonatomic, strong) IBOutlet MainWindowController *mainWindowController;
@property (nonatomic, strong) IBOutlet PreferencesWindowController *preferencesWindowController;
@property (nonatomic, strong) IBOutlet AboutWindowController *aboutWindowController;
@property (nonatomic, strong) IBOutlet IdleNotificationWindowController *idleNotificationWindowController;
@property (nonatomic, strong) IBOutlet FeedbackWindowController *feedbackWindowController;
@property (nonatomic, strong) IBOutlet ConsoleViewController *consoleWindowController;

// Remember some app state
@property TimeEntryViewItem *lastKnownRunningTimeEntry;
@property BOOL lastKnownOnlineState;
@property uint64_t lastKnownUserID;

// We'll change app icon in the tray. So keep the different state images handy
@property NSMutableDictionary *statusImages;

// Timers to update app state
@property NSTimer *menubarTimer;
@property NSTimer *idleTimer;

// We'll be updating running TE as a menu item, too
@property (strong) IBOutlet NSMenuItem *runningTimeEntryMenuItem;

// We'll add user email once userdata has been loaded
@property (strong) IBOutlet NSMenuItem *currentUserEmailMenuItem;

// Where logs are written and db is kept
@property NSString *app_path;
@property NSString *db_path;
@property NSString *log_path;
@property NSString *log_level;
@property NSString *scriptPath;

// Environment (development, production, etc)
@property NSString *environment;

@property NSString *version;

// For testing crash reporter
@property BOOL forceCrash;

// Avoid doing stuff when app is already shutting down
@property BOOL willTerminate;

// Show or not show menubar timer
@property BOOL showMenuBarTimer;

// Show or not show menubar project
@property BOOL showMenuBarProject;

// Manual mode
@property NSMenuItem *manualModeMenuItem;

@end

@implementation AppDelegate

void *ctx;
BOOL manualMode = NO;

- (void)applicationWillFinishLaunching:(NSNotification *)not
{
	self.willTerminate = NO;
	self.lastKnownOnlineState = YES;
	self.lastKnownUserID = 0;
	self.showMenuBarTimer = NO;

	if ([self updateCheckEnabled])
	{
		[[SUUpdater sharedUpdater] setAutomaticallyDownloadsUpdates:YES];

		NSAssert(ctx, @"ctx is not initialized, cannot continue");
		char *str = toggl_get_update_channel(ctx);
		NSAssert(str, @"Could not read update channel value");
		NSString *channel = [NSString stringWithUTF8String:str];
		free(str);
		[Utils setUpdaterChannel:channel];
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSLog(@"applicationDidFinishLaunching");

	if (![self.environment isEqualToString:@"production"] && ![self.version isEqualToString:@"7.0.0"])
	{
		// Turn on UI constraint debugging, if not in production
		[[NSUserDefaults standardUserDefaults] setBool:YES
												forKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
	}

	self.mainWindowController = [[MainWindowController alloc] initWithWindowNibName:@"MainWindowController"];
	[self.mainWindowController.window setReleasedWhenClosed:NO];

	PLCrashReporter *crashReporter = [self configuredCrashReporter];

	// Check if we previously crashed
	if ([crashReporter hasPendingCrashReport])
	{
		[self handleCrashReport];
	}

	// Enable the Crash Reporter
	NSError *error;
	if (![crashReporter enableCrashReporterAndReturnError:&error])
	{
		NSLog(@"Warning: Could not enable crash reporter: %@", error);
	}

	if (self.forceCrash)
	{
		abort();
	}

	if (!wasLaunchedAsHiddenLoginItem())
	{
		[self onShowMenuItem:self];
	}

	self.activeAppIcon = [NSImage imageNamed:@"app"];
	[self.activeAppIcon setTemplate:YES];

	self.preferencesWindowController = [[PreferencesWindowController alloc]
										initWithWindowNibName:@"PreferencesWindowController"];

	self.aboutWindowController = [[AboutWindowController alloc]
								  initWithWindowNibName:@"AboutWindowController"];

	self.idleNotificationWindowController = [[IdleNotificationWindowController alloc]
											 initWithWindowNibName:@"IdleNotificationWindowController"];

	self.feedbackWindowController = [[FeedbackWindowController alloc]
									 initWithWindowNibName:@"FeedbackWindowController"];

	[self createStatusItem];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayIdleNotification:)
												 name:kDisplayIdleNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startStop:)
												 name:kCommandStop
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startNew:)
												 name:kCommandNew
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startNewShortcut:)
												 name:kCommandNewShortcut
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startContinueTimeEntry:)
												 name:kCommandContinue
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayApp:)
												 name:kDisplayApp
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayOnlineState:)
												 name:kDisplayOnlineState
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplaySyncState:)
												 name:kDisplaySyncState
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayUnsyncedItems:)
												 name:kDisplayUnsyncedItems
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayTimerState:)
												 name:kDisplayTimerState
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayLogin:)
												 name:kDisplayLogin
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplaySettings:)
												 name:kDisplaySettings
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDisplayPromotion:)
												 name:kDisplayPromotion
											   object:nil];

	toggl_set_environment(ctx, [self.environment UTF8String]);

	bool_t started = toggl_ui_start(ctx);
	NSAssert(started, @"Failed to start UI");

	[MASShortcut registerGlobalShortcutWithUserDefaultsKey:kPreferenceGlobalShortcutShowHide handler:^{
		 if ([[NSApplication sharedApplication] isActive] && [self.mainWindowController.window isVisible])
		 {
			 [self.mainWindowController.window close];
		 }
		 else
		 {
			 [self onShowMenuItem:self];
		 }
	 }];

	[MASShortcut registerGlobalShortcutWithUserDefaultsKey:kPreferenceGlobalShortcutStartStop handler:^{
		 if (self.lastKnownRunningTimeEntry == nil)
		 {
			 [self onContinueMenuItem:self];
		 }
		 else
		 {
			 [self onStopMenuItem:self];
		 }
	 }];

	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
														   selector:@selector(receiveSleepNote:)
															   name:NSWorkspaceWillSleepNotification object:NULL];

	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
														   selector:@selector(receiveWakeNote:)
															   name:NSWorkspaceDidWakeNotification object:NULL];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reachabilityChanged:)
												 name:kReachabilityChangedNotification
											   object:nil];

	self.reach = [Reachability reachabilityForInternetConnection];
	[self.reach startNotifier];

	if ([self updateCheckEnabled])
	{
		[[SUUpdater sharedUpdater] setDelegate:self.aboutWindowController];
		[[SUUpdater sharedUpdater] checkForUpdatesInBackground];
	}

	if (self.scriptPath)
	{
		[self performSelectorInBackground:@selector(runScript:)
							   withObject:self.scriptPath];
	}
}

- (void)runScript:(NSString *)scriptFile
{
	NSString *script = [NSString stringWithContentsOfFile:scriptFile encoding:NSUTF8StringEncoding error:nil];
	ScriptResult *result = [Utils runScript:script];

	if (result && !result.err)
	{
		[[NSApplication sharedApplication] terminate:self];
	}
}

- (BOOL)updateCheckEnabled
{
	if (self.scriptPath)
	{
		return NO;
	}

	if (![self.environment isEqualToString:@"production"])
	{
		return NO;
	}

	NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];

	return [infoDict[@"KopsikCheckForUpdates"] boolValue];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
	 shouldPresentNotification:(NSUserNotification *)notification
{
	return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
	   didActivateNotification:(NSUserNotification *)notification
{
	NSLog(@"didActivateNotification %@", notification);

	// handle autotracker notification
	if (notification && notification.userInfo && notification.userInfo[@"autotracker"] != nil)
	{
		if (NSUserNotificationActivationTypeActionButtonClicked == notification.activationType)
		{
			NSNumber *project_id = notification.userInfo[@"project_id"];
			char_t *guid = toggl_start(ctx, "", "", 0, project_id.longValue, 0);
			free(guid);
		}
		return;
	}

	// handle other notifications; we only have reminder at the moment
	[self onShowMenuItem:self];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
		didDeliverNotification:(NSUserNotification *)notification
{
	NSLog(@"didDeliverNotification %@", notification);
}

- (void)receiveSleepNote:(NSNotification *)note
{
	NSLog(@"receiveSleepNote: %@", [note name]);
	toggl_set_sleep(ctx);
}

- (void)receiveWakeNote:(NSNotification *)note
{
	NSLog(@"receiveWakeNote: %@", [note name]);
	toggl_set_wake(ctx);
}

- (void)startNew:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(new:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)new:(TimeEntryViewItem *)new_time_entry
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");
	NSAssert(new_time_entry != nil, @"new time entry details cannot be nil");

	char *guid = toggl_start(ctx,
							 [new_time_entry.Description UTF8String],
							 [new_time_entry.duration UTF8String],
							 new_time_entry.TaskID,
							 new_time_entry.ProjectID,
							 0);
	free(guid);
}

- (void)startNewShortcut:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(newShortcut:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)newShortcut:(TimeEntryViewItem *)new_time_entry
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");
	NSAssert(new_time_entry != nil, @"new time entry details cannot be nil");

	char *guid = toggl_start(ctx,
							 [new_time_entry.Description UTF8String],
							 [new_time_entry.duration UTF8String],
							 new_time_entry.TaskID,
							 new_time_entry.ProjectID,
							 0);
	toggl_edit(ctx, guid, true, "");
	free(guid);
}

- (void)startContinueTimeEntry:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(continueTimeEntry:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)continueTimeEntry:(NSString *)guid
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	if (guid == nil)
	{
		toggl_continue_latest(ctx);
	}
	else
	{
		toggl_continue(ctx, [guid UTF8String]);
	}
}

- (void)startStop:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(stop)
						   withObject:nil
						waitUntilDone:NO];
}

- (void)stop
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	toggl_stop(ctx);
}

- (void)startDisplaySettings:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displaySettings:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displaySettings:(DisplayCommand *)cmd
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	// Start idle detection, if its enabled
	if (cmd.settings.idle_detection)
	{
		NSLog(@"Starting idle detection");
		if (!self.idleTimer)
		{
			self.idleTimer = [NSTimer
							  scheduledTimerWithTimeInterval:1.0
													  target:self
													selector:@selector(idleTimerFired:)
													userInfo:nil
													 repeats:YES];
		}
	}
	else
	{
		NSLog(@"Idle detection is disabled. Stopping idle detection.");
		if (self.idleTimer != nil)
		{
			[self.idleTimer invalidate];
			self.idleTimer = nil;
		}
	}


	// Start menubar timer if its enabled
	self.showMenuBarTimer = cmd.settings.menubar_timer;
	if (cmd.settings.menubar_timer)
	{
		NSLog(@"Starting menubar timer");
		if (!self.menubarTimer)
		{
			self.menubarTimer = [NSTimer
								 scheduledTimerWithTimeInterval:1.0
														 target:self
													   selector:@selector(menubarTimerFired:)
													   userInfo:nil
														repeats:YES];
		}
	}
	else
	{
		NSLog(@"Menubar timer is disabled. Stopping menubar timer.");
		if (self.menubarTimer != nil)
		{
			[self.menubarTimer invalidate];
			self.menubarTimer = nil;
		}
		[self updateStatusItem];
	}

	// Show/Hide project in menubar
	self.showMenuBarProject = cmd.settings.menubar_project;

	// Show/Hide dock icon
	ProcessSerialNumber psn = { 0, kCurrentProcess };
	if (cmd.settings.dock_icon)
	{
		NSLog(@"Showing dock icon");
		TransformProcessType(&psn, kProcessTransformToForegroundApplication);
	}
	else
	{
		NSLog(@"Hiding dock icon.");
		TransformProcessType(&psn, kProcessTransformToUIElementApplication);
	}

	// Stay on top
	if (cmd.settings.on_top)
	{
		[self.mainWindowController.window setLevel:NSFloatingWindowLevel];
	}
	else
	{
		[self.mainWindowController.window setLevel:NSNormalWindowLevel];
	}

	if (cmd.open)
	{
		self.preferencesWindowController.originalCmd = cmd;
		self.preferencesWindowController.user_id = self.lastKnownUserID;
		[self.preferencesWindowController showWindow:self];
		[NSApp activateIgnoringOtherApps:YES];
	}

	NSString *mode = kToggleTimerMode;
	manualMode = cmd.settings.manual_mode;
	if (cmd.settings.manual_mode)
	{
		mode = kToggleManualMode;
		[self.manualModeMenuItem setTitle:@"Use timer"];
	}
	else
	{
		[self.manualModeMenuItem setTitle:@"Use manual mode"];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:mode
														object:nil];
}

- (void)startDisplayApp:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayApp:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayApp:(DisplayCommand *)cmd
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");
	if (cmd.open)
	{
		[self onShowMenuItem:self];
	}
}

- (void)startDisplayPromotion:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayPromotion:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayPromotion:(NSNumber *)promotion_type
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	NSAlert *alert = [[NSAlert alloc] init];
	[alert addButtonWithTitle:@"Let's do it!"];
	[alert addButtonWithTitle:@"No thanks"];
	[alert setMessageText:@"Join Team Beta?"];
	[alert setInformativeText:@"Hi there! Would you like to join Toggl Desktop Beta program to get cool gear and check out the hot new features as they come out of the oven?"];
	[alert setAlertStyle:NSInformationalAlertStyle];
	NSInteger result = [alert runModal];

	toggl_set_promotion_response(ctx, promotion_type.intValue, NSAlertFirstButtonReturn == result);
}

- (void)startDisplayLogin:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayLogin:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayLogin:(DisplayCommand *)cmd
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	self.lastKnownUserID = cmd.user_id;

	if (!self.lastKnownUserID)
	{
		// maybe its running, but we dont know any more
		[self indicateStoppedTimer];
	}
	// Set email address
	char *str = toggl_get_user_email(ctx);
	NSString *email = [NSString stringWithUTF8String:str];
	free(str);
	[self.currentUserEmailMenuItem setTitle:email];
}

- (void)startDisplayOnlineState:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayOnlineState:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayOnlineState:(NSNumber *)state
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	self.lastKnownOnlineState = ![state intValue];
	[self updateStatusItem];
}

- (void)startDisplaySyncState:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displaySyncState:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displaySyncState:(NSNumber *)state
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	if ([state intValue])
	{
		// FIXME: display syncing spinner
	}
	else
	{
		// FIXME: hide syncing spinner
	}
}

- (void)startDisplayUnsyncedItems:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayUnsyncedItems:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayUnsyncedItems:(NSNumber *)count
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	NSLog(@"displayUnsyncedItems %d", [count intValue]);

	// FIXME: hide/show number of unsynced time entries
}

- (void)updateStatusItem
{
	NSString *title = @"";

	if (self.lastKnownRunningTimeEntry && self.lastKnownUserID)
	{
		if (self.showMenuBarProject)
		{
			title = [title stringByAppendingString:self.lastKnownRunningTimeEntry.ProjectLabel];
		}

		if (self.showMenuBarTimer)
		{
			char *str = toggl_format_tracked_time_duration(self.lastKnownRunningTimeEntry.duration_in_seconds);

			if (self.showMenuBarProject)
			{
				title = [NSString stringWithFormat:@"%@ (%@)", title, [NSString stringWithUTF8String:str]];
			}
			else
			{
				title = [title stringByAppendingString:[NSString stringWithUTF8String:str]];
			}

			free(str);
		}
	}

	NSString *key = nil;
	if (self.lastKnownRunningTimeEntry && self.lastKnownUserID)
	{
		if (self.lastKnownOnlineState)
		{
			key = @"on";
		}
		else
		{
			key = @"offline_on";
		}
	}
	else
	{
		if (self.lastKnownOnlineState)
		{
			key = @"off";
		}
		else
		{
			key = @"offline_off";
		}
	}
	NSImage *image = [self.statusImages objectForKey:key];
	NSAssert(image, @"status image not found!");

	if (![title isEqualToString:self.statusItem.title])
	{
		[self.statusItem setTitle:title];
	}

	if (image != self.statusItem.image)
	{
		[self.statusItem setImage:image];
	}
}

- (void)startDisplayTimerState:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayTimerState:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayTimerState:(TimeEntryViewItem *)timeEntry
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	self.lastKnownRunningTimeEntry = timeEntry;

	if (!timeEntry)
	{
		if (self.idleNotificationWindowController.window.isVisible)
		{
			[self.idleNotificationWindowController.window orderOut:nil];
		}
	}

	if (timeEntry)
	{
		if (!self.willTerminate)
		{
			[NSApp setApplicationIconImage:self.activeAppIcon];
		}

		[self updateStatusItem];

		// Change tracking time entry row in menu
		if (self.lastKnownRunningTimeEntry.Description
			&& self.lastKnownRunningTimeEntry.Description.length)
		{
			[self.runningTimeEntryMenuItem setTitle:self.lastKnownRunningTimeEntry.Description];
		}
		else
		{
			[self.runningTimeEntryMenuItem setTitle:@"Timer is tracking"];
		}

		return;
	}

	[self indicateStoppedTimer];
}

- (void)indicateStoppedTimer
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	if (!self.willTerminate)
	{
		// Change app dock icon to default
		// See https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/customizing_docktile/dockconcepts.pdf
		[NSApp setApplicationIconImage:nil];
	}

	[self updateStatusItem];

	[self.runningTimeEntryMenuItem setTitle:@"Timer is not tracking"];
}

- (void)createStatusItem
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");
	NSMenu *menu = [[NSMenu alloc] init];
	self.currentUserEmailMenuItem = [menu addItemWithTitle:@""
													action:nil
											 keyEquivalent:@""];
	self.runningTimeEntryMenuItem = [menu addItemWithTitle:@"Timer status"
													action:nil
											 keyEquivalent:@""];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"New"
					action:@selector(onNewMenuItem:)
			 keyEquivalent:@"n"].tag = kMenuItemTagNew;
	[menu addItemWithTitle:@"Continue"
					action:@selector(onContinueMenuItem:)
			 keyEquivalent:@"o"].tag = kMenuItemTagContinue;
	[menu addItemWithTitle:@"Stop"
					action:@selector(onStopMenuItem:)
			 keyEquivalent:@"s"].tag = kMenuItemTagStop;
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"Show"
					action:@selector(onShowMenuItem:)
			 keyEquivalent:@"t"];
	[menu addItemWithTitle:@"Edit"
					action:@selector(onEditMenuItem:)
			 keyEquivalent:@"e"].tag = kMenuItemTagEdit;
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"Sync"
					action:@selector(onSyncMenuItem:)
			 keyEquivalent:@""].tag = kMenuItemTagSync;
	[menu addItemWithTitle:@"Reports"
					action:@selector(onOpenBrowserMenuItem:)
			 keyEquivalent:@""].tag = kMenuItemTagOpenBrowser;
	[menu addItemWithTitle:@"Preferences"
					action:@selector(onPreferencesMenuItem:)
			 keyEquivalent:@""];
	[menu addItemWithTitle:@"Record Timeline"
					action:@selector(onToggleRecordTimeline:)
			 keyEquivalent:@""].tag = kMenuItemRecordTimeline;
	self.manualModeMenuItem = [menu addItemWithTitle:@"Use manual mode"
											  action:@selector(onModeChange:)
									   keyEquivalent:@"d"];
	self.manualModeMenuItem.tag = kMenuItemTagMode;
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"About"
					action:@selector(onAboutMenuItem:)
			 keyEquivalent:@""];
	NSMenuItem *sendFeedbackMenuItem = [menu addItemWithTitle:@"Send Feedback"
													   action:@selector(onSendFeedbackMenuItem)
												keyEquivalent:@""];
	sendFeedbackMenuItem.tag = kMenuItemTagSendFeedback;
	[menu addItemWithTitle:@"Logout"
					action:@selector(onLogoutMenuItem:)
			 keyEquivalent:@""].tag = kMenuItemTagLogout;;
	[menu addItemWithTitle:@"Quit"
					action:@selector(onQuitMenuItem)
			 keyEquivalent:@""];

	NSStatusBar *bar = [NSStatusBar systemStatusBar];

	self.statusImages = [[NSMutableDictionary alloc] init];
	for (NSString *key in @[@"on", @"off", @"offline_on", @"offline_off"])
	{
		NSImage *image = [NSImage imageNamed:key];
		[image setTemplate:YES];
		[self.statusImages setObject:image forKey:key];
	}

	self.statusItem = [bar statusItemWithLength:NSVariableStatusItemLength];
	[self.statusItem setHighlightMode:YES];
	[self.statusItem setEnabled:YES];
	[self.statusItem setMenu:menu];

	[self updateStatusItem];
}

- (IBAction)onConsoleMenuItem:(id)sender
{
	if (!self.consoleWindowController)
	{
		self.consoleWindowController = [[ConsoleViewController alloc]
										initWithWindowNibName:@"ConsoleViewController"];
	}
	[self.consoleWindowController showWindow:self];
}

- (void)onNewMenuItem:(id)sender
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kCommandNewShortcut
														object:[[TimeEntryViewItem alloc] init]];
}

- (void)onSendFeedbackMenuItem
{
	[self.feedbackWindowController showWindow:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)onSendFeedbackMainMenuItem:(id)sender
{
	[self onSendFeedbackMenuItem];
}

- (IBAction)onContinueMenuItem:(id)sender
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kCommandContinue
														object:nil];
}

- (IBAction)onStopMenuItem:(id)sender
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kCommandStop
														object:nil];
}

- (IBAction)onSyncMenuItem:(id)sender
{
	toggl_sync(ctx);
}

- (IBAction)onToggleRecordTimeline:(id)sender
{
	toggl_timeline_toggle_recording(ctx,
									!toggl_timeline_is_recording_enabled(ctx));
}

- (IBAction)onModeChange:(id)sender
{
	manualMode = !manualMode;
	toggl_set_settings_manual_mode(ctx, manualMode);
}

- (IBAction)onOpenBrowserMenuItem:(id)sender
{
	toggl_open_in_browser(ctx);
}

- (IBAction)onHelpMenuItem:(id)sender
{
	toggl_get_support(ctx);
}

- (IBAction)onLogoutMenuItem:(id)sender
{
	toggl_logout(ctx);
}

- (IBAction)onClearCacheMenuItem:(id)sender
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setMessageText:@"Clear local data and log out?"];
	[alert setInformativeText:@"Deleted unsynced time entries cannot be restored."];
	[alert setAlertStyle:NSWarningAlertStyle];
	if ([alert runModal] != NSAlertFirstButtonReturn)
	{
		return;
	}
	toggl_clear_cache(ctx);
}

- (IBAction)onAboutMenuItem:(id)sender
{
	[self.aboutWindowController showWindow:self];
	[self.aboutWindowController checkForUpdates];
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)onShowMenuItem:(id)sender
{
	[self.mainWindowController showWindow:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)onEditMenuItem:(id)sender
{
	[self.mainWindowController showWindow:self];
	toggl_edit(ctx, "", true, "description");
}

- (IBAction)onPreferencesMenuItem:(id)sender
{
	toggl_edit_preferences(ctx);
}

- (IBAction)onHideMenuItem:(id)sender
{
	[self.mainWindowController.window close];
}

- (void)onQuitMenuItem
{
	[[NSApplication sharedApplication] terminate:self];
}

- (void)applicationWillTerminate:(NSNotification *)app
{
	NSLog(@"applicationWillTerminate");
	self.willTerminate = YES;
	[self.reach stopNotifier];
	toggl_context_clear(ctx);
	ctx = 0;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
					hasVisibleWindows:(BOOL)flag
{
	[self.mainWindowController.window setIsVisible:YES];
	return YES;
}

const NSString *appName = @"osx_native_app";

- (void)parseCommandLineArguments
{
	NSArray *arguments = [[NSProcessInfo processInfo] arguments];

	NSLog(@"Command line arguments: %@", arguments);

	for (int i = 1; i < arguments.count; i++)
	{
		NSString *argument = arguments[i];

		if (([argument rangeOfString:@"force"].location != NSNotFound) &&
			([argument rangeOfString:@"crash"].location != NSNotFound))
		{
			NSLog(@"forcing crash");
			self.forceCrash = YES;
			continue;
		}
		if (([argument rangeOfString:@"log"].location != NSNotFound) &&
			([argument rangeOfString:@"path"].location != NSNotFound))
		{
			self.log_path = arguments[i + 1];
			NSLog(@"log path overriden with '%@'", self.log_path);
			continue;
		}
		if (([argument rangeOfString:@"db"].location != NSNotFound) &&
			([argument rangeOfString:@"path"].location != NSNotFound))
		{
			self.db_path = arguments[i + 1];
			NSLog(@"db path overriden with '%@'", self.db_path);
			continue;
		}
		if (([argument rangeOfString:@"log"].location != NSNotFound) &&
			([argument rangeOfString:@"level"].location != NSNotFound))
		{
			self.log_level = arguments[i + 1];
			NSLog(@"log level overriden with '%@'", self.log_level);
			continue;
		}
		if (([argument rangeOfString:@"script"].location != NSNotFound) &&
			([argument rangeOfString:@"path"].location != NSNotFound))
		{
			self.scriptPath = arguments[i + 1];
			NSLog(@"script path '%@'", self.log_level);
			continue;
		}
	}
}

- (id)init
{
	self = [super init];

	NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
	self.environment = infoDict[@"KopsikEnvironment"];
	self.version = infoDict[@"CFBundleShortVersionString"];

	// Disallow duplicate instances in production
	if ([self.environment isEqualToString:@"production"])
	{
		[Utils disallowDuplicateInstances];
	}

	[Bugsnag startBugsnagWithApiKey:@"2a46aa1157256f759053289f2d687c2f"];
	NSAssert(self.environment != nil, @"Missing environment in plist");
	[Bugsnag configuration].releaseStage = self.environment;

	self.app_path = [Utils applicationSupportDirectory:self.environment];
	self.db_path = [self.app_path stringByAppendingPathComponent:@"kopsik.db"];
	self.log_path = [self.app_path stringByAppendingPathComponent:@"toggl_desktop.log"];
	self.log_level = @"debug";

	[self parseCommandLineArguments];

	NSLog(@"Starting with db path %@, log path %@, log level %@",
		  self.db_path, self.log_path, self.log_level);

	toggl_set_log_path([self.log_path UTF8String]);
	toggl_set_log_level([self.log_level UTF8String]);

	ctx = toggl_context_init([appName UTF8String], [self.version UTF8String]);

	// Using sparkle instead of self updater:
	toggl_disable_update_check(ctx);

	toggl_on_sync_state(ctx, on_sync_state);
	toggl_on_unsynced_items(ctx, on_unsynced_items);
	toggl_on_show_app(ctx, on_app);
	toggl_on_error(ctx, on_error);
	toggl_on_online_state(ctx, on_online_state);
	toggl_on_login(ctx, on_login);
	toggl_on_url(ctx, on_url);
	toggl_on_reminder(ctx, on_reminder);
	toggl_on_time_entry_list(ctx, on_time_entry_list);
	toggl_on_time_entry_autocomplete(ctx, on_time_entry_autocomplete);
	toggl_on_mini_timer_autocomplete(ctx, on_mini_timer_autocomplete);
	toggl_on_project_autocomplete(ctx, on_project_autocomplete);
	toggl_on_workspace_select(ctx, on_workspace_select);
	toggl_on_client_select(ctx, on_client_select);
	toggl_on_tags(ctx, on_tags);
	toggl_on_time_entry_editor(ctx, on_time_entry_editor);
	toggl_on_settings(ctx, on_settings);
	toggl_on_timer_state(ctx, on_timer_state);
	toggl_on_idle_notification(ctx, on_idle_notification);
	toggl_on_autotracker_rules(ctx, on_autotracker_rules);
	toggl_on_autotracker_notification(ctx, on_autotracker_notification);
	toggl_on_promotion(ctx, on_promotion);

	NSLog(@"Version %@", self.version);

	NSString *cacertPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
	toggl_set_cacert_path(ctx, [cacertPath UTF8String]);

	bool_t res = toggl_set_db_path(ctx, [self.db_path UTF8String]);
	if (!res)
	{
		NSLog(@"Failed to initialize database at %@", self.db_path);

		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Failed to initialize database"];
		NSString *informative = [NSString stringWithFormat:
								 @"Make sure you have permissions to write to folder \"%@\"", self.app_path];
		[alert setInformativeText:informative];
		[alert setAlertStyle:NSCriticalAlertStyle];
		[alert runModal];
		[NSApp terminate:nil];
		return nil;
	}

	id logToFile = infoDict[@"KopsikLogUserInterfaceToFile"];
	if ([logToFile boolValue])
	{
		NSLog(@"Redirecting UI log to file");
		NSString *logPath =
			[self.app_path stringByAppendingPathComponent:@"ui.log"];
		freopen([logPath fileSystemRepresentation], "a+", stderr);
	}

	NSLog(@"AppDelegate init done");

	return self;
}

- (void)menubarTimerFired:(NSTimer *)timer
{
	[self updateStatusItem];
}

- (void)idleTimerFired:(NSTimer *)timer
{
	uint64_t idle_seconds = 0;

	if (0 != get_idle_time(&idle_seconds))
	{
		NSLog(@"Achtung! Failed to get idle status.");
		return;
	}

	toggl_set_idle_seconds(ctx, idle_seconds);
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem
{
	switch ([anItem tag])
	{
		case kMenuItemTagContinue :
			if (!self.lastKnownUserID)
			{
				return NO;
			}
			if (self.lastKnownRunningTimeEntry != nil)
			{
				return NO;
			}
			break;
		case kMenuItemTagStop :
		case kMenuItemTagEdit :
			if (!self.lastKnownUserID)
			{
				return NO;
			}
			if (self.lastKnownRunningTimeEntry == nil)
			{
				return NO;
			}
			break;
		case kMenuItemTagMode :
		case kMenuItemTagSync :
		case kMenuItemTagLogout :
		case kMenuItemTagClearCache :
		case kMenuItemTagSendFeedback :
		case kMenuItemTagOpenBrowser :
		case kMenuItemTagNew :
			if (!self.lastKnownUserID)
			{
				return NO;
			}
			break;
		case kMenuItemRecordTimeline :
			if (!self.lastKnownUserID)
			{
				NSMenuItem *menuItem = (NSMenuItem *)anItem;
				[menuItem setState:NSOffState];
				return NO;
			}
			if (toggl_timeline_is_recording_enabled(ctx))
			{
				NSMenuItem *menuItem = (NSMenuItem *)anItem;
				[menuItem setState:NSOnState];
			}
			else
			{
				NSMenuItem *menuItem = (NSMenuItem *)anItem;
				[menuItem setState:NSOffState];
			}
			break;
		default :
			// Dont care about this stuff
			break;
	}
	return YES;
}

- (void)startDisplayIdleNotification:(NSNotification *)notification
{
	[self performSelectorOnMainThread:@selector(displayIdleNotification:)
						   withObject:notification.object
						waitUntilDone:NO];
}

- (void)displayIdleNotification:(IdleEvent *)idleEvent
{
	NSAssert([NSThread isMainThread], @"Rendering stuff should happen on main thread");

	[self.idleNotificationWindowController displayIdleEvent:idleEvent];
}

- (PLCrashReporter *)configuredCrashReporter
{
	PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc]
									 initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD
										 symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];

	return [[PLCrashReporter alloc] initWithConfiguration:config];
}

- (void)handleCrashReport
{
	PLCrashReporter *crashReporter = [self configuredCrashReporter];

	NSError *error;
	NSData *crashData = [crashReporter loadPendingCrashReportDataAndReturnError:&error];

	if (crashData == nil)
	{
		NSLog(@"Could not load crash report: %@", error);
		[crashReporter purgePendingCrashReport];
		return;
	}

	PLCrashReport *report = [[PLCrashReport alloc] initWithData:crashData
														  error:&error];
	if (report == nil)
	{
		NSLog(@"Could not parse crash report");
		[crashReporter purgePendingCrashReport];
		return;
	}

	NSString *summary = [NSString stringWithFormat:@"Crashed with signal %@ (code %@)",
						 report.signalInfo.name,
						 report.signalInfo.code];

	NSString *humanReadable = [PLCrashReportTextFormatter stringValueForCrashReport:report
																	 withTextFormat:PLCrashReportTextFormatiOS];
	NSLog(@"Crashed on %@", report.systemInfo.timestamp);
	NSLog(@"Report: %@", humanReadable);

	NSException *exception;
	if (report.hasExceptionInfo)
	{
		exception = [NSException
					 exceptionWithName:report.exceptionInfo.exceptionName
								reason:report.exceptionInfo.exceptionReason
							  userInfo:nil];
	}
	else
	{
		exception = [NSException
					 exceptionWithName:summary
								reason:humanReadable
							  userInfo:nil];
	}
	char *str = toggl_get_update_channel(ctx);
	NSString *channel = [NSString stringWithUTF8String:str];
	free(str);
	[Bugsnag notify:exception withData:[NSDictionary dictionaryWithObjectsAndKeys:@"channel", channel, nil]];

	[crashReporter purgePendingCrashReport];
}

- (void)reachabilityChanged:(NSNotification *)notice
{
	NetworkStatus remoteHostStatus = [self.reach currentReachabilityStatus];

	if (ctx && remoteHostStatus != NotReachable)
	{
		toggl_set_online(ctx);
	}
}

void on_online_state(const int64_t state)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayOnlineState
														object:[NSNumber numberWithLong:state]];
}

void on_sync_state(const int64_t state)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplaySyncState
														object:[NSNumber numberWithLong:state]];
}

void on_unsynced_items(const int64_t count)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayUnsyncedItems
														object:[NSNumber numberWithLong:count]];
}

void on_login(const bool_t open, const uint64_t user_id)
{
	[Bugsnag setUserAttribute:@"user_id" withValue:[NSString stringWithFormat:@"%lld", user_id]];

	DisplayCommand *cmd = [[DisplayCommand alloc] init];
	cmd.open = open;
	cmd.user_id = user_id;

	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayLogin
														object:cmd];
}

void on_reminder(const char *title, const char *informative_text)
{
	NSUserNotification *notification = [[NSUserNotification alloc] init];

	[notification setTitle:[NSString stringWithUTF8String:title]];
	[notification setInformativeText:[NSString stringWithUTF8String:informative_text]];
	[notification setDeliveryDate:[NSDate dateWithTimeInterval:0 sinceDate:[NSDate date]]];
	NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
	[center scheduleNotification:notification];
}

void on_url(const char *url)
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]];
}

void on_time_entry_list(const bool_t open,
						TogglTimeEntryView *first)
{
	NSMutableArray *viewitems = [[NSMutableArray alloc] init];
	TogglTimeEntryView *it = first;

	while (it)
	{
		TimeEntryViewItem *model = [[TimeEntryViewItem alloc] init];
		[model load:it];
		[viewitems addObject:model];
		it = it->Next;
	}
	DisplayCommand *cmd = [[DisplayCommand alloc] init];
	cmd.open = open;
	cmd.timeEntries = viewitems;
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayTimeEntryList
														object:cmd];
}

void on_time_entry_autocomplete(TogglAutocompleteView *first)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayTimeEntryAutocomplete
														object:[AutocompleteItem loadAll:first]];
}

void on_mini_timer_autocomplete(TogglAutocompleteView *first)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayMinitimerAutocomplete
														object:[AutocompleteItem loadAll:first]];
}

void on_project_autocomplete(TogglAutocompleteView *first)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayProjectAutocomplete
														object:[AutocompleteItem loadAll:first]];
}

void on_tags(TogglGenericView *first)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayTags
														object:[ViewItem loadAll:first]];
}

void on_autotracker_rules(TogglAutotrackerRuleView *first, const uint64_t title_count, char_t *title_list[])
{
	NSMutableArray *titles = [[NSMutableArray alloc] init];

	for (int i = 0; i < title_count; i++)
	{
		NSString *title = [NSString stringWithUTF8String:title_list[i]];
		[titles addObject:title];
	}
	NSDictionary *data = @{
		@"rules": [AutotrackerRuleItem loadAll:first],
		@"titles": titles
	};
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayAutotrackerRules
														object:data];
}

void on_autotracker_notification(const char_t *project_name,
								 const uint64_t project_id)
{
	NSUserNotification *notification = [[NSUserNotification alloc] init];

	// http://stackoverflow.com/questions/11676017/nsusernotification-not-showing-action-button
	[notification setValue:@YES forKey:@"_showsButtons"];

	notification.title = @"Toggl Desktop Autotracker";
	notification.informativeText = [NSString stringWithFormat:@"Track %@?",
									[NSString stringWithUTF8String:project_name]];
	notification.hasActionButton = YES;
	notification.actionButtonTitle = @"Start";
	notification.userInfo = @{ @"autotracker": @"YES", @"project_id": [NSNumber numberWithLong:project_id] };
	notification.deliveryDate = [NSDate dateWithTimeInterval:0 sinceDate:[NSDate date]];
	notification.soundName = NSUserNotificationDefaultSoundName;

	NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
	[center scheduleNotification:notification];
}

void on_promotion(const int64_t promotion_type)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayPromotion
														object:[NSNumber numberWithLong:promotion_type]];
}

void on_client_select(TogglGenericView *first)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayClientSelect
														object:[ViewItem loadAll:first]];
}

void on_workspace_select(TogglGenericView *first)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayWorkspaceSelect
														object:[ViewItem loadAll:first]];
}

void on_time_entry_editor(const bool_t open,
						  TogglTimeEntryView *te,
						  const char *focused_field_name)
{
	TimeEntryViewItem *item = [[TimeEntryViewItem alloc] init];

	[item load:te];
	DisplayCommand *cmd = [[DisplayCommand alloc] init];
	cmd.open = open;
	cmd.timeEntry = item;
	cmd.timeEntry.focusedFieldName = [NSString stringWithUTF8String:focused_field_name];
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayTimeEntryEditor
														object:cmd];
}

void on_app(const bool_t open)
{
	DisplayCommand *cmd = [[DisplayCommand alloc] init];

	cmd.open = open;
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayApp
														object:cmd];
}

void on_error(const char *errmsg, const bool_t is_user_error)
{
	NSString *msg = [NSString stringWithUTF8String:errmsg];

	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayError
														object:msg];
	if (!is_user_error)
	{
		char *str = toggl_get_update_channel(ctx);
		NSString *channel = [NSString stringWithUTF8String:str];
		free(str);
		[Bugsnag notify:[NSException exceptionWithName:msg reason:msg userInfo:nil]
			   withData :[NSDictionary dictionaryWithObjectsAndKeys:@"channel", channel, nil]];
	}
}

void on_settings(const bool_t open,
				 TogglSettingsView *settings)
{
	Settings *s = [[Settings alloc] init];

	[s load:settings];

	DisplayCommand *cmd = [[DisplayCommand alloc] init];
	cmd.open = open;
	cmd.settings = s;
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplaySettings
														object:cmd];
}

void on_timer_state(TogglTimeEntryView *te)
{
	TimeEntryViewItem *view_item = nil;

	if (te)
	{
		view_item = [[TimeEntryViewItem alloc] init];
		[view_item load:te];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayTimerState object:view_item];
}

void on_idle_notification(
	const char *guid,
	const char *since,
	const char *duration,
	const uint64_t started,
	const char *description)
{
	IdleEvent *idleEvent = [[IdleEvent alloc] init];

	idleEvent.guid = [NSString stringWithUTF8String:guid];
	idleEvent.since = [NSString stringWithUTF8String:since];
	idleEvent.duration = [NSString stringWithUTF8String:duration];
	idleEvent.started = started;
	idleEvent.timeEntryDescription = [NSString stringWithUTF8String:description];
	[[NSNotificationCenter defaultCenter] postNotificationName:kDisplayIdleNotification object:idleEvent];
}

@end
