#import "NSError+DPAdditions.h"

@implementation NSError (DPAdditions)

+ (NSError *)droPubErrorWithDescription:(NSString *)msg code:(NSInteger)code {
	return [NSError errorWithDomain:DPErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]];
}

+ (NSError *)droPubErrorWithDescription:(NSString *)msg {
	return [NSError droPubErrorWithDescription:msg code:0];
}

+ (NSError *)droPubErrorWithCode:(NSInteger)code format:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError droPubErrorWithDescription:msg code:code];
}

+ (NSError *)droPubErrorWithFormat:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError droPubErrorWithDescription:msg code:0];
}

@end
