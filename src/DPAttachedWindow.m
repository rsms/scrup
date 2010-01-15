#import "DPAttachedWindow.h"

@implementation DPAttachedWindow

- (void)becomeKeyWindow {
	[self setLevel:NSStatusWindowLevel];
	[super becomeKeyWindow];
}

- (void)resignKeyWindow {
	[self setLevel:NSNormalWindowLevel];
	[super resignKeyWindow];
}

@end
