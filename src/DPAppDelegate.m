#import "DPAppDelegate.h"
#import "SSYLoginItems.h"
#import "HTTPPOSTOperation.h"

#import <CoreServices/CoreServices.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#define SCREENSHOT_LOG_LIMIT 100

static void _on_fsevent(ConstFSEventStreamRef streamRef,
												void *userdata,
												size_t nevents,
												void *_paths,
												const FSEventStreamEventFlags eventFlags[],
												const FSEventStreamEventId eventIds[])
{
	int i;
	char **paths = _paths;
	id self = (id)userdata;
	
	for (i=0; i<nevents; i++) {
		/* flags are unsigned long, IDs are uint64_t */
		#if DEBUG
		printf("Change %llu in %s, flags %lu\n", eventIds[i], paths[i], eventFlags[i]);
		#endif
		[self checkForScreenshotsAtPath:[NSString stringWithUTF8String:paths[i]]];
	}
}


/*@interface NSStatusBar (Unofficial)
-(id)_statusItemWithLength:(float)f withPriority:(int)d;
@end*/

@implementation DPAppDelegate

#pragma mark -
#pragma mark Initialization & setup

- (id)init {
	NSNumber *n;
	
	self = [super init];
	
	// init members
	defaults = [NSUserDefaults standardUserDefaults];
	fsevstream = NULL;
	uidRefDate = [NSDate dateWithTimeIntervalSince1970:1258600000];
	uploadedScreenshots = [defaults objectForKey:@"screenshots"];
	if (!uploadedScreenshots)
		uploadedScreenshots = [NSMutableDictionary dictionary];
	nCurrOps = 0;
	fseventsIsObservingDesktop = NO;
	knownScreenshotsOnDesktop = [NSDictionary dictionary];
	screenshotLocation = [@"~/Desktop" stringByExpandingTildeInPath];
	
	// read general settings from defaults
	n = [defaults objectForKey:@"showInMenuBar"];
	showInMenuBar = (!n || [n boolValue]); // default YES
	n = [defaults objectForKey:@"showQueueCountInMenuBar"];
	showQueueCountInMenuBar = (n && [n boolValue]); // default NO
	n = [defaults objectForKey:@"paused"];
	paused = (n && [n boolValue]); // default NO
	
	// read showInDock
	showInDock = YES;
	NSMutableDictionary *infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Info.plist"]];
	n = [infoPlist objectForKey:@"LSUIElement"];
	if (n) showInDock = ![n boolValue];
	
	// prevent lock-out state
	if (!showInDock && !showInMenuBar)
		self.showInMenuBar = YES;
	
	// set openAtLogin to YES by default
	if (!openAtLogin && ![defaults objectForKey:@"openAtLoginIsSet"])
		[self setOpenAtLogin:YES];
	
	// read recvURL
	if (![defaults objectForKey:@"recvURL"])
		[defaults setObject:@"http://your.host/recv.php?name={filename}" forKey:@"recvURL"];
	
	// read com.apple.screencapture location, if set
	NSDictionary *screencaptureDefaults = [defaults persistentDomainForName:@"com.apple.screencapture"];
	if (screencaptureDefaults) {
		NSString *loc = [screencaptureDefaults objectForKey:@"location"];
		if (loc && [[NSFileManager defaultManager] fileExistsAtPath:loc]) {
			screenshotLocation = loc;
			#if DEBUG
			NSLog(@"using com.apple.screencapture location => \"%@\"", screenshotLocation);
			#endif
		}
	}
	
	return self;
}

- (void)awakeFromNib {
	// Setup icons
	iconStandby = [NSImage imageNamed:@"status-item-standby.png"];
	iconPaused = [NSImage imageNamed:@"status-item-paused.png"];
	iconSending = [NSImage imageNamed:@"status-item-sending.png"];
	iconOk = [NSImage imageNamed:@"status-item-ok.png"];
	iconError = [NSImage imageNamed:@"status-item-error.png"];
	iconSelected = [NSImage imageNamed:@"status-item-selected.png"];
	iconSelectedPaused = [NSImage imageNamed:@"status-item-selected-paused.png"];
	iconState = paused ? iconPaused : iconStandby;
	icon = iconState;
	
	[self enableOrDisableMenuItem:self];
	
	// set default selected toolbar item and view
	[toolbar setSelectedItemIdentifier:DPToolbarFoldersItemIdentifier];
}

