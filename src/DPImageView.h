#import <Quartz/Quartz.h>

@class IKComposer, IKImageBackgroundLayer, IKImageLayer;
@interface DP_IKImageViewPrivateData : NSObject {
	IKComposer *_composer;
	IKImageBackgroundLayer *_backgroundLayer;
	IKImageLayer *_imageLayer;
	// partial
}
@end

@interface IKImageView (IKImageViewPublicUndocumented)
- (void)setFrame:(struct CGRect)arg1;
@end

@interface IKImageView (IKPrivate)
@property(assign) BOOL animates;
@property(assign) int annotationType;
@property(assign) CGRect selectionRect;
- (struct CGImage *)createThumbnailOfSize:(unsigned long long)arg1;
- (struct CGImage *)createThumbnailWithMaximumSize:(struct CGSize)arg1;
@end

@interface IKImageView (IKImageViewInternal)
- (void)autoResizeToRect:(struct CGRect)arg1;
- (id)backgroundLayer;
- (void)centerImage;
- (void)closeInspector:(id)arg1;
- (id)composer;
- (void)concludeDragOperation:(id)arg1;
- (void)connectToBackgroundLayer;
- (unsigned long long)draggingEntered:(id)arg1;
- (void)draggingExited:(id)arg1;
- (BOOL)embedded;
- (void)filterAdded:(id)arg1 filterChain:(id)arg2;
- (id)filterChain;
- (void)filterRemoved:(id)arg1 filterChain:(id)arg2;
- (id)imageLayer;
- (void)invalidateCursorRects;
- (BOOL)performDragOperation:(id)arg1;
- (BOOL)respondsToSelector:(SEL)arg1;
- (void)saveScrollInfo:(struct CGSize)arg1 scaling:(struct CGPoint)arg2;
- (void)selectionRectAdded;
- (void)selectionRectDidChange:(struct CGRect)arg1;
- (void)selectionRectRemoved;
- (void)setEmbedded:(BOOL)arg1;
- (void)setFilterChain:(id)arg1;
- (void)setImage:(id)arg1;
- (void)setImageAlignment:(unsigned long long)arg1;
- (void)setImageFrameStyle:(unsigned long long)arg1;
- (void)setImageScaling:(unsigned long long)arg1;
- (void)setReuseImageLayer:(BOOL)arg1;
- (void)setSelectionRect:(struct CGRect)arg1;
- (void)showInspector:(id)arg1;
@end

@interface DPImageView : IKImageView {
}

- (void)dpCenter;

@end
