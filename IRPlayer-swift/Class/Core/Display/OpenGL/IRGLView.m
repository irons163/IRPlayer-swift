//
//  IRGLView.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <IRPlayer_swift/IRPlayer_swift-Swift.h>
#import "IRGLView.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/EAGL.h>
#import "IRMovieDecoder.h"
//#import "VideoDecoder.h"
#import "IRGLTransformController2D.h"
#import "IRGLTransformController3DFisheye.h"
#import "IRGLProjectionOrthographic.h"
#import "IRGLProjectionEquirectangular.h"
#import "IRGLProgram2D.h"
#import "IRGLProgram2DFisheye2Pano.h"
#import "IRGLProgram3DFisheye.h"
#import "IRGLProgram2DFisheye2Persp.h"
#import "IRGLProgramFactory.h"
#import "IRePTZShiftController.h"
#import "IRGLRenderMode.h"
#import "IRGLProgram2DFactory.h"
#import "IRGLRenderModeFactory.h"
#import <pthread.h>
#include <sys/time.h>
//#import "IRAVPlayer.h"

@interface IRGLRenderMode(BuildIRGLProgram)

@end

@implementation IRGLRenderMode(BuildIRGLProgram)

-(void)buildIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    _program = [programFactory createIRGLProgramWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    [self.shiftController setProgram:self.program];
    [self setDefaultScale:self.defaultScale];
    [self setContentMode:self.contentMode];
    [self setting];
    
    [self.delegate programDidCreate:_program];
}

@end

@interface IRGLView()

@property (nonatomic) IRPlayerImp * abstractPlayer;

@end

@implementation IRGLView {
    EAGLContext     *_context;
    GLuint          _framebuffer;
    GLuint          _renderbuffer;
    
    GLint           _backingWidth;
    GLint           _backingHeight;
    GLint           _viewportWidth;
    GLint           _viewportHeight;
    
    dispatch_queue_t queue;
    IRPixelFormat irPixelFormat;
    
    NSArray *_programs;
    IRGLProgram2D *_currentProgram;
    NSUInteger lastFrameWidth;
    NSUInteger lastFrameHeight;
    
//    BOOL isGLRenderContentModeChangable;
//    BOOL isTouchedInProgram;
    BOOL willDoSnapshot;
    
    IRGLRenderMode* mode;
    NSArray<IRGLRenderMode*>* _modes;
    CGRect viewprotRange;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.frame = CGRectMake(0, 0, 100, 100);
        [self initDefaultValue];
        irPixelFormat = YUV_IRPixelFormat;
        [self initGLWithPixelFormat:irPixelFormat];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self initDefaultValue];
        irPixelFormat = YUV_IRPixelFormat;
        [self initGLWithPixelFormat:irPixelFormat];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
             decoder:(IRMovieDecoder *)decoder {
    self = [super initWithFrame:frame];
    if (self) {
        [self initDefaultValue];
        [self initGLWithIRMovieDecoder:decoder];
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame
         withPlayer:(IRPlayerImp *)abstractPlayer {
    self = [super initWithFrame:frame];
    if (self) {
        self.abstractPlayer = abstractPlayer;
        [self initDefaultValue];
//        [self initGLWithIRMovieDecoder:decoder];
        irPixelFormat = YUV_IRPixelFormat;
        [self initGLWithPixelFormat:irPixelFormat];
    }
    
    return self;
}

- (void)initDefaultValue {
    _modes = [NSArray array];
}

- (void)initGLWithIRMovieDecoder:(IRMovieDecoder *)decoder {
    if ([decoder setupVideoFrameFormat:IRFrameFormatYUV]) {
        irPixelFormat = YUV_IRPixelFormat;
    } else {
        irPixelFormat = RGB_IRPixelFormat;
    }
    
    [self initGLWithPixelFormat:irPixelFormat];
}

- (EAGLContext *)setupContext {
    EAGLContext *context = nil;
    context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if(!context)
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    return context;
}

- (void)initGLWithPixelFormat:(IRPixelFormat)irPixelFormat {
    [self initRenderQueue];
    
    [CATransaction flush];
    
    [EAGLContext setCurrentContext:_context];
    
    CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
    
    dispatch_sync(queue, ^{
        [self reset];
        
        eaglLayer.contentsScale = [[UIScreen mainScreen] scale];
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        
        self->_context = [self setupContext];
        
        if (!self->_context ||
            ![EAGLContext setCurrentContext:self->_context]) {
            
            NSLog(@"failed to setup EAGLContext");
            return;
        }
        
        glGenFramebuffers(1, &self->_framebuffer);
        glGenRenderbuffers(1, &self->_renderbuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, self->_framebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, self->_renderbuffer);
        [self->_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &self->_backingWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &self->_backingHeight);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, self->_renderbuffer);
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE) {
            
            NSLog(@"failed to make complete framebuffer object %x", status);
            return;
        }
        
        GLenum glError = glGetError();
        if (GL_NO_ERROR != glError) {
            NSLog(@"failed to setup GL %x", glError);
            return;
        }
    });
    
    viewprotRange = CGRectMake(0, 0, self->_backingWidth, self->_backingHeight);
    
    [self setupModes];
    
    NSLog(@"OK setup GL");
}

