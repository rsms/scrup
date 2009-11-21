@interface NSError (DPAdditions)
+ (NSError *)droPubErrorWithDescription:(NSString *)msg code:(NSInteger)code;
+ (NSError *)droPubErrorWithDescription:(NSString *)msg;
+ (NSError *)droPubErrorWithCode:(NSInteger)code format:(NSString *)format, ...;
+ (NSError *)droPubErrorWithFormat:(NSString *)format, ...;
@end
