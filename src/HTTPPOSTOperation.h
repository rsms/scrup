@interface HTTPPOSTOperation : NSOperation {
	NSString *path;
	NSURL *url;
	NSMutableURLRequest *request;
	NSHTTPURLResponse *response;
	NSData *responseData;
	id delegate;
}
@property(assign) NSString *path;
@property(assign) NSURL *url;
@property(assign) NSMutableURLRequest *request;
@property(assign) NSHTTPURLResponse *response;
@property(assign) NSData *responseData;
@property(assign) id delegate;
-(id)initWithPath:(NSString *)path URL:(NSURL *)url delegate:(id)delegate;
@end

@protocol HTTPPOSTOperationDelegate
-(void)httpPostOperationWillBegin:(HTTPPOSTOperation *)op;
-(void)httpPostOperationDidSucceed:(HTTPPOSTOperation *)op;
-(void)httpPostOperationDidFail:(HTTPPOSTOperation *)op withError:(NSError *)error;
@end