- (void)closeGLView {
    if(queue){
        dispatch_sync(queue, ^{
            [EAGLContext setCurrentContext:self->_context];
            [self reset];
        });
    }
}

//For NV12, This is important that need to glDeleteFramebuffers and glDeleteRenderbuffers before set _renderer = nil.
//If not, when change live view's resolustion, it render nothing. The reason is unknown.
-(void)reset{
    if (_framebuffer) {
        glDeleteFramebuffers(1, &_framebuffer);
        _framebuffer = 0;
    }
    
    if (_renderbuffer) {
        glClear(GL_COLOR_BUFFER_BIT);
        glDeleteRenderbuffers(1, &_renderbuffer);
        _renderbuffer = 0;
    }
    
    if (_programs) {
        for(IRGLProgram2D *program in _programs){
            if (program) {
                [program releaseProgram];
            }
        }
        _programs = nil;
    }
    
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    _context = nil;
}

- (void)initRenderQueue {
    if(!queue)
        queue = dispatch_queue_create("render.queue", DISPATCH_QUEUE_SERIAL);
}

- (void)setDecoder:(VideoDecoder *)decoder {
    irPixelFormat = NV12_IRPixelFormat;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self initGLWithPixelFormat:self->irPixelFormat];
    });
}

- (void)setPixelFormat:(IRPixelFormat)pixelFormat {
    irPixelFormat = pixelFormat;
    
    [self initGLWithPixelFormat:irPixelFormat];
}



- (void)dealloc {
    [self reset];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateViewPort:1.0];
}

- (void)updateViewPort:(float)viewportScale {
    if(!queue)
        return;
    
    [CATransaction flush];
    
    dispatch_sync(queue, ^{
        BOOL hasLoadShaders = YES;
        if(self->_backingWidth == 0 && self->_backingHeight == 0) {
            hasLoadShaders = NO;
        }
        
        [EAGLContext setCurrentContext:self->_context];
        CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
        eaglLayer.contentsScale = viewportScale * [[UIScreen mainScreen] scale];
        glBindFramebuffer(GL_FRAMEBUFFER, self->_framebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, self->_renderbuffer);
        [self->_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &self->_backingWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &self->_backingHeight);
        NSLog(@"_backingWidth:%d",self->_backingWidth);
//        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, self->_renderbuffer);
        
        if (!hasLoadShaders && (self->_backingWidth != 0 || self->_backingHeight != 0)) {
            [self loadShaders];
        }
    });
    
    [self resetAllViewport:_backingWidth :_backingHeight resetTransform:YES];
}

- (void)setContentMode:(UIViewContentMode)contentMode {
    [super setContentMode:contentMode];
    
//    if(isGLRenderContentModeChangable)
//        [self changeGLRenderContentMode];
}

