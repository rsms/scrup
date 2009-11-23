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
	//connectionRetryInterval = 10.0;
	
	return self;
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
	if ([delegate respondsToSelector:@selector(httpPostOperationWillBegin:)]) {
		[delegate httpPostOperationWillBegin:self];
	}
	else {
		NSLog(@"[%@] sending request %@ %@ %@", self, [request HTTPMethod], [request URL],
					[request allHTTPHeaderFields]);
	}
	
	[self sendRequestAllowingRetries:20];
}

-(void)sendRequestAllowingRetries:(int)nretries {
	NSError *err;
	NSDictionary *fattrs;
	
	// send and recv...
	responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&err];
	
	// error check
	if (!responseData && err && [err domain] == NSURLErrorDomain && nretries) {
		NSInteger code = [err code];
		// retry forever?
		/*if (code == kCFURLErrorCannotConnectToHost ||
				code == kCFURLErrorNetworkConnectionLost ||
				code == kCFURLErrorNotConnectedToInternet ||
				code == kCFErrorHTTPConnectionLost) {
			// Discussion: Currently we do not retry connections based on the assumption
			// that you do not want old screenshots to be uploaded when you get an internet connection
			// at a later date. Fall through to error callback instead.
			//[NSThread sleepForTimeInterval:connectionRetryInterval];
			//[self sendRequestAllowingRetries:nretries]; // do not modify <nretries>
		}
		else*/ if (code == kCFURLErrorRequestBodyStreamExhausted) {
			#if DEBUG
			NSLog(@"warning: [%@] got CFURLErrorRequestBodyStreamExhausted from CF. Retrying...", self);
			#endif
			// wait a short amount of time then try again once
			[NSThread sleepForTimeInterval:0.5];
			[request setHTTPBodyStream:[NSInputStream inputStreamWithFileAtPath:path]];
			if ((fattrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&err]))
				[request setValue:[NSString stringWithFormat:@"%llu", [fattrs fileSize]] forHTTPHeaderField:@"Content-Length"];
			[self sendRequestAllowingRetries:nretries-1];
			return;
		}
	}
	
	// parse response
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
				NSLog(@"[%@] succeeded with HTTP %d %@ %@", self, 
							[response statusCode], [response allHeaderFields],
							[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding]);
			}
		}
		// response: failure
		else {
			NSString *rspStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
			if ([delegate respondsToSelector:@selector(httpPostOperationDidFail:withError:)]) {
				err = [NSError errorWithDomain:NSStringFromClass(isa)
																	code:[response statusCode] 
															userInfo:[NSDictionary dictionaryWithObject:rspStr forKey:NSLocalizedDescriptionKey]];
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
