
@interface NSImage (ProportionalScaling)
- (NSImage*)imageByScalingProportionallyToSize:(NSSize)targetSize;
- (NSImage*)imageByScalingProportionallyWithinSize:(NSSize)targetSize;
@end