#pragma mark -
#pragma mark Handling screenshots


-(NSDictionary *)screenshotsOnDesktop {
	NSDate *lmod = [NSDate dateWithTimeIntervalSinceNow:-10]; // max 10 sec old
	return [self screenshotsAtPath:screenshotLocation modifiedAfterDate:lmod];
}

-(NSDictionary *)screenshotsAtPath:(NSString *)dirpath modifiedAfterDate:(NSDate *)lmod {
	NSDirectoryEnumerator *den = [[NSFileManager defaultManager] enumeratorAtPath:dirpath];
	NSMutableDictionary *files = [NSMutableDictionary dictionary];
	NSString *path;
	NSDate *mod;
	int fd;
	
	for (NSString *fn in den) {
		if (![fn hasPrefix:@"Screen shot "] || ![fn hasSuffix:@".png"])
			continue;
		path = [dirpath stringByAppendingPathComponent:fn];
		
		// must be able to stat and must be a regular file
		struct stat s;
		if (stat([path UTF8String], &s) != 0) {
			NSLog(@"error: stat(\"%@\") failed", path);
			continue;
		}
		if (!S_ISREG(s.st_mode)) {
			//NSLog(@"skipping non-file %@", path);
			continue;
		}
		
		// Are we able to aquire an exclusive lock? Then the file is probably not being written to.
		if ((fd = open([path UTF8String], O_RDWR | O_EXLOCK | O_NONBLOCK)) == -1) {
			NSLog(@"warn: skipping/delaying locked \"%@\"", fn);
			// kqueue will emit an event once the file is completely written, we
			// will then implicitly try again.
			continue;
		}
		else {
			close(fd);
		}
		
		// check last modified date
		mod = [NSDate dateWithTimeIntervalSince1970:s.st_mtime];
		NSComparisonResult c = [mod compare:lmod];
		if (c == NSOrderedDescending || c == NSOrderedSame) {
			[files setObject:mod forKey:path];
		}
		/*#if DEBUG
		else {
			// might be VERY verbose
			NSLog(@"skipping old \"%@\"", fn);
		}
		#endif*/
	}
	
	return files;
}


-(void)checkForScreenshotsAtPath:(NSString *)dirpath {
	NSDictionary *files;
	NSArray *sortedKeys;
	
	if (!(files = [self findUnprocessedScreenshotsOnDesktop]))
		return;
	sortedKeys = [files keysSortedByValueUsingComparator:^(id a, id b) {
		return [b compare:a];
	}];
	for (NSString *path in sortedKeys) {
		[self vacuumUploadedScreenshots];
		[self processScreenshotAtPath:path modifiedAtDate:[files objectForKey:path]];
	}
}


// This keeps state, so be careful when calling since it will return different
// thing for each call (or nil if there are no new files).
-(NSDictionary *)findUnprocessedScreenshotsOnDesktop {
	NSDictionary *currentFiles;
	NSMutableDictionary *files;
	NSMutableSet *newFilenames;
	
	currentFiles = [self screenshotsOnDesktop];
	files = nil;
	
	if ([currentFiles count]) {
		newFilenames = [NSMutableSet setWithArray:[currentFiles allKeys]];
		[newFilenames minusSet:[NSSet setWithArray:[knownScreenshotsOnDesktop allKeys]]];
		if ([newFilenames count]) {
			files = [NSMutableDictionary dictionaryWithCapacity:1];
			for (NSString *path in newFilenames) {
				[files setObject:[currentFiles objectForKey:path] forKey:path];
			}
		}
	}
	
	knownScreenshotsOnDesktop = currentFiles;
	return files;
}


