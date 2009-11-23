@interface NSBitmapImageRep (HUAdditions)
- (NSData *)JPEGRepresentationWithCompressionFactor:(float)compression progressive:(BOOL)progressive;
- (NSData *)PNGRepresentationAsProgressive:(BOOL)progressive;
@end
