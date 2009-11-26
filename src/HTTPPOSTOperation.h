@interface HTTPPOSTOperation : NSOperation {
	NSString *path;
	NSURL *url;
	NSMutableURLRequest *request;
	NSHTTPURLResponse *response;
	NSData *responseData;
	id delegate;
	//NSTimeInterval connectionRetryInterval;
	ASLLogger *log;
}
@property(assign) NSString *path;
@property(assign) NSURL *url;
@property(assign) NSMutableURLRequest *request;
@property(assign) NSHTTPURLResponse *response;
@property(assign) NSData *responseData;
@property(assign) id delegate;
@property(assign) ASLLogger *log;
-(id)initWithPath:(NSString *)path URL:(NSURL *)url delegate:(id)delegate;
-(void)sendRequestAllowingRetries:(int)nretries;
@end

@protocol HTTPPOSTOperationDelegate
-(BOOL)preprocessFileBeforeSending:(HTTPPOSTOperation *)op;
-(void)httpPostOperationWillBegin:(HTTPPOSTOperation *)op;
-(void)httpPostOperationDidSucceed:(HTTPPOSTOperation *)op;
-(void)httpPostOperationDidFail:(HTTPPOSTOperation *)op withError:(NSError *)error;
@end
