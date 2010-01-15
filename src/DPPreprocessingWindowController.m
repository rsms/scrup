#import "DPPreprocessingWindowController.h"
#import "DPAppDelegate.h"

@interface IKImageView (IKPrivate_DPPreprocessingWindowController)
- (struct CGImage *)imageWithOptions:(id)arg1;
@end

@implementation DPPreprocessingWindowController

- (void)awakeFromNib {
	imageView.hasVerticalScroller = YES;
	imageView.hasHorizontalScroller = YES;
	imageView.autohidesScrollers = YES;
	[commitActionButton setTarget:self];
	[self switchToolMode:toolbarSegmentedControl];
}


- (void)openImageAtURL:(NSURL*)url {
	// use ImageIO to get the CGImage, image properties, and the image-UTType
	CGImageRef          image = NULL;
	CGImageSourceRef    isr = CGImageSourceCreateWithURL( (CFURLRef)url, NULL);
	if (isr) {
		image = CGImageSourceCreateImageAtIndex(isr, 0, NULL);
		if (image) {
			imageProperties = (NSDictionary*)CGImageSourceCopyPropertiesAtIndex(isr, 0, (CFDictionaryRef)imageProperties);
			imageUTType = (NSString*)CGImageSourceGetType(isr);
		}
	}
	if (image) {
		[imageView setImage:image imageProperties:imageProperties];
	}
}


- (void)editScreenshotAtPath:(NSString *)path
											 meta:(NSMutableDictionary *)meta
								commitBlock:(void(^)(NSString *path))b1
								cancelBlock:(void(^)(void))b2
{
	screenshotPath = path;
	screenshotMeta = meta;
	commitBlock = b1 ? [b1 copy] : nil;
	cancelBlock = b2 ? [b2 copy] : nil;
	
	[filenameTextField setStringValue:[[screenshotPath lastPathComponent] stringByDeletingPathExtension]];
	imageView.autoresizes = YES;
	[self openImageAtURL:[NSURL fileURLWithPath:screenshotPath]];
}


- (void)clear {
	screenshotPath = nil;
	screenshotMeta = nil;
	commitBlock = nil;
	cancelBlock = nil;
	[imageView setImageWithURL:nil]; // dangerous?
}

- (IBAction)performCancel:(id)sender {
	#if DEBUG
		NSLog(@"%s %@", _cmd, sender);
	#endif
	[[self window] close];
	if (cancelBlock)
		cancelBlock();
	[self clear];
}

- (IBAction)performCommit:(id)sender {
	#if DEBUG
		NSLog(@"%s %@", _cmd, sender);
	#endif
	if (commitBlock) {
		NSString *lcpath, *path = screenshotPath;
		NSString *fn = [filenameTextField stringValue];
		
		// renamed?
		if (![[path lastPathComponent] isEqualToString:fn]) {
			// filename changed -- move file
			path = [screenshotPath stringByDeletingLastPathComponent];
			path = [path stringByAppendingPathComponent:fn];
			
			// add file extension (this can definitely be done smarter)
			lcpath = [path lowercaseString];
			if (![lcpath hasSuffix:@".png"] && ![lcpath hasSuffix:@".jpg"] && ![lcpath hasSuffix:@".jpeg"]) {
				// Add original extension
				path = [path stringByAppendingPathExtension:[screenshotPath pathExtension]];
			}
			
			NSError *error = nil;
			if (![[NSFileManager defaultManager] moveItemAtPath:screenshotPath toPath:path error:&error]) {
				NSLog(@"%s failed to rename '%@' --> '%@' because: %@", _cmd, screenshotPath, path, error);
				path = screenshotPath;
			}
		}
		
		// todo: track ismodified
		
		// get and save image
		CGImageRef image;
		// This official API returns an image w/o any annotations or other funky stuff.
		//image = [imageView image];
		// This inofficial, private method do:
		image = [imageView imageWithOptions:[NSDictionary dictionaryWithObjectsAndKeys:nil]];
		
		if (image) {
			// use ImageIO to save the image in the same format as the original
			NSURL *url = [NSURL fileURLWithPath:path];
			CGImageDestinationRef dest = CGImageDestinationCreateWithURL((CFURLRef)url, (CFStringRef)imageUTType, 1, NULL);
			if (dest) {
				CGImageDestinationAddImage(dest, image, (CFDictionaryRef)imageProperties);
				CGImageDestinationFinalize(dest);
				CFRelease(dest);
			}
			else {
				NSLog(@"%s error: CGImageDestinationCreateWithURL returned nil", _cmd);
				image = nil;
			}
		}
		else {
			NSLog(@"%s error: no image ([imageView image] returned nil)", _cmd);
		}
		
		// continue
		commitBlock(path);
	}
	else {
		NSLog(@"%s warning: no commitBlock (nil)", _cmd);
	}
	[self clear];
}