-(void)processScreenshotAtPath:(NSString *)path modifiedAtDate:(NSDate *)dateModified {
	NSString *fn;
	
	#if DEBUG
	NSLog(@"processing screenshot \"%@\"", path);
	#endif
	
	fn = [path lastPathComponent];
	
	// receiver URL
	NSString *surl = [defaults objectForKey:@"recvURL"];
	if (!surl || ![surl length]) {
		ALERT_MODAL(@"Scrup: Missing Receiver URL", @"No Receiver URL has been specified");
		return;
	}
	NSString *fne = [fn stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	surl = [surl stringByReplacingOccurrencesOfString:@"{filename}" withString:fne];
	
	// validate URL
	NSURL *url = [NSURL URLWithString:surl];
	if (![[url scheme] isEqualToString:@"http"] && ![[url scheme] isEqualToString:@"https"]) {
		ALERT_MODAL(@"Scrup: Invalid Receiver URL", 
								@"The Receiver URL must be a HTTP or HTTPS URL (begin with \"http://\" or \"https://\")");
		return;
	}
	
	// Register
	NSMutableDictionary *rec = [uploadedScreenshots objectForKey:fn];
	if (rec) {
		[rec setObject:dateModified forKey:@"du"];
	}
	else {
		rec = [NSMutableDictionary dictionaryWithObject:dateModified forKey:@"du"];
		[uploadedScreenshots setObject:rec forKey:fn];
	}
	
	// POST
	HTTPPOSTOperation *postOp = [HTTPPOSTOperation alloc];
	[postOp initWithPath:path URL:url delegate:self];
	nCurrOps++;
	[self updateMenuItem:self];
	[statusItem setImage:iconSending];
	[g_opq addOperation:postOp];
}


-(void)httpPostOperationDidSucceed:(HTTPPOSTOperation *)op {
	// schedule in main thread since we want to avoid locks and stuff
	[self performSelectorOnMainThread:@selector(_httpPostOperationDidSucceed:) withObject:op waitUntilDone:NO];
}

-(void)_httpPostOperationDidSucceed:(HTTPPOSTOperation *)op {
	nCurrOps--;
	NSString *rspstr = [[NSString alloc] initWithData:op.responseData encoding:NSUTF8StringEncoding];
	NSLog(@"[%@] succeeded with HTTP %d %@ %@", op, 
				[op.response statusCode], [op.response allHeaderFields], rspstr);
	
	// Parse response as a single URL
	NSURL *scrupURL = [NSURL URLWithString:rspstr];
	if (!scrupURL) {
		NSLog(@"error: invalid URL returned by receiver");
		
		// Remove record of screenshot
		[uploadedScreenshots removeObjectForKey:[op.path lastPathComponent]];
		
		// Display "error" icon
		[self momentarilyDisplayIcon:iconError];
	}
	else {
		// add url to scrup record
		NSMutableDictionary *rec = [self uploadedScreenshotForOperation:op];
		if (rec) {
			[rec setObject:rspstr forKey:@"url"];
			//NSLog(@"rec => %@", rec);
		}
		
		// Put URL in pasteboard
		// this code is >=10.6 only:
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		[pb clearContents];
		[pb writeObjects:[NSArray arrayWithObject:scrupURL]];
		//NSLog(@"%@", [pb types]);
		
		// Display "OK" icon
		[self momentarilyDisplayIcon:iconOk];
		[self updateListOfRecentUploads];
	}
	
	// Update menu item
	[self updateMenuItem:self];
}

-(void)httpPostOperationDidFail:(HTTPPOSTOperation *)op withError:(NSError *)error {
	// schedule in main thread since we want to avoid locks and stuff
	NSLog(@"[%@] failed with error %@", op, error);
	[self performSelectorOnMainThread:@selector(_httpPostOperationDidFail:) withObject:[NSArray arrayWithObjects:op, error, nil] waitUntilDone:NO];
}

-(void)_httpPostOperationDidFail:(NSArray *)args {
	nCurrOps--;
	HTTPPOSTOperation *op = [args objectAtIndex:0];
	//NSError *error = [args objectAtIndex:1];
	
	// Remove record of screenshot
	[uploadedScreenshots removeObjectForKey:[op.path lastPathComponent]];
	
	// Display "error" icon
	[self momentarilyDisplayIcon:iconError];
	
	[self updateMenuItem:self];
	[self updateListOfRecentUploads];
}

#pragma mark -
#pragma mark Properties

- (BOOL)openAtLogin {
	NSError *error = nil;
	NSURL *bundleURL = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] bundlePath] isDirectory:YES];
	NSNumber *isLoginItem = nil;
	NSNumber *isHidden = nil;
	if ([SSYLoginItems isURL:bundleURL loginItem:&isLoginItem hidden:&isHidden error:&error])
		openAtLogin = [isLoginItem boolValue];
	// else discard error
	return openAtLogin;
}

