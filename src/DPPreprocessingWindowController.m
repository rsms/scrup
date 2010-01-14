#import "DPPreprocessingWindowController.h"
#import "DPAppDelegate.h"

@implementation DPPreprocessingWindowController

- (void)editScreenshotAtPath:(NSString *)path
											 meta:(NSMutableDictionary *)meta
								commitBlock:(void(^)(NSString *path))b1
								cancelBlock:(void(^)(void))b2
{
	screenshotPath = path;
	screenshotMeta = meta;
	commitBlock = b1 ? [b1 copy] : nil;
	cancelBlock = b2 ? [b2 copy] : nil;
	
	[filenameTextField setStringValue:[screenshotPath lastPathComponent]];
	[imageView setImageWithURL:[NSURL fileURLWithPath:screenshotPath]];
}

- (void)clear {
	screenshotPath = nil;
	screenshotMeta = nil;
	commitBlock = nil;
	cancelBlock = nil;
	[imageView setImageWithURL:nil]; // dangerous?
}

- (IBAction)performCancel:(id)sender {
	NSLog(@"%s %@", _cmd, sender);
	[[self window] close];
	if (cancelBlock)
		cancelBlock();
	[self clear];
}

- (IBAction)performCommit:(id)sender {
	NSLog(@"%s %@", _cmd, sender);
	if (commitBlock) {
		NSString *path = screenshotPath;
		NSString *fn = [filenameTextField stringValue];
		if (![[path lastPathComponent] isEqualToString:fn]) {
			// filename changed -- move file
			path = [[screenshotPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:fn];
			NSError *error = nil;
			if (![[NSFileManager defaultManager] moveItemAtPath:screenshotPath toPath:path error:&error]) {
				NSLog(@"%s failed to rename '%@' --> '%@' because: %@", _cmd, screenshotPath, path, error);
				path = screenshotPath;
			}
		}
		commitBlock(path);
	}
	[self clear];
}

@end
