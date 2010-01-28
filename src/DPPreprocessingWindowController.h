#import "DPImageView.h"
#import <Quartz/Quartz.h>

@class DPAppDelegate;

@interface DPPreprocessingWindowController : NSWindowController <NSWindowDelegate> {
	IBOutlet DPAppDelegate *appDelegate;
	IBOutlet NSButton *defaultButton; // "Upload"
	IBOutlet NSTextField *filenameTextField;
	IBOutlet IKImageView *imageView;
	IBOutlet NSButton *commitActionButton; // crop, etc
	IBOutlet NSSegmentedControl *toolbarSegmentedControl;
	
	NSString *screenshotPath;
	NSMutableDictionary *screenshotMeta;
	
	void (^commitBlock)(NSString *path);
	void (^cancelBlock)(void);
	
	NSDictionary *imageProperties;
	NSString *imageUTType;
}

- (void)openImageAtURL:(NSURL*)url;

- (IBAction)performCancel:(id)sender; // OK button
- (IBAction)performCommit:(id)sender; // Cancel button

- (IBAction)switchToolMode:(id)sender;
- (IBAction)toggleIKInspector:(id)sender;

- (IBAction)crop:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;

- (void)editScreenshotAtPath:(NSString *)path
											 meta:(NSMutableDictionary *)meta
								commitBlock:(void(^)(NSString *path))b1 // path: where the file can be found (might have been renamed)
								cancelBlock:(void(^)(void))b2;

@end