- (void)changeGLRenderContentMode {
    IRGLRenderContentMode irGLViewContentMode;
    
    switch (self.abstractPlayer.viewGravityMode) {
        case IRGravityModeResizeAspect:
            irGLViewContentMode = IRGLRenderContentModeScaleAspectFit;
            break;
        case IRGravityModeResizeAspectFill:
            irGLViewContentMode = IRGLRenderContentModeScaleAspectFill;
            break;
        case IRGravityModeResize:
            irGLViewContentMode = IRGLRenderContentModeScaleToFill;
            break;
        default:
            irGLViewContentMode = IRGLRenderContentModeScaleAspectFit;
            break;
    }
    
    for(IRGLProgram2D *program in _programs){
        program.contentMode = irGLViewContentMode;
    }
}

- (void)resetAllViewport:(float)w :(float)h resetTransform:(BOOL)resetTransform {
    viewprotRange = CGRectMake(0, 0, w, h);
    
    for(IRGLProgram2D *program in _programs){
        [program setViewprotRange:CGRectMake(0, 0, w, h) resetTransform:NO];
    }
    [self render:nil];
}

- (void)updateScopeByFx:(float)fx fy:(float)fy dsx:(float)dsx dsy:(float)dsy {
    [_currentProgram didPinchByfx:fx fy:fy dsx:dsx dsy:dsy];
    [self render:nil];
}

- (void) scrollByDx:(float)dx dy:(float)dy {
    [_currentProgram didPanBydx:dx dy:dy];
    [self render:nil];
}

- (void)scrollByDegreeX:(float)degreex degreey:(float)degreey {
    [_currentProgram didPanByDegreeX:degreex degreey:degreey];
    [self render:nil];
}

- (void)render:(nullable IRFFVideoFrame *)frame {
    if(!queue || !_currentProgram)
        return;
    
    dispatch_sync(queue, ^{
        [self setCurrentContext];
        [self bindCurrentFramebuffer];
        
        if (frame) {
            [self->_currentProgram setRenderFrame:frame];
            lastFrameWidth = frame.width;
            lastFrameHeight = frame.height;
        }
        
        [self->_currentProgram clearBuffer];
        
        //        NSDate *methodStart = [NSDate date];
        [self->_currentProgram render];
        
        //        glFinish();
        
        [self bindCurrentRenderBuffer];
        [self presentRenderBuffer];
        
        //        NSDate *methodFinish = [NSDate date];
        //        NSTimeInterval executionTime = [methodFinish timeIntervalSinceDate:methodStart];
        //                NSLog(@"executionTime = %f", executionTime);
        
        [self saveSnapShot];
    });
}

- (void)setRenderModes:(NSArray<IRGLRenderMode*>*)modes {
    _modes = modes;
    
    [self initGLWithPixelFormat:irPixelFormat];
}

- (void)initModes {
    NSMutableArray* array = [NSMutableArray array];
    if(_modes.count == 0) {
        _modes = [IRGLRenderModeFactory createNormalModesWithParameter:nil];
    }
    
    for(IRGLRenderMode* m in _modes){
        [m buildIRGLProgramWithPixelFormat:irPixelFormat withViewprotRange:viewprotRange withParameter:m.parameter];
        if(m.program)
            [array addObject:m.program];
    }
    
    _programs = [NSArray arrayWithArray:array];
}

- (void)loadShaders {
    [EAGLContext setCurrentContext:self->_context];
    
    for(IRGLProgram2D *program in self->_programs){
        if (![program loadShaders]) {
            return;
        }
    }
}

- (void)setupModes {
    [self initModes];
    
    dispatch_sync(queue, ^{
        [self loadShaders];
    });
    self.contentMode = UIViewContentModeScaleAspectFit;
    [self setContentMode:self.contentMode];
    
    [self chooseRenderMode:[_modes firstObject] withImmediatelyRenderOnce:NO];
}

- (NSArray*)getRenderModes{
    return _modes;
}

- (IRGLRenderMode*)getCurrentRenderMode{
    return mode;
}