- (void)setOpenAtLogin:(BOOL)y {
	NSError *error = nil;
	openAtLogin = y;
	if ([SSYLoginItems synchronizeLoginItemPath:[[NSBundle mainBundle] bundlePath] shouldBeLoginItem:openAtLogin setHidden:NO error:&error] == SSYSharedFileListResultFailed)
	{
		[[NSAlert alertWithError:error] runModal];
	}
	else {
		[defaults setBool:YES forKey:@"openAtLoginIsSet"];
	}
}

- (BOOL)showInDock {
	return showInDock;
}

- (void)setShowInDock:(BOOL)y {
	#if DEBUG
	NSLog(@"showInDock = %d", y);
	#endif
	showInDock = y;
	NSString *infoPlistPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Info.plist"];
	NSMutableDictionary *infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:infoPlistPath];
	[infoPlist setObject:[NSNumber numberWithBool:!showInDock] forKey:@"LSUIElement"];
	[infoPlist writeToFile:infoPlistPath atomically:YES];
}

- (BOOL)showInMenuBar {
	return showInMenuBar;
}

- (void)setShowInMenuBar:(BOOL)y {
	#if DEBUG
	NSLog(@"showInMenuBar = %d", y);
	#endif
	showInMenuBar = y;
	[statusItem setEnabled:showInMenuBar];
	[defaults setBool:showInMenuBar forKey:@"showInMenuBar"];
	[self enableOrDisableMenuItem:self];
}

- (BOOL)showQueueCountInMenuBar {
	return showQueueCountInMenuBar;
}

- (void)setShowQueueCountInMenuBar:(BOOL)y {
	#if DEBUG
	NSLog(@"showQueueCountInMenuBar = %d", y);
	#endif
	showQueueCountInMenuBar = y;
	[defaults setBool:showQueueCountInMenuBar forKey:@"showQueueCountInMenuBar"];
	[self updateMenuItem:self];
}

- (BOOL)paused {
	return paused;
}

- (void)setPaused:(BOOL)y {
	paused = y;
	
	[defaults setBool:paused forKey:@"paused"];
	if (paused)
		[pauseMenuItem setTitle:@"Paused"];
	else
		[pauseMenuItem setTitle:@"Pause"];
	if ([NSApp isRunning]) {
		if (paused && [self isObservingDesktop])
			[self stopObservingDesktop];
		else if (!paused && ![self isObservingDesktop])
			[self startObservingDesktop];
	}
	
	// update icon
	BOOL x = icon == iconState;
	iconState = paused ? iconPaused : iconStandby;
	if (x)
		icon = iconState;
	[statusItem setAlternateImage:paused ? iconSelectedPaused : iconSelected];
	[self resetIcon];
}


#pragma mark -
#pragma mark Actions

-(void)momentarilyDisplayIcon:(NSImage *)ic {
	if (statusItem) {
		[statusItem setImage:ic];
		[self performSelector:@selector(resetIcon) withObject:nil afterDelay:4.0];
		// if we call statusItem:setImage: directly, <icon> might have changed at the 
		// future time of invocation, thus we read the value first at call time.
	}
}

-(void)resetIcon {
	if (statusItem)
		[statusItem setImage:icon];
}

