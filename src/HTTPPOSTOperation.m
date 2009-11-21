#import "HTTPPOSTOperation.h"

// todo: rewrite this to use async operations rather than just blocking in 
//       main while waiting for libfoundation to fill up responseData.

@interface HTTPPOSTOperation (Private)
-(NSString *)mimeTypeForFileAtPath:(NSString *)p error:(NSError **)err;
@end

@implementation HTTPPOSTOperation
@synthesize path, url, request, response, responseData, delegate;

-(id)initWithPath:(NSString *)s URL:(NSURL *)u delegate:(id)d {
	self = [super init];
	path = s;
	url = u;
	delegate = d;
	response = nil;
	responseData = nil;
	request = [[NSMutableURLRequest alloc] initWithURL:url];
}

-(NSString *)mimeTypeForFileAtPath:(NSString *)p error:(NSError **)err {
	NSString *uti, *mimeType = nil;
	if (!(uti = [[NSWorkspace sharedWorkspace] typeOfFile:p error:err]))
		return nil;
	if (err)
		*err = nil;
	if ((mimeType = (NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)uti, kUTTagClassMIMEType)))
		mimeType = NSMakeCollectable(mimeType);
	return mimeType;
}

-(void)main {
	NSError *err;
	NSString *mimeType = nil;
	
	// determine file type
	if (!(mimeType = [self mimeTypeForFileAtPath:path error:nil]))
		mimeType = @"application/octet-stream";
	
	// stat
	NSDictionary *fattrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&err];
	if (!fattrs) {
		if ([delegate respondsToSelector:@selector(httpPostOperationDidFail:withError:)])
			[delegate httpPostOperationDidFail:self withError:err];
		else
			NSLog(@"[%@] failed to read file attributes of '%@' %@ -- aborting", self, path, err);
		return;
	}
	
	// build request
	[request setHTTPMethod:@"POST"];
	[request setHTTPBodyStream:[NSInputStream inputStreamWithFileAtPath:path]];
	[request setValue:mimeType forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"%llu", [fattrs fileSize]] forHTTPHeaderField:@"Content-Length"];
	
	// perform request
	if ([delegate respondsToSelector:@selector(httpPostOperationWillBegin:)])
		[delegate httpPostOperationWillBegin:self];
	else
		NSLog(@"[%@] sending request", self);
	responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&err];
	
	// response
	if (!responseData) {
		if ([delegate respondsToSelector:@selector(httpPostOperationDidFail:withError:)])
			[delegate httpPostOperationDidFail:self withError:err];
		else
			NSLog(@"[%@] failed with error %@", self, err);
	}
	else {
		// response: success
		if ([response statusCode] < 300 && [response statusCode] >= 200) {
			if ([delegate respondsToSelector:@selector(httpPostOperationDidSucceed:)]) {
				[delegate httpPostOperationDidSucceed:self];
			}
			else {
				NSString *urlStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
				NSLog(@"[%@] succeeded with HTTP %d %@ %@", self, 
							[response statusCode], [response allHeaderFields], urlStr);
			}
		}
		// response: failure
		else {
			NSString *rspStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
			if ([delegate respondsToSelector:@selector(httpPostOperationDidFail:withError:)]) {
				err = [NSError errorWithDomain:NSStringFromClass(isa) code:[response statusCode] userInfo:[NSDictionary dictionaryWithObject:rspStr forKey:NSLocalizedDescriptionKey]];
				[delegate httpPostOperationDidFail:self withError:err];
			}
			else {
				NSLog(@"[%@] failed with HTTP %d %@ %@", self, 
							[response statusCode], [response allHeaderFields], rspStr);
			}
		}
	}
}

@end