- (BOOL)chooseRenderMode:(IRGLRenderMode*)renderMode withImmediatelyRenderOnce:(BOOL)immediatelyRenderOnce{
    if(!queue)
        return NO;
    
    if(![_modes containsObject:renderMode])
        return NO;
    
    dispatch_sync(queue, ^{
        self->mode = renderMode;
        self->_currentProgram = self->mode.program;
        [self->mode.shiftController setProgram:self->_currentProgram];
        [_currentProgram updateTextureWidth:lastFrameWidth height:lastFrameHeight];
        self.aspect = self->mode.aspect;
        
        if(immediatelyRenderOnce){
            dispatch_async(dispatch_get_main_queue(), ^{
                [self render:nil];
            });
        }
    });
    
    return YES;
}

- (void)runSyncInQueue:(void (^)(void))block {
    dispatch_sync(queue, block);
}

- (void)setCurrentContext {
    [EAGLContext setCurrentContext:self->_context];
}

- (void)bindCurrentFramebuffer {
    glBindFramebuffer(GL_FRAMEBUFFER, self->_framebuffer);
}

- (BOOL)presentRenderBuffer {
    return [self->_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)bindCurrentRenderBuffer {
    glBindRenderbuffer(GL_RENDERBUFFER, self->_renderbuffer);
}

- (void)clearCurrentBuffer {
    [self->_currentProgram clearBuffer];
}

-(void) clearCanvas{
    if(!queue || !_currentProgram)
        return;
    
    dispatch_sync(queue, ^{
        [self setCurrentContext];
        [self bindCurrentFramebuffer];
        
        [self clearCurrentBuffer];
        
        [self bindCurrentRenderBuffer];
        [self presentRenderBuffer];
    });
}

-(void) doSnapShot
{
    willDoSnapshot = YES;
}

-(void) saveSnapShot{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self->willDoSnapshot){
            [self saveSnapshotAlbum:[self createImageFromFramebuffer]];
            self->willDoSnapshot = NO;
        }
    });
}

-(void) saveSnapshotAlbum:(UIImage *) _snap
{
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    [library writeImageToSavedPhotosAlbum:_snap.CGImage orientation:(ALAssetOrientation)_snap.imageOrientation completionBlock:^(NSURL *assetURL, NSError *error )
     {
         //            NSLog(@"IMAGE SAVED TO PHOTO ALBUM");
         [library assetForURL:assetURL
                  resultBlock:^(ALAsset *asset )
          {
              [library enumerateGroupsWithTypes:ALAssetsGroupAlbum
                                     usingBlock:^(ALAssetsGroup *group, BOOL *stop)
               {
                   
               }
                                   failureBlock:^(NSError *error)
               {
                   NSLog(@"Error:%@",error.localizedDescription);
               }];
              
              //                  NSLog(@"we have our ALAsset!");
          }
          
                 failureBlock:^(NSError *error )
          {
              NSLog(@"Error loading asset");
          }];
     }];
}


- (UIImage *)createImageFromFramebuffer {
    UIImage* imgRtn;
    CGSize size = [self.layer bounds].size;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGRect containerRect = [self.layer bounds];
    [self drawViewHierarchyInRect:containerRect afterScreenUpdates:NO];
    imgRtn = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return imgRtn;
}

typedef NS_ENUM(NSInteger, IRScrollDirectionType){
    None, //default
    Left,
    Right,
    Up,
    Down
};

- (void)cleanEmptyBuffer
{
//    [self cleanTexture];
//    
//    if ([NSThread isMainThread]) {
//        [self displayAndClear:YES];
//    } else {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [self displayAndClear:YES];
//        });
//    }
}

- (void)decoder:(IRFFDecoder *)decoder renderVideoFrame:(IRFFVideoFrame *)videoFrame {
    [self render:videoFrame];
}

- (void)setRendererType:(IRDisplayRendererType)rendererType
{
    if (_rendererType != rendererType) {
        _rendererType = rendererType;
        [self reloadView];
    }
}