- (IBAction)enableOrDisableMenuItem:(id)sender {
	if (showInMenuBar)
		[self enableMenuItem:self];
	else
		[self disableMenuItem:self];
}

- (IBAction)enableMenuItem:(id)sender {
	// For increased priority:
	// _statusItemWithLength:0 withPriority:INT_MAX
	if (!statusItem && (statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:0])) {
		[statusItem setLength:0];
		[statusItem setAlternateImage:paused ? iconSelectedPaused : iconSelected];
		[statusItem setHighlightMode:YES];
		[statusItem setMenu:statusItemMenu];
		[statusItem setLength:NSVariableStatusItemLength];
		[statusItem setImage:iconState];
		[self updateMenuItem:sender];
	}
}

- (IBAction)disableMenuItem:(id)sender {
	if (statusItem) {
		[[statusItem statusBar] removeStatusItem:statusItem];
		statusItem = nil;
	}
}

- (IBAction)updateMenuItem:(id)sender {
	if (!statusItem)
		return;
	
	icon = nCurrOps ? iconSending : iconState;
	
	if (showQueueCountInMenuBar) {
		[statusItem setLength:NSVariableStatusItemLength];
		[statusItem setTitle:[NSString stringWithFormat:@"%d", nCurrOps]];
	}
	else {
		if ([statusItem title])
			[statusItem setTitle:nil];
		[statusItem setLength:25.0];
	}
}

-(void)updateListOfRecentUploads {
	NSInteger i, n, limit = 10;
	NSArray *keys;
	
	// todo: reuse/move existing items instead of removing them just to then create them again.
	i = [statusItemMenu indexOfItemWithTag:1337]+1;
	n = [statusItemMenu numberOfItems];
	
	keys = [[uploadedScreenshots allKeys] sortedArrayUsingComparator:^(id a, id b) {
		return [b compare:a options:NSNumericSearch];
	}];
	
	for (NSString *key in keys) {
		NSDictionary *m = [uploadedScreenshots objectForKey:key];
		NSDate *d = [m objectForKey:@"du"];
		NSString *title = [d descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S" timeZone:nil locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
		if (i < n)
			[statusItemMenu removeItemAtIndex:i];
		NSMenuItem *mi = [statusItemMenu insertItemWithTitle:title action:@selector(openUploadedImageURL:) keyEquivalent:@"" atIndex:i];
		[mi setRepresentedObject:m];
		if (!limit--)
			break;
		i++;
	}
}

-(IBAction)openUploadedImageURL:(id)sender {
	NSDictionary *rec;
	NSString *urlstr;
	NSURL *url;
	
	if (sender
			&& (rec = [sender representedObject]) 
			&& (urlstr = [rec objectForKey:@"url"]) 
			&& (url = [NSURL URLWithString:urlstr]))
	{
		[[NSWorkspace sharedWorkspace] openURL:url];
	}
}

- (IBAction)displayViewForFoldersSettings:(id)sender {
	if ([mainWindow contentView] != generalSettingsView)
		[mainWindow setContentView:generalSettingsView];// display:YES animate:YES];
}

- (IBAction)displayViewForAdvancedSettings:(id)sender {
	if ([mainWindow contentView] != advancedSettingsView)
		[mainWindow setContentView:advancedSettingsView];// display:YES animate:YES];
}

- (IBAction)saveState:(id)sender {
	[defaults setObject:uploadedScreenshots forKey:@"screenshots"];
}

- (IBAction)orderFrontFoldersSettingsWindow:(id)sender {
	[self displayViewForFoldersSettings:sender];
	[toolbar setSelectedItemIdentifier:DPToolbarFoldersItemIdentifier];
	[self orderFrontSettingsWindow:sender];
}

- (IBAction)orderFrontSettingsWindow:(id)sender {
	if (![NSApp isActive])
		[NSApp activateIgnoringOtherApps:YES];
	[mainWindow makeKeyAndOrderFront:sender];
}

- (void)setupFSEvents {
	CFStringRef path = (CFStringRef)screenshotLocation;
	if (!path) {
		NSLog(@"error: screenshotLocation == NULL");
		return;
	}
	CFArrayRef pathsToWatch = CFArrayCreate(NULL, (const void **)&path, 1, NULL);
	CFTimeInterval latency = 0.0; // seconds
	FSEventStreamContext ctx = (FSEventStreamContext){ 
    0, //version
    (void *)self, //info
    NULL, //CFAllocatorRetainCallBack retain; 
    NULL, //CFAllocatorReleaseCallBack release; 
    NULL //CFAllocatorCopyDescriptionCallBack copyDescription; 
	};
	fsevstream = FSEventStreamCreate(CFAllocatorGetDefault(),
																	 &_on_fsevent,
																	 &ctx,
																	 pathsToWatch,
																	 kFSEventStreamEventIdSinceNow, /* Or a previous event ID */
																	 latency,
																	 kFSEventStreamCreateFlagNone /* Flags explained in reference */
																	 );
	FSEventStreamScheduleWithRunLoop(fsevstream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);	
}

- (BOOL)startObservingDesktop {
	if (fsevstream == NULL)
		[self setupFSEvents];
	fseventsIsObservingDesktop = FSEventStreamStart(fsevstream);
	return fseventsIsObservingDesktop;
}

- (void)stopObservingDesktop {
	if (fsevstream != NULL)
		FSEventStreamStop(fsevstream);
	fseventsIsObservingDesktop = NO;
}

- (BOOL)isObservingDesktop {
	return fseventsIsObservingDesktop;
}

#pragma mark -
#pragma mark NSApplication delegate methods

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[self updateListOfRecentUploads];
	knownScreenshotsOnDesktop = [self screenshotsOnDesktop];
	if (!paused)
		[self startObservingDesktop];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[self saveState:self];
}


