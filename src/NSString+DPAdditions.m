#import "NSString+DPAdditions.h"

@implementation NSString (DPAdditions)

- (NSString *)shellArgumentRepresentation {
	return [NSString stringWithFormat:@"'%@'", [self stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
}

@end