- (void)reloadView
{
    [self cleanViewIgnore];
    switch (self.rendererType) {
        case IRDisplayRendererTypeEmpty:
            break;
        case IRDisplayRendererTypeAVPlayerLayer:
//            if (!self.avplayerLayer) {
//                self.avplayerLayer = [AVPlayerLayer playerLayerWithPlayer:nil];
//                [self reloadIRAVPlayer];
//                self.avplayerLayerToken = NO;
//                [self.layer insertSublayer:self.avplayerLayer atIndex:0];
//                [self reloadGravityMode];
//            }
            break;
        case IRDisplayRendererTypeAVPlayerPixelBufferVR:
//            if (!self.avplayerView) {
//                self.avplayerView = [IRGLAVView viewWithDisplayView:self];
//                IRPLFViewInsertSubview(self, self.avplayerView, 0);
//            }
            break;
        case IRDisplayRendererTypeFFmpegPexelBuffer:
        case IRDisplayRendererTypeFFmpegPexelBufferVR:
//            if (!self.ffplayerView) {
//                self.ffplayerView = [IRGLFFView viewWithDisplayView:self];
//                IRPLFViewInsertSubview(self, self.ffplayerView, 0);
//            }
            break;
    }
    [self updateDisplayViewLayout:self.bounds];
}

- (void)reloadGravityMode {
    [self changeGLRenderContentMode];
}

- (void)setAspect:(CGFloat)aspect
{
    if (_aspect != aspect) {
        _aspect = aspect;
        [self reloadViewFrame];
    }
}

- (void)updateDisplayViewLayout:(CGRect)frame {
    [self reloadViewFrame];
    [self updateViewPort:1.0];
}

- (void)reloadViewFrame
{
    CGRect superviewFrame = self.superview.bounds;
    CGFloat superviewAspect = superviewFrame.size.width / superviewFrame.size.height;
    
    if (self.aspect <= 0) {
        self.frame = superviewFrame;
        return;
    }
    
    if (superviewAspect < self.aspect) {
        CGFloat height = superviewFrame.size.width / self.aspect;
        self.frame = CGRectMake(0, (superviewFrame.size.height - height) / 2, superviewFrame.size.width, height);
    } else if (superviewAspect > self.aspect) {
        CGFloat width = superviewFrame.size.height * self.aspect;
        self.frame = CGRectMake((superviewFrame.size.width - width) / 2, 0, width, superviewFrame.size.height);
    } else {
        self.frame = superviewFrame;
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
//    [self reloadView];
}

- (void)updateFrameFromParent:(CGRect)frame {
    self.frame = frame;
    [self reloadView];
}

//- (void)reloadIRAVPlayer
//{
//#if IRPLATFORM_TARGET_OS_MAC
//    self.avplayerLayer.player = self.sgavplayer.avPlayer;
//#elif IRPLATFORM_TARGET_OS_IPHONE_OR_TV
//    if (self.avplayer.avPlayer && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
//        self.avplayerLayer.player = self.avplayer.avPlayer;
//    } else {
//        self.avplayerLayer.player = nil;
//    }
//#endif
//}

- (void)cleanView
{
    [self cleanViewCleanAVPlayerLayer:YES cleanAVPlayerView:YES cleanFFPlayerView:YES];
}

- (void)cleanViewIgnore
{
    switch (self.rendererType) {
        case IRDisplayRendererTypeEmpty:
            [self cleanView];
            break;
        case IRDisplayRendererTypeAVPlayerLayer:
            [self cleanViewCleanAVPlayerLayer:NO cleanAVPlayerView:YES cleanFFPlayerView:YES];
            break;
        case IRDisplayRendererTypeAVPlayerPixelBufferVR:
            [self cleanViewCleanAVPlayerLayer:YES cleanAVPlayerView:NO cleanFFPlayerView:YES];
            break;
        case IRDisplayRendererTypeFFmpegPexelBuffer:
        case IRDisplayRendererTypeFFmpegPexelBufferVR:
            [self cleanViewCleanAVPlayerLayer:YES cleanAVPlayerView:YES cleanFFPlayerView:NO];
            break;
    }
}

- (void)cleanViewCleanAVPlayerLayer:(BOOL)cleanAVPlayerLayer cleanAVPlayerView:(BOOL)cleanAVPlayerView cleanFFPlayerView:(BOOL)cleanFFPlayerView
{
    [self cleanEmptyBuffer];
}


@end
