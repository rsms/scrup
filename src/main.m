#import "DPAppDelegate.h"
#import "ASLLogger.h"

NSOperationQueue *g_opq;
BOOL g_debug = NO;

NSString *DPToolbarGeneralSettingsItemIdentifier = @"DPToolbarGeneralSettingsItem";
NSString *DPToolbarProcessingSettingsItemIdentifier = @"DPToolbarProcessingSettingsItem";
NSString *DPToolbarAdvancedSettingsItemIdentifier = @"DPToolbarAdvancedSettingsItem";
NSString *SCErrorDomain = @"ScrupError";

int main(int argc, const char *argv[]) {
	// create a global operation queue
	g_opq = [[NSOperationQueue alloc] init];

	// read "debug" from user defaults
	#if DEBUG
	g_debug = YES;
	#else
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	if (ud)
		g_debug = [ud boolForKey:@"debug"];
	#endif

	// setup logging
	[ASLLogger setFacility:@"se.notion.Scrup"];
	if (g_debug) {
		// Send no messages to syslogd, but instead send everything on stderr. We do this
		// instead of rising the connection level since default syslogd conf in OS X discards
		// info and debug messages by default. The stderrthing is a trick which normalizes
		// all messages to warning.
		ASLLogger *log = [ASLLogger defaultLogger];
		log.connection.level = ASLLoggerLevelNone;
		[log addFileHandle:[NSFileHandle fileHandleWithStandardError]];
		[log debug:@"started in debug mode"];
	}

	// main runloop
	NSApplicationMain(argc, argv);

	// tear down operation queue
	[g_opq cancelAllOperations];
	NSArray *ops = g_opq.operations;
	if ([ops count]) {
		NSLog(@"waiting for %lu operations to complete...", (unsigned long)[ops count]);
		[g_opq waitUntilAllOperationsAreFinished];
	}

	return 0;
}
