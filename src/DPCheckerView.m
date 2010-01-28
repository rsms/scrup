#import "DPCheckerView.h"

@implementation DPCheckerView

- (void)drawRect:(NSRect)dirtyRect {
	NSColor *color1 = [NSColor colorWithPatternImage:[NSImage imageNamed:@"checker"]];
	[color1 set];
	NSRectFill(dirtyRect);
}

@end
