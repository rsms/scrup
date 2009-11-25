#import "NSBitmapImageRep+HUAdditions.h"

@implementation NSBitmapImageRep (HUAdditions)

- (NSData *)JPEGRepresentationWithCompressionFactor:(float)compression progressive:(BOOL)progressive {
	return [self representationUsingType:NSJPEGFileType
		properties:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSDecimalNumber numberWithFloat:compression], NSImageCompressionFactor,
			[NSNumber numberWithBool:progressive], NSImageProgressive, nil]];
}

- (NSData *)PNGRepresentationAsProgressive:(BOOL)progressive {
	return [self representationUsingType:NSPNGFileType
		properties:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithBool:progressive], NSImageProgressive, nil]];
}

- (NSBitmapImageRep *)bitmapImageRepByConvertingTosRGBColorSpace {
	return [self bitmapImageRepByConvertingToColorSpace:[NSColorSpace sRGBColorSpace]
																			renderingIntent:NSColorRenderingIntentDefault];
}

- (NSData *)PNGRepresentationInsRGBColorSpace {
	return [[self bitmapImageRepByConvertingTosRGBColorSpace] PNGRepresentationAsProgressive:NO];
}

@end