- (IBAction)switchToolMode:(id)sender {
	NSInteger newTool;
	BOOL didEnableComplementaryButton = NO;
	
	if ([sender isKindOfClass:[NSSegmentedControl class]])
		newTool = [sender selectedSegment];
	else
		newTool = [sender tag];
	
	switch (newTool) {
		case 0:
			[imageView setCurrentToolMode:IKToolModeMove];
			break;
		case 1:
			[imageView setCurrentToolMode:IKToolModeSelect];
			[commitActionButton setImage:[NSImage imageNamed:@"crop"]];
			[commitActionButton setEnabled:YES];
			[commitActionButton setToolTip:@"Crop image to selected area"];
			[commitActionButton setAction:@selector(crop:)];
			[commitActionButton setTarget:self];
			didEnableComplementaryButton = YES;
			break;
		case 2: // arrow
			// Types:
			// 0: oval
			// 1: text
			// 2: rectangle
			// 3: arrow
			[imageView setCurrentToolMode:IKToolModeAnnotate];
			[imageView setAnnotationType:3];
			break;
		case 3: // ellipse
			[imageView setCurrentToolMode:IKToolModeAnnotate];
			[imageView setAnnotationType:0];
			break;
		case 4: // rect
			[imageView setCurrentToolMode:IKToolModeAnnotate];
			[imageView setAnnotationType:2];
			break;
		case 5: // text
			[imageView setCurrentToolMode:IKToolModeAnnotate];
			[imageView setAnnotationType:1];
			[commitActionButton setImage:[NSImage imageNamed:@"BottomTB_fonts"]];
			[commitActionButton setEnabled:YES];
			[commitActionButton setToolTip:@"Change font"];
			[commitActionButton setAction:@selector(orderFrontFontPanel:)];
			[commitActionButton setTarget:[NSFontManager sharedFontManager]];
			didEnableComplementaryButton = YES;
			break;
	}
	
	// update commitActionButton state
	if (!didEnableComplementaryButton && [commitActionButton isEnabled]) {
		[commitActionButton setImage:nil];
		[commitActionButton setToolTip:nil];
		[commitActionButton setEnabled:NO];
	}
}


- (IBAction)crop:(id)sender {
	BOOL shouldZoomToFit = (imageView.zoomFactor != 1.0);
	
	// test if the image is currently zoomed to fit
	if (shouldZoomToFit) {
		NSSize z1, z2, sz = [imageView imageSize];
		z1 = [imageView convertImageRectToViewRect:NSMakeRect(0.0, 0.0, sz.width, sz.height)].size;
		z2 = [imageView bounds].size;
		if (z1.width != z2.width && z1.height != z2.height)
			shouldZoomToFit = NO;
	}
	
	// perform crop
	[imageView crop:sender];
	
	// zoom
	if (shouldZoomToFit) {
		[imageView zoomImageToFit:sender];
	}
}


- (IBAction)toggleIKInspector:(id)sender {
	[imageView showInspector:sender];
	// todo: read state and to A or B
	// - (void)closeInspector:(id)arg1;
}


#define ZOOM_IN_FACTOR  1.414214
#define ZOOM_OUT_FACTOR 0.7071068


- (IBAction)zoomIn:(id)sender {
	[imageView zoomIn:sender];
}

- (IBAction)zoomOut:(id)sender {
	[imageView zoomOut:sender];
}

@end