#pragma mark -
#pragma mark NSToolbar delegate methods

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)_toolbar {
	return [NSArray arrayWithObjects:
		DPToolbarFoldersItemIdentifier,
		DPToolbarSettingsItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
		NSToolbarSpaceItemIdentifier,
		NSToolbarSeparatorItemIdentifier, nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)_toolbar {
	return [NSArray arrayWithObjects:DPToolbarFoldersItemIdentifier, DPToolbarSettingsItemIdentifier, nil];	
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)_toolbar {
	return [self toolbarDefaultItemIdentifiers:_toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)_toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *item = nil;
	if (itemIdentifier == DPToolbarFoldersItemIdentifier) {
		item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		[item setImage:[NSImage imageNamed:@"NSPreferencesGeneral"]];
		[item setLabel:@"General"];
		[item setToolTip:@"General settings"];
		[item setTarget:self];
		[item setAction:@selector(displayViewForFoldersSettings:)];
	}
	else if (itemIdentifier == DPToolbarSettingsItemIdentifier) {
		item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		[item setImage:[NSImage imageNamed:@"NSAdvanced"]];
		[item setLabel:@"Advanced"];
		[item setToolTip:@"Optional settings"];
		[item setTarget:self];
		[item setAction:@selector(displayViewForAdvancedSettings:)];
	}
	return item;
}

#pragma mark -
#pragma mark Utilities

-(NSMutableDictionary *)uploadedScreenshotForOperation:(HTTPPOSTOperation *)op {
	return [uploadedScreenshots objectForKey:[op.path lastPathComponent]];
}

-(void)vacuumUploadedScreenshots {
	if ([uploadedScreenshots count] > SCREENSHOT_LOG_LIMIT) {
		NSArray *rmkeys;
		rmkeys = [[uploadedScreenshots allKeys] sortedArrayUsingComparator:^(id a, id b) {
			return [b compare:a options:NSNumericSearch];
		}];
		rmkeys = [rmkeys subarrayWithRange:NSMakeRange(SCREENSHOT_LOG_LIMIT, [rmkeys count]-SCREENSHOT_LOG_LIMIT)];
		[uploadedScreenshots removeObjectsForKeys:rmkeys];
	}
}


@end
