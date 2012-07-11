#import "DPAppDelegate.h"
#import "SSYLoginItems.h"
#import "HTTPPOSTOperation.h"
#import "NSImage+HUAdditions.h"
#import "NSBitmapImageRep+HUAdditions.h"

#import <CoreServices/CoreServices.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#define SCREENSHOT_LOG_LIMIT 10 /* todo: make configurable */

/*@interface NSStatusBar (Unofficial)
-(id)_statusItemWithLength:(float)f withPriority:(int)d;
@end*/

extern int pngcrush_main(int argc, char *argv[]);

/*@implementation NSStatusItem (Hack)
- (NSWindow *)hackWindow {
	return _fWindow;
}
@end*/

@implementation DPAppDelegate

@synthesize cacheDir;

#pragma mark -
#pragma mark Initialization & setup

- (id)init {
	NSNumber *n;
	NSFileManager *fm = [NSFileManager defaultManager];

	self = [super init];

	// logging
	log = [ASLLogger defaultLogger];

	// init members
	defaults = [NSUserDefaults standardUserDefaults];
	uidRefDate = [NSDate dateWithTimeIntervalSince1970:1258600000];
	uploadedScreenshots = [defaults objectForKey:@"screenshots"];
	if (!uploadedScreenshots)
		uploadedScreenshots = [NSMutableDictionary dictionary];
	nCurrOps = 0;
	isObservingDesktop = NO;
	knownScreenshotsOnDesktop = [NSDictionary dictionary];
	screenshotLocation = [@"~/Desktop" stringByExpandingTildeInPath]; // default
	screenshotFilenameSuffix = @".png";
	cacheDir = [@"~/Library/Caches/se.notion.Scrup" stringByExpandingTildeInPath];
	thumbCacheDir = [cacheDir stringByAppendingPathComponent:@"thumbnails"];
	thumbSize = NSMakeSize(128.0, 128.0);
	enableThumbnails = YES;
	filePrefixMatch = [defaults objectForKey:@"filePrefixMatch"];
	postProcessShellCommand = [defaults objectForKey:@"postProcessShellCommand"];
	if (!postProcessShellCommand)
		postProcessShellCommand = @"say scrupped at $(date +%X) &";
	preprocessingWindow = nil;
	preprocessingWindowController = nil;
	preprocessingUIBlockQueue = [NSMutableArray array];
    eventManager = [[SCEvents alloc] init];
    [eventManager setDelegate:self];
    [eventManager setNotificationLatency:1];

	// set boolean properties from user defaults or give them default values
	#define SETDEFBOOL(_member_, _defval_) \
		n = [defaults objectForKey:@#_member_];\
		_member_ = n ? [n boolValue] : (_defval_);
	SETDEFBOOL(showInMenuBar, YES);
	SETDEFBOOL(showQueueCountInMenuBar, NO);
	SETDEFBOOL(paused, NO);
	SETDEFBOOL(enableThumbnails, YES);
	SETDEFBOOL(enablePngcrush, YES);
	SETDEFBOOL(convertImagesTosRGB, YES);
	SETDEFBOOL(trashAfterSuccessfulUpload, NO);
	SETDEFBOOL(enablePostProcessShellCommand, NO);
	#undef SETDEFBOOL

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
	//[defaults setObject:@"http://your.host/recv.php?name={filename}" forKey:@"recvURL"];

	// read defaults:com.apple.screencapture
	NSDictionary *screencaptureDefaults = [defaults persistentDomainForName:@"com.apple.screencapture"];
	if (screencaptureDefaults) {
		// location
		NSString *s = [screencaptureDefaults objectForKey:@"location"];
		if (
				s
				&& (s = [s stringByExpandingTildeInPath])
				&& [[NSFileManager defaultManager] fileExistsAtPath:s]
			 )
		{
            // Trim / suffix to be sure we can ignore safely subdirectories in FSEvent
            if([s hasSuffix:@"/"] && [s length] > 2) {
                screenshotLocation = [s substringToIndex:[s length] - 1];
            } else {
                screenshotLocation = s; 
            }
			[log info:@"using com.apple.screencapture location => \"%@\"", screenshotLocation];
		}
		// type
		if ((s = [screencaptureDefaults objectForKey:@"type"]) && [s length]) {
			// trim away "." to be sure not to produce strings like "..png"
			s = [s stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
			screenshotFilenameSuffix = [@"." stringByAppendingString:s];
		}
	}

	// Make sure paths exist
	if (![fm fileExistsAtPath:thumbCacheDir]) {
		[fm createDirectoryAtPath:thumbCacheDir withIntermediateDirectories:YES attributes:nil error:nil];
		// todo: handle error from mkdir thumbCacheDir
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
	[toolbar setSelectedItemIdentifier:DPToolbarGeneralSettingsItemIdentifier];

	// no recvURL? Probably first launch, so show the settings window
	if (![defaults objectForKey:@"recvURL"] || [[receiverURL stringValue] length] == 0) {
		[self orderFrontSettingsWindow:self];
		[receiverURL becomeFirstResponder];
	}

	// Start perpetual state debug loop in a background thread
	#if DEBUG
	[self performSelectorInBackground:@selector(debugPerpetualStateCheck) withObject:nil];
	#endif

	// XXX
	/*[self displayPreprocessingUIForScreenshotAtPath:@""
																						 meta:[NSDictionary dictionaryWithObjectsAndKeys:[NSDate date], @"du", nil]
																		 confirmBlock:^{
																			 NSLog(@"confirmBlock called");
																		 }];*/
}


- (NSRect)menuItemFrame {
	// ugly, ugly hack... damn you Apple.
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];
	[statusItem setView:view];
	NSRect wr = [[view window] frame];
	[statusItem setView:nil];
	[self setShowInMenuBar:NO];
	[self setShowInMenuBar:YES];
	return wr;
}


- (BOOL)preprocessingWindowIsActive {
	return preprocessingWindow && [preprocessingWindow isVisible];
}


- (void)togglePreprocessingWindow {
	if (!preprocessingWindow) {
		NSRect wr = [self menuItemFrame];
		NSPoint pt = wr.origin;
		pt.x += wr.size.width/2.0;

		preprocessingWindow = (id)[[DPAttachedWindow alloc] initWithView:preprocessingUIView
																								 attachedToPoint:pt
																												inWindow:nil
																													onSide:MAPositionBottomLeft
																											atDistance:-5.0];
		[preprocessingWindowController setWindow:preprocessingWindow];
		[preprocessingWindow setDelegate:preprocessingWindowController];
		[preprocessingWindow setDrawsRoundCornerBesideArrow:NO];
		[preprocessingWindow setBackgroundColor:[NSColor colorWithDeviceWhite:0.8 alpha:1.0]];
		[preprocessingWindow setBorderColor:[NSColor colorWithDeviceWhite:0.87 alpha:1.0]];
		[preprocessingWindow setBorderWidth:1.0];
		[preprocessingWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
		[preprocessingWindow setCanHide:NO];
		[preprocessingWindow makeKeyAndOrderFront:self];

		if (statusItem) {
			[statusItem setMenu:nil];
			[statusItem setTarget:self];
			[statusItem setAction:@selector(activateApp)];
		}
	}
	else {
		[preprocessingWindow orderOut:self];
		[preprocessingWindow release];
		preprocessingWindow = nil;

		if (statusItem) {
			[statusItem setAction:nil];
			[statusItem setTarget:nil];
			[statusItem setMenu:statusItemMenu];
		}
	}
}


- (void)activateApp {
	if (![NSApp isActive])
		[NSApp activateIgnoringOtherApps:YES];
}


- (void)enqueueDisplayOfPreprocessingUIForScreenshotAtPath:(NSString *)path
																											meta:(NSMutableDictionary *)meta
																							commitBlock:(void(^)(NSString *path))commitBlock
																							cancelBlock:(void(^)(void))cancelBlock
{
	[log debug:@"enqueing/displaying preprocessing UI for %@", path];

	if (commitBlock) commitBlock = [commitBlock copy];
	if (cancelBlock) cancelBlock = [cancelBlock copy];

	void(^_block)(void) = ^{
		BOOL appWasActive = [NSApp isActive];

		// todo: look at QuickCursor (or similar) and use AX* if enabled to re-activate
		//       previously active app & window

		#define DONE_ROUTINE \
			if (!appWasActive) [NSApp deactivate]; \
			[self togglePreprocessingWindow];\
			[self performSelectorOnMainThread:@selector(dequeueDisplayOfPreprocessingUI) withObject:nil waitUntilDone:NO];

		[preprocessingWindowController editScreenshotAtPath:path meta:meta commitBlock:^(NSString *_path){
			DONE_ROUTINE
			if (commitBlock)
				commitBlock(_path);
		} cancelBlock:^{
			DONE_ROUTINE
			if (cancelBlock)
				cancelBlock();
		}];

		#undef DONE_ROUTINE

		[self togglePreprocessingWindow];

		if (!appWasActive)
			[NSApp activateIgnoringOtherApps:YES];
	};

	// enqueue or run now?
	if (self.preprocessingWindowIsActive) {
		// enqueue
		[preprocessingUIBlockQueue addObject:[_block copy]];
		// make sure the app is active/focused
		[self activateApp];
	}
	else {
		_block();
	}
}


- (void)dequeueDisplayOfPreprocessingUI {
	if (preprocessingUIBlockQueue && [preprocessingUIBlockQueue count]) {
		void(^nextBlock)(void) = [preprocessingUIBlockQueue objectAtIndex:0];
		[preprocessingUIBlockQueue removeObjectAtIndex:0];
		[log info:@"invoking next preprocessing UI"];
		nextBlock();
	}
	else {
		[log debug:@"no more preprocessing UIs to invoke"];
	}
}


#if DEBUG
-(void)debugPerpetualStateCheck {
	ASLLogger *tlog;

	tlog = [ASLLogger loggerForModule:@"state"];
	if (g_debug) {
		tlog.connection.level = ASLLoggerLevelNone;
		[tlog addFileHandle:[NSFileHandle fileHandleWithStandardError]];
	}

	while (1) {
		[NSThread sleepForTimeInterval:10];
	}
}
#endif

#pragma mark -
#pragma mark Handling screenshots


-(NSDictionary *)screenshotsOnDesktop {
	NSDate *lmod = [NSDate dateWithTimeIntervalSinceNow:-5]; // max 5 sec old
	return [self screenshotsAtPath:screenshotLocation modifiedAfterDate:lmod];
}

/**
 * Pick-up workshorse function.
 */
-(NSDictionary *)screenshotsAtPath:(NSString *)dirpath modifiedAfterDate:(NSDate *)lmod {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *direntries;
	NSMutableDictionary *files = [NSMutableDictionary dictionary];
	NSString *path;
	NSDate *mod;
	NSError *error;
	NSDictionary *attrs;

	direntries = [fm contentsOfDirectoryAtPath:dirpath error:&error];
	if (!direntries) {
		[log error:@"%s failed to list contents of directory at '%@' -- %@", _cmd, dirpath, error];
		return nil;
	}

	for (NSString *fn in direntries) {
		//[log debug:@"%s testing %@", _cmd, fn];

		// always skip dotfiles
		if ([fn hasPrefix:@"."]) {
			//[log debug:@"%s skipping: filename begins with a dot", _cmd];
			continue;
		}

		// if prefix matching is used, test for it
		if (!(filePrefixMatch == nil || [filePrefixMatch length] == 0 || [fn hasPrefix:filePrefixMatch])) {
			[log debug:@"%s skipping: filename prefix does not match", _cmd];
			continue;
		}

		// skip any file not ending in screenshotFilenameSuffix (".png" by default)
		if (([fn length] < 10) ||
				// ".png" suffix is expected
				(![fn compare:screenshotFilenameSuffix options:NSCaseInsensitiveSearch range:NSMakeRange([fn length]-5, 4)] != NSOrderedSame)
			 )
		{
			//[log debug:@"%s skipping: not ending in \".png\" (case-insensitive)", _cmd];
			continue;
		}

		// build path
		path = [dirpath stringByAppendingPathComponent:fn];

		// Skip any file which name does not contain a SP.
		// This is a semi-ugly fix -- since we want to avoid matching the filename against
		// all possible screenshot file name schemas (must be hundreds), we make the
		// assumption that all language formats have this in common: it contains at least one SP.
		if ([fn rangeOfString:@" "].location == NSNotFound) {
			//[log debug:@"%s skipping: not containing SP", _cmd];
			continue;
		}

		// query file attributes (rich stat)
		attrs = [fm attributesOfItemAtPath:path error:&error];
		if (!attrs) {
			//[log error:@"failed to read attributes of '%@' because: %@ -- skipping", path, error];
			continue;
		}

		// must be a regular file
		if ([attrs objectForKey:NSFileType] != NSFileTypeRegular) {
			//[log debug:@"%s skipping: not a regular file", _cmd];
			continue;
		}

		// check last modified date
		mod = [attrs objectForKey:NSFileModificationDate];
		if (lmod && (!mod || [mod compare:lmod] == NSOrderedAscending)) {
			// file is too old
			//[log debug:@"%s skipping: too old", _cmd];
			continue;
		}

		// find key for NSFileExtendedAttributes
		NSString *xattrsKey = nil;
		for (NSString *k in [attrs keyEnumerator]) {
			if ([k isEqualToString:@"NSFileExtendedAttributes"]) {
				xattrsKey = k;
				break;
			}
		}
		if (!xattrsKey) {
			// no xattrs
			continue;
		}
		NSDictionary *xattrs = [attrs objectForKey:xattrsKey];
		if (!xattrs || ![xattrs objectForKey:@"com.apple.metadata:kMDItemIsScreenCapture"]) {
			[log debug:@"%s skipping: no xattr:com.apple.metadata:kMDItemIsScreenCapture", _cmd];
			continue;
		}

		// ok, let's use this file (set: string path => date modified)
		[files setObject:mod forKey:path];
	}

	return files;
}


-(void)checkForScreenshotsAtPath:(NSString *)dirpath {
	NSDictionary *files;
	NSArray *paths;

	// find new screenshots
	if (!(files = [self findUnprocessedScreenshotsOnDesktop]))
		return;

	// sort on key (path)
	paths = [files keysSortedByValueUsingComparator:^(id a, id b) { return [b compare:a]; }];

	// process each file
	for (NSString *path in paths) {
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
		// filter: remove allready processed screenshots
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

	[log info:@"processing screenshot \"%@\"", path];

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

	// Continuation -- POST
	void (^continue_block)(NSString *) = ^(NSString *actualPath){
		HTTPPOSTOperation *postOp = [HTTPPOSTOperation alloc];
		[postOp initWithPath:actualPath URL:url delegate:self];
		nCurrOps++;
		[self updateMenuItem:self];
		[statusItem setImage:iconSending];
		[g_opq addOperation:postOp];
	};

	// Strip xattr:com.apple.metadata:kMDItemIsScreenCapture
	[log debug:@"Stripping xattr:com.apple.metadata:kMDItemIsScreenCapture from %@", path];
	NSString *cmd = [NSString stringWithFormat:@"/usr/bin/xattr -d com.apple.metadata:kMDItemIsScreenCapture %@",
	                                           [path shellArgumentRepresentation]];
	int rc = system([cmd UTF8String]);
	if (rc != 0) {
		[log warn:@"Failed to strip xattr:com.apple.metadata:kMDItemIsScreenCapture from %@ (xattr exited with %d)",
							path, rc];
	}

	// UI-based preprocessing?
	if (self.enablePreprocessingUI) {
		[self enqueueDisplayOfPreprocessingUIForScreenshotAtPath:path
																												meta:rec
																								 commitBlock:continue_block
																								 cancelBlock:nil];
	}
	else {
		continue_block(path);
	}
}

-(BOOL)preprocessFileBeforeSending:(HTTPPOSTOperation *)op {
	// This callback is called from a send operation thread, so in here
	// we can spend quality time with <op>.

	// convert to sRGB
	if (convertImagesTosRGB) {
		NSBitmapImageRep *bm = [NSBitmapImageRep imageRepWithContentsOfFile:op.path];
		NSData *sRGBPNGData = [bm PNGRepresentationInsRGBColorSpace];
		[sRGBPNGData writeToFile:op.path atomically:YES];
		[op.log info:@"converted \"%@\" to sRGB", op.path];
	}

	// pngcrush
	if (enablePngcrush)
		[self pngcrushPNGImageAtPath:op.path brute:NO];

	// post-process script
	if (enablePostProcessShellCommand && postProcessShellCommand && [postProcessShellCommand length]) {
		NSString *cmd = [postProcessShellCommand stringByReplacingOccurrencesOfString:@"{path}" withString:[op.path stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
		[op.log notice:@"executing shell command: %@", cmd];
		int r = system([cmd UTF8String]);
		if (r != 0) {
			[op.log notice:@"shell command exited %d", r];
			return NO;
		}
	}

	return YES;
}


-(void)httpPostOperationDidSucceed:(HTTPPOSTOperation *)op {
	// schedule in main thread since we want to avoid locks and stuff
	[self performSelectorOnMainThread:@selector(_httpPostOperationDidSucceed:) withObject:op waitUntilDone:NO];
}

-(void)_httpPostOperationDidSucceed:(HTTPPOSTOperation *)op {
	nCurrOps--;
	NSString *rspstr = [[NSString alloc] initWithData:op.responseData encoding:NSUTF8StringEncoding];
	[op.log debug:@"succeeded with HTTP %d %@ %@",
				[op.response statusCode], [op.response allHeaderFields], rspstr];

	// Parse response as a single URL
	NSURL *scrupURL = [NSURL URLWithString:rspstr];
	if (!scrupURL) {
		[log error:@"invalid URL returned by receiver"];

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

		// Write thumbnail
		if (enableThumbnails)
			[self writeThumbnailForScreenshotAtPath:op.path];

		// Trash the file
		if (trashAfterSuccessfulUpload) {
			if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation
																									 source:[op.path stringByDeletingLastPathComponent]
																							destination:@""
																										files:[NSArray arrayWithObject:[op.path lastPathComponent]]
																											tag:NULL])
			{
				[log warn:@"could not move \"\" to trash", op.path];
			}
		}

		// Update list of recent
		[self updateListOfRecentUploads];
	}

	// Update menu item
	[self updateMenuItem:self];
}

-(void)httpPostOperationDidFail:(HTTPPOSTOperation *)op withError:(NSError *)error {
	// schedule in main thread since we want to avoid locks and stuff
	[op.log error:@"failed with error %@", error];
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

- (BOOL)enablePostProcessShellCommand {
	return enablePostProcessShellCommand;
}

- (void)setEnablePostProcessShellCommand:(BOOL)y {
	#if DEBUG
	NSLog(@"enablePostProcessShellCommand = %d", y);
	#endif
	enablePostProcessShellCommand = y;
	[defaults setBool:enablePostProcessShellCommand forKey:@"enablePostProcessShellCommand"];
}

- (NSString *)postProcessShellCommand {
	return postProcessShellCommand;
}

- (void)setPostProcessShellCommand:(NSString *)s {
	#if DEBUG
	NSLog(@"postProcessShellCommand = %@", s);
	#endif
	postProcessShellCommand = s;
	[defaults setObject:postProcessShellCommand forKey:@"postProcessShellCommand"];
}

- (NSString *)filePrefixMatch {
	return filePrefixMatch;
}

- (void)setFilePrefixMatch:(NSString *)s {
	#if DEBUG
	NSLog(@"filePrefixMatch = %@", s);
	#endif
	filePrefixMatch = s;
	[defaults setObject:filePrefixMatch forKey:@"filePrefixMatch"];
}

- (BOOL)enableThumbnails {
	return enableThumbnails;
}

- (void)setEnableThumbnails:(BOOL)y {
	#if DEBUG
	NSLog(@"enableThumbnails = %d", y);
	#endif
	enableThumbnails = y;
	[defaults setBool:enableThumbnails forKey:@"enableThumbnails"];
	[self updateListOfRecentUploads];
}

- (BOOL)convertImagesTosRGB {
	return convertImagesTosRGB;
}

- (void)setConvertImagesTosRGB:(BOOL)y {
	#if DEBUG
	NSLog(@"convertImagesTosRGB = %d", y);
	#endif
	convertImagesTosRGB = y;
	[defaults setBool:convertImagesTosRGB forKey:@"convertImagesTosRGB"];
}

- (BOOL)trashAfterSuccessfulUpload {
	return trashAfterSuccessfulUpload;
}

- (void)setTrashAfterSuccessfulUpload:(BOOL)y {
	#if DEBUG
	NSLog(@"trashAfterSuccessfulUpload = %d", y);
	#endif
	trashAfterSuccessfulUpload = y;
	[defaults setBool:trashAfterSuccessfulUpload forKey:@"trashAfterSuccessfulUpload"];
}


- (BOOL)enablePngcrush {
	return enablePngcrush;
}

- (void)setEnablePngcrush:(BOOL)y {
	#if DEBUG
	NSLog(@"enablePngcrush = %d", y);
	#endif
	enablePngcrush = y;
	[defaults setBool:enablePngcrush forKey:@"enablePngcrush"];
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
		if (paused && isObservingDesktop)
			[self stopObservingDesktop];
		else if (!paused && !isObservingDesktop)
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

- (BOOL)enablePreprocessingUI {
	NSNumber *n = [defaults objectForKey:@"enablePreprocessingUI"];
	if (!n)
		return YES; // default value
	return [n boolValue];
}

- (void)setEnablePreprocessingUI:(BOOL)y {
	#if DEBUG
	NSLog(@"enablePreprocessingUI = %d", y);
	#endif
	[defaults setBool:y forKey:@"enablePreprocessingUI"];
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
	icon = nCurrOps ? iconSending : iconState;
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

- (NSArray *)sortedUploadedScreenshotKeys {
	NSMutableArray *a = [NSMutableArray arrayWithCapacity:[uploadedScreenshots count]];
	for (NSDictionary *rec in [self sortedUploadedScreenshots]) {
		[a addObject:[rec objectForKey:@"fn"]];
	}
	return a;
}

- (NSArray *)sortedUploadedScreenshots {
	NSMutableArray *a = [NSMutableArray arrayWithCapacity:[uploadedScreenshots count]];
	[uploadedScreenshots enumerateKeysAndObjectsWithOptions:0 usingBlock:^(id key, id obj, BOOL *stop) {
		NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:obj];
		[d setObject:key forKey:@"fn"];
		[a addObject:d];
	}];
	return [a sortedArrayUsingComparator:^(id a, id b) {
		if (!a) return (NSComparisonResult)NSOrderedAscending;
		if (!b) return (NSComparisonResult)NSOrderedDescending;
		return [(NSDate *)[b objectForKey:@"du"] compare:(NSDate *)[a objectForKey:@"du"]];
	}];
}

-(void)updateListOfRecentUploads {
	NSInteger i, n, limit = SCREENSHOT_LOG_LIMIT;
	NSString *fn;

	// todo: reuse/move existing items instead of removing them just to then create them again.
	i = [statusItemMenu indexOfItemWithTag:1337]+1;
	n = [statusItemMenu numberOfItems];

	for (NSDictionary *m in [self sortedUploadedScreenshots]) {
		NSDate *d = [m objectForKey:@"du"];
		NSString *calfmt = @"%Y-%m-%d %H:%M:%S";
		NSTimeInterval age = -[d timeIntervalSinceNow];
		if (age < 60*60) // <1h
			calfmt = @"%H:%M:%S";
		else if (age < 60*60*23) // <23h
			calfmt = @"%H:%M";
		else if (age < 60*60*24*6) // <~1w
			calfmt = @"%a %H:%M"; // Fri 19:01
		else if (age < 60*60*24*250) // <~1y
			calfmt = @"%a %b %e"; // Fri Nov 7
		NSString *title = [d descriptionWithCalendarFormat:calfmt timeZone:nil locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
		if (i < n)
			[statusItemMenu removeItemAtIndex:i];
		NSMenuItem *mi = [statusItemMenu insertItemWithTitle:title action:@selector(openUploadedImageURL:) keyEquivalent:@"" atIndex:i];

		// set thumbnail
		if (enableThumbnails && (fn = [m objectForKey:@"fn"])) {
			NSImage *im = [[NSImage alloc] initWithContentsOfFile:[thumbCacheDir stringByAppendingPathComponent:fn]];
			if (im)
				[mi setImage:im];
			else
				[log debug:@"no thumb for %@", fn];
		}

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

- (IBAction)displayViewForGeneralSettings:(id)sender {
	if (generalSettingsView && [mainWindow contentView] != generalSettingsView)
		[mainWindow setContentView:generalSettingsView display:YES animate:YES];
}

- (IBAction)displayViewForProcessingSettings:(id)sender {
	if (processingSettingsView && [mainWindow contentView] != processingSettingsView)
		[mainWindow setContentView:processingSettingsView display:YES animate:YES];
}

- (IBAction)displayViewForAdvancedSettings:(id)sender {
	if (advancedSettingsView && [mainWindow contentView] != advancedSettingsView)
		[mainWindow setContentView:advancedSettingsView display:YES animate:YES];
}

- (IBAction)saveState:(id)sender {
	[defaults setObject:uploadedScreenshots forKey:@"screenshots"];
}

- (IBAction)orderFrontSettingsWindow:(id)sender {
	if (![NSApp isActive])
		[NSApp activateIgnoringOtherApps:YES];
	[mainWindow makeKeyAndOrderFront:sender];
}

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event {
    // check flags for kFSEventStreamEventFlagItemCreated (0x100)
    int flags = [event eventFlags];
    if (!(flags & 0x100))
        return;
    
    #if DEBUG
    [log debug:@"Received SCEvents directory notification"];
    #endif
    NSString *eventPath = [event eventPath];
    if([eventPath hasSuffix:@"/"] && [eventPath length] > 2)
        eventPath = [eventPath substringToIndex:[eventPath length] - 1];
    if([eventPath isEqualToString:screenshotLocation]) {
        [self checkForScreenshotsAtPath:screenshotLocation];
    }
    #if DEBUG
    else {
        [log debug:@"Event in subfolder, ignoring"];
    }
    #endif
}

- (void)startObservingDesktop {
	if (isObservingDesktop)
		return;
	[log info:@"Starting observation of desktop using SCEvents"];
    NSMutableArray *pathsToWatch = [NSMutableArray arrayWithObject:screenshotLocation];
	isObservingDesktop = [eventManager startWatchingPaths:pathsToWatch];
    if(!isObservingDesktop)
        [log error:@"Error while starting desktop observer"];
}

- (void)stopObservingDesktop {
	if (!isObservingDesktop)
		return;
	[log info:@"Stopping observation of desktop using SCEvents"];
    if(![eventManager stopWatchingPaths])
        [log error:@"Error while stopping desktop observer"];
	isObservingDesktop = NO;
}

#pragma mark -
#pragma mark NSApplication delegate methods

#if !(DEBUG)
#import "PFMoveApplication.h"
#endif

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	#if !(DEBUG)
	PFMoveToApplicationsFolderIfNecessary();
	#endif

	[self updateListOfRecentUploads];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[log debug:@"event: applicationDidFinishLaunching"];
	knownScreenshotsOnDesktop = [self screenshotsOnDesktop];
	if (!paused)
		[self startObservingDesktop];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[self saveState:self];
}


#pragma mark -
#pragma mark NSToolbar delegate methods

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)_toolbar {
	return [NSArray arrayWithObjects:
					DPToolbarGeneralSettingsItemIdentifier,
					DPToolbarProcessingSettingsItemIdentifier,
					DPToolbarAdvancedSettingsItemIdentifier,
					NSToolbarFlexibleSpaceItemIdentifier,
					NSToolbarSpaceItemIdentifier,
					NSToolbarSeparatorItemIdentifier, nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)_toolbar {
	return [NSArray arrayWithObjects:
					DPToolbarGeneralSettingsItemIdentifier,
					DPToolbarProcessingSettingsItemIdentifier,
					DPToolbarAdvancedSettingsItemIdentifier,
					nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)_toolbar {
	return [self toolbarDefaultItemIdentifiers:_toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)_toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *item = nil;
	if (itemIdentifier == DPToolbarGeneralSettingsItemIdentifier) {
		item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		[item setImage:[NSImage imageNamed:@"NSPreferencesGeneral"]];
		[item setLabel:@"General"];
		[item setToolTip:@"General settings"];
		[item setTarget:self];
		[item setAction:@selector(displayViewForGeneralSettings:)];
	}
	else if (itemIdentifier == DPToolbarProcessingSettingsItemIdentifier) {
		item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		[item setImage:[NSImage imageNamed:@"toolbar-processing"]];
		[item setLabel:@"Processing"];
		[item setToolTip:@"How images are picked up and processed"];
		[item setTarget:self];
		[item setAction:@selector(displayViewForProcessingSettings:)];
	}
	else if (itemIdentifier == DPToolbarAdvancedSettingsItemIdentifier) {
		item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		[item setImage:[NSImage imageNamed:@"NSAdvanced"]];
		[item setLabel:@"Advanced"];
		[item setToolTip:@"You probably don't need to change these things in here"];
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
	NSFileManager *fm;
	NSArray *rmkeys;

	if ([uploadedScreenshots count] > SCREENSHOT_LOG_LIMIT) {
		fm = [NSFileManager defaultManager];
		rmkeys = [self sortedUploadedScreenshotKeys];
		rmkeys = [rmkeys subarrayWithRange:NSMakeRange(SCREENSHOT_LOG_LIMIT, [rmkeys count]-SCREENSHOT_LOG_LIMIT)];

		// remove any thumbnails
		// todo: remove all thumbnails which is NOT in [uploadedScreenshots allKeys] instead
		//       of removing those we know of.
		for (NSString *fn in rmkeys) {
			BOOL removed = [fm removeItemAtPath:[thumbCacheDir stringByAppendingPathComponent:fn] error:nil];
			if (removed)
				[log debug:@"removed old screenshot record for '%@'", fn];
		}

		[uploadedScreenshots removeObjectsForKeys:rmkeys];
	}
}


-(BOOL)pngcrushPNGImageAtPath:(NSString *)path brute:(BOOL)brute {
	NSFileManager *fm = [NSFileManager defaultManager];
	char *tmpntpl = NULL;
	NSError *err = nil;
	NSString *tmppath;
	BOOL success = NO;

	NSDictionary *attrs;
	if ((attrs = [fm attributesOfItemAtPath:path error:&err])) {
		[log debug:@"[pngcrush] original size: %llu B", [attrs fileSize]];
	}

	#define PNCARGC 8
	char *argv[PNCARGC] = {
		"libpngcrush",
		"-q", // quiet
		"-fix", // fix otherwise fatal conditions such as bad CRCs
		//"-reduce", // do lossless color-type or bit-depth reduction if possible // cur. not sup.
		brute ? "-brute" : "-q",
		"-rem","allb", // remove all meta except from tRNS and gAMA
		"/tmp/input",
		"/tmp/output"
	};
	argv[PNCARGC-2] = (char *)/* this is safe -- it won't be altered */[path UTF8String];
	tmppath = [cacheDir stringByAppendingString:@"pngcrush.XXXXXX"];
	tmpntpl = strdup([tmppath UTF8String]);
	argv[PNCARGC-1] = mktemp(tmpntpl);

	if (argv[PNCARGC-1] == NULL) {
		[log error:@"[pngcrush] mktemp(\"%s\") failed", tmpntpl];
		return NO;
	}

	int pncr = pngcrush_main(PNCARGC, (char **)argv);

	if (pncr == 0) {
		tmppath = [NSString stringWithUTF8String:argv[PNCARGC-1]];

		if ((attrs = [fm attributesOfItemAtPath:tmppath error:&err]))
			[log debug:@"[pngcrush] crushed \"%@\" to size: %llu B", path, [attrs fileSize]];
		else
			[log debug:@"debug: [pngcrush] crushed \"%@\"", path];

		NSURL *resultingURL = nil;
		success = [fm replaceItemAtURL:[NSURL fileURLWithPath:path]
										 withItemAtURL:[NSURL fileURLWithPath:tmppath]
										backupItemName:nil
													 options:0
									resultingItemURL:&resultingURL
														 error:&err];
		if (!success) {
			[log error:@"error: [pngcrush] atomic/safe rename \"%s\" --> \"%@\" failed: %@", argv[PNCARGC-1], path, err];
			[fm removeItemAtPath:tmppath error:nil];
		}
	}
	else {
		[log error:@"error: [pngcrush] pngcrush_main(<%d args>) failed with code %d", PNCARGC, pncr];
		[fm removeItemAtPath:tmppath error:nil];
	}
	#undef PNCARGC

	if (tmpntpl)
		free(tmpntpl);
	return success;
}


-(void)writeThumbnailForScreenshotAtPath:(NSString *)path {
	NSImage *im;
	NSData *bmData;
	NSBitmapImageRep *bmrep;
	NSString *thumbPath;

	im = [[NSImage alloc] initWithContentsOfFile:path];
	if (!im)
		return;
	im = [im imageByScalingProportionallyWithinSize:thumbSize];
	bmrep = [[NSBitmapImageRep alloc] initWithData:[im TIFFRepresentation]];

	if (convertImagesTosRGB)
		bmData = [bmrep PNGRepresentationInsRGBColorSpace];
	else
		bmData = [bmrep PNGRepresentationAsProgressive:NO];

	if (!bmData || ![bmData length]) {
		[log warn:@"failed to create thumbnail for %@", path];
		return;
	}
	thumbPath = [thumbCacheDir stringByAppendingPathComponent:[path lastPathComponent]];
	[bmData writeToFile:thumbPath atomically:NO];

	if (enablePngcrush)
		[self pngcrushPNGImageAtPath:thumbPath brute:NO];

	[log debug:@"wrote thumbnail to %@", thumbPath];
}


@end
