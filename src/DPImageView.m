#import "DPImageView.h"
#import <objc/runtime.h>

#import "IKImageLayer.h"




@interface IKRootLayer : CALayer
{
	IKImageView *_ikImageView;
	IKImageLayer *_ikImageLayer;
}

- (struct CGPoint)ikConvertEventLocationInWindow:(struct CGPoint)arg1 toLayer:(id)arg2;
- (id)ikRootLayer;
- (id)ikView;
- (id)init;
- (void)setAnchorPoint:(struct CGPoint)arg1;
- (void)setBounds:(struct CGRect)arg1;
- (void)setFrame:(struct CGRect)arg1;
- (void)setIKView:(id)arg1;
- (void)setPosition:(struct CGPoint)arg1;
- (void)setup:(id)arg1;

@end




@interface IKComposer : NSObject
{
	IKImageView *_view;
	id _viewDelegate;
	IKRootLayer *_rootLayer;
	IKImageBackgroundLayer *_imageBackgroundLayer;
	IKImageLayer *_imageLayer;
	CALayer *_userOverlayImage;
	CALayer *_userOverlayRoot;
	CALayer *_mouseDownLayer;
	NSMutableArray *_layers;
	NSMutableDictionary *_registeredLayers;
	NSURL *_URL;
	/*IKFilterChain*/id *_filterChain;
	long long _toolMode;
	long long _oldToolMode;
	int _selectionType;
	int _annotationType;
	int _maxTextureSize;
	NSColor *_backgroundColor;
	struct CGColor *_cgBackgroundColor;
	BOOL _viewDelegateRespondsToWillChange;
	BOOL _viewDelegateRespondsToDidChange;
	BOOL _viewDelegateRespondsToDidChangeWithParameters;
	BOOL _viewDelegateRespondsToUndoManagerForOperation;
	BOOL _needToCreateImageForImageState;
	BOOL _isInInterfaceBuilderApp;
	BOOL _isInInterfaceBuilderSimulator;
	BOOL _reuseImageLayer;
	BOOL _isOpaque;
}
@end

@interface IKComposer (Partial)
- (void)scrollToPoint:(struct CGPoint)arg1;
- (void)scrollToRect:(struct CGRect)arg1;
- (void)setImageZoomFactor:(double)arg1 centerPoint:(struct CGPoint)arg2;
// ...
@end

@interface NSObject (PrivateMemberAccess)
- (id)instanceMemberNamed:(const char *)memberName;
@end
@implementation NSObject (PrivateMemberAccess)
- (id)instanceMemberNamed:(const char *)memberName {
	void *p = nil;
	object_getInstanceVariable(self, memberName, &p);
	return (id)p;
}
@end


@implementation DPImageView

- (DP_IKImageViewPrivateData *)privateData {
	return (DP_IKImageViewPrivateData *)[self instanceMemberNamed:"_privateData"];
}
- (IKComposer *)composer {
	return (IKComposer *)[[self privateData] instanceMemberNamed:"_composer"];
}
- (IKImageLayer *)imageLayer {
	return (IKImageLayer *)[[self privateData] instanceMemberNamed:"_imageLayer"];
}


- (void)dpCenter {
	//IKComposer *composer = [self composer];
	//IKImageLayer *imageLayer = [self imageLayer];
	IKImageLayer *rootLayer = [[self privateData] instanceMemberNamed:"_rootLayer"];
	//[rootLayer setPosition:CGPointMake(200.0, 200.0)];
	//[composer setImageZoomFactor:2.0 centerPoint:CGPointMake(200.0, 200.0)];
}

- (void)preZoom {
	NSLog(@"%s", _cmd);
}

- (void)postZoom {
	NSLog(@"%s", _cmd);
}

@end
