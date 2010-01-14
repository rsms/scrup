#import <Quartz/Quartz.h>

@class DPAppDelegate;

@interface DPPreprocessingWindowController : NSWindowController <NSWindowDelegate> {
	IBOutlet DPAppDelegate *appDelegate;
	IBOutlet NSTextField *filenameTextField;
	IBOutlet IKImageView *imageView;
	
	NSString *screenshotPath;
	NSMutableDictionary *screenshotMeta;
	
	void (^commitBlock)(NSString *path);
	void (^cancelBlock)(void);
}

- (IBAction)performCancel:(id)sender;
- (IBAction)performCommit:(id)sender;

- (void)editScreenshotAtPath:(NSString *)path
											 meta:(NSMutableDictionary *)meta
								commitBlock:(void(^)(NSString *path))b1 // path: where the file can be found (might have been renamed)
								cancelBlock:(void(^)(void))b2;

@end
