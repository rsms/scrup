#import "NSWindow+DPAdditions.h"

@implementation NSWindow (DPAdditions)

- (void)setContentView:(NSView *)view display:(BOOL)display animate:(BOOL)animate {
	NSRect d = [self contentRectForFrameRect:[self frame]];
	NSSize newSize = [view bounds].size;
	NSRect frame = [self frame];
	newSize.height += (frame.size.height - d.size.height);
	newSize.width += (frame.size.width - d.size.width);
	frame.origin.y += (frame.size.height - newSize.height);
	//frame.origin.x += (frame.size.width - newSize.width);
	frame.size = newSize;
	[self setContentView:view];
	[self setFrame:frame display:display animate:animate];
}

@end
