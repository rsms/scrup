#import "DPAppDelegate.h"

NSOperationQueue *g_opq;
NSString *DPToolbarFoldersItemIdentifier = @"DPToolbarFoldersItem";
NSString *DPToolbarSettingsItemIdentifier = @"DPToolbarSettingsItem";
NSString *DPErrorDomain = @"DPError";

int main(int argc, const char *argv[]) {
	g_opq = [[NSOperationQueue alloc] init];
	
	NSApplicationMain(argc, argv);
	
	[g_opq cancelAllOperations];
	NSArray *ops = g_opq.operations;
	if ([ops count]) {
		NSLog(@"waiting for %u operations to complete...", [ops count]);
		[g_opq waitUntilAllOperationsAreFinished];
	}
	
	return 0;
}
