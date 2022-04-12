//
//  IRGLProgram2D.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2D.h"
#import "IRGLVertexShaderGLSL.h"
#import "IRGLFragmentRGBShaderGLSL.h"
#import "IRGLFragmentYUVShaderGLSL.h"
#import "IRGLFragmentNV12ShaderGLSL.h"
#import "IRGLProjection.h"
#import "IRGLRenderRGB.h"
#import "IRGLRenderYUV.h"
#import "IRGLRenderNV12.h"

@implementation IRGLProgram2D{
    IRGLShaderParams *shaderParams2D;
}

-(NSString*)vertexShader{
    vertexShaderString = [IRGLVertexShaderGLSL getShardString];
    return vertexShaderString;
}

-(NSString*)fragmentShader{
    switch (_pixelFormat) {
        case RGB_IRPixelFormat:
            fragmentShaderString = [IRGLFragmentRGBShaderGLSL getShardString];
            break;
        case YUV_IRPixelFormat:
            fragmentShaderString = [IRGLFragmentYUVShaderGLSL getShardString];
            break;
        case NV12_IRPixelFormat:
            fragmentShaderString = [IRGLFragmentNV12ShaderGLSL getShardString];
            break;
    }
    return fragmentShaderString;
}

-(instancetype)init{
    if(self = [self initWithPixelFormat:RGB_IRPixelFormat withViewprotRange:CGRectZero withParameter:nil]){
        
    }
    return self;
}

-(instancetype)initWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    if(self = [super init]){
        [self initShaderParams];
        
        _pixelFormat = pixelFormat;
        
        switch (_pixelFormat) {
            case RGB_IRPixelFormat:
                _renderer = [[IRGLRenderRGB alloc] init];
                NSLog(@"OK use RGB GL renderer");
                break;
            case YUV_IRPixelFormat:
                _renderer = [[IRGLRenderYUV alloc] init];
                NSLog(@"OK use YUV GL renderer");
                break;
            case NV12_IRPixelFormat:
                _renderer = [[IRGLRenderNV12 alloc] init];
                NSLog(@"OK use NV12 GL renderer");
                break;
        }
        
        [self setViewprotRange:viewprotRange];
        _parameter = parameter;
        
        self.shouldUpdateToDefaultWhenOutputSizeChanged = YES;
    }
    return self;
}

- (void)setupWithParameter:(IRMediaParameter *)parameter {
    if (!parameter) return;
}

- (void)initShaderParams {
    shaderParams2D = [[IRGLShaderParams alloc] init];
    shaderParams2D.delegate = self;
}

- (void)releaseProgram {
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
    
    if(_renderer) {
        [_renderer releaseRender];
        _renderer = nil;
    }
}

- (void)setRenderer:(id<IRGLRender>)renderer {
    _renderer = renderer;
}

- (void)setViewprotRange:(CGRect)viewprotRange {
    [self setViewprotRange:viewprotRange resetTransform:YES];
}

- (void)setViewprotRange:(CGRect)viewprotRange resetTransform:(BOOL)resetTransform{
    _viewprotRange = viewprotRange;
    
    [self.tramsformController resetViewport:viewprotRange.size.width :viewprotRange.size.height resetTransform:resetTransform];
}

- (void)setDefaultScale:(float)scale{
    IRGLScaleRange* oldScaleRange = self.tramsformController.scaleRange;
    IRGLScaleRange* newSScaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:oldScaleRange.minScaleX minScaleY:oldScaleRange.minScaleY maxScaleX:oldScaleRange.maxScaleX maxScaleY:oldScaleRange.maxScaleY defaultScaleX:scale defaultScaleY:scale];
    self.tramsformController.scaleRange = newSScaleRange;
}

- (CGPoint)getCurrentScale{
    return CGPointMake([self.tramsformController getDefaultTransformScale].x == 0 ? 0 :[self.tramsformController getScope].scaleX / [self.tramsformController getDefaultTransformScale].x, [self.tramsformController getDefaultTransformScale].y == 0 ? 0 :[self.tramsformController getScope].scaleY / [self.tramsformController getDefaultTransformScale].y);
}

- (void)setTramsformController:(IRGLTransformController *)tramsformController{
    _tramsformController = tramsformController;
}

- (BOOL)touchedInProgram:(CGPoint)touchedPoint{
    return (CGRectContainsPoint(_viewprotRange, touchedPoint));
}

- (void)setContentMode:(IRGLRenderContentMode)contentMode{
    if(_contentMode != contentMode){
        _contentMode = contentMode;
        [self updateTextureWidth:shaderParams2D.textureWidth height:shaderParams2D.textureHeight];
    }
}

- (CGSize)getOutputSize{
    return CGSizeMake(shaderParams2D.outputWidth, shaderParams2D.outputHeight);
}

- (BOOL)isRendererValid{
    return _renderer && _renderer.isValid ? YES : NO;
}

- (BOOL)loadShaders {
    BOOL result = NO;
    GLuint vertShader = 0, fragShader = 0;
    
    _program = glCreateProgram();
    
    vertShader = compileShader(GL_VERTEX_SHADER, [self vertexShader]);
    if (!vertShader)
        goto exit;
    
    fragShader = compileShader(GL_FRAGMENT_SHADER, [self fragmentShader]);
    if (!fragShader)
        goto exit;
    
    glAttachShader(_program, vertShader);
    glAttachShader(_program, fragShader);
    glBindAttribLocation(_program, ATTRIBUTE_VERTEX, "position");
    glBindAttribLocation(_program, ATTRIBUTE_TEXCOORD, "texcoord");
    
    glLinkProgram(_program);
    
    GLint status;
    glGetProgramiv(_program, GL_LINK_STATUS, &status);
    if (status == GL_FALSE) {
        NSLog(@"Failed to link program %d", _program);
        goto exit;
    }
    
    result = validateProgram(_program);
    
    [_renderer resolveUniforms:_program];
    [shaderParams2D resolveUniforms:_program];
    
exit:
    
    if (vertShader)
        glDeleteShader(vertShader);
    if (fragShader)
        glDeleteShader(fragShader);
    
    if (result) {
        
        NSLog(@"OK setup GL programm");
        
    } else {
        
        glDeleteProgram(_program);
        _program = 0;
    }
    
    return result;
}

- (void)setRenderFrame:(IRFFVideoFrame *)frame {
    [_renderer setVideoFrame:frame];
    
    if(frame.width != shaderParams2D.textureWidth || frame.height != shaderParams2D.textureHeight){
        [self updateTextureWidth:frame.width height:frame.height];
    }
}

- (void)updateTextureWidth:(NSUInteger)w height:(NSUInteger)h {
    [shaderParams2D updateTextureWidth:w height:h];
}

- (void)setModelviewProj:(GLKMatrix4)modelviewProj {
    [_renderer setModelviewProj:modelviewProj];
}

- (BOOL)prepareRender {
    glUseProgram(_program);
    [shaderParams2D prepareRender];
    return [_renderer prepareRender:_program];
}

- (void)clearBuffer {
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
}

- (CGRect)calculateViewport {
    float vw = [self.tramsformController getScope].W;
    float vh = [self.tramsformController getScope].H;
    float viewportX = [self.tramsformController getScope].scaleX < 1.0 ? -1*(vw - vw * [self.tramsformController getScope].scaleX) / 2  : 0;
    float viewportY = [self.tramsformController getScope].scaleY < 1.0 ? -1*(vh - vh * [self.tramsformController getScope].scaleY) / 2  : 0;
    
    return CGRectMake(_viewprotRange.origin.x + viewportX, _viewprotRange.origin.y + viewportY, _viewprotRange.size.width, _viewprotRange.size.height);
}

- (void)render {
    CGRect viewport = [self calculateViewport];
    glViewport(viewport.origin.x, viewport.origin.y, viewport.size.width, viewport.size.height);
    
    [self setModelviewProj:[self.tramsformController getModelViewProjectionMatrix]];
    
    if ([self prepareRender]) {
        [self.mapProjection updateVertex];
#ifdef DEBUG
        if (!validateProgram(_program))
        {
            NSLog(@"Failed to validate program");
            return;
        }
#endif
        [self.mapProjection draw];
    }
}

- (void)didUpdateOutputWH:(int)w :(int)h {
    if(self.tramsformController){
        const double width   = w;
        const double height  = h;
        const double dH      = (double)[self.tramsformController getScope].H / height;
        const double dW      = (double)[self.tramsformController getScope].W / width;
        double dd;
        switch (_contentMode) {
            case IRGLRenderContentModeScaleAspectFit:
                dd = MIN(dH, dW);
                break;
            case IRGLRenderContentModeScaleAspectFill:
                dd = MAX(dH, dW);
                break;
            case IRGLRenderContentModeScaleToFill:
                dd = 0;
                break;
        }
        
        if(dd > 0){
            const double sy       = (height * dd / (double)[self.tramsformController getScope].H);
            const double sx       = (width  * dd / (double)[self.tramsformController getScope].W );
            
            //            if(_tramsformController.getDefaultTransformScale.x != sx ||
            //               _tramsformController.getDefaultTransformScale.y != sy){
            //                [_tramsformController setupDefaultTransformScaleX:sx transformScaleY:sy];
            ////                [_tramsformController updateToDefault];
            //            }
            
            [_tramsformController setupDefaultTransformScaleX:sx transformScaleY:sy];
            
            if((dH != 1 ||
                dW != 1) && self.shouldUpdateToDefaultWhenOutputSizeChanged){
                [_tramsformController updateToDefault];
            }
        }
    }
}

- (void)didPanBydx:(float)dx dy:(float)dy {
    [self.tramsformController scrollByDx:dx dy:dy];
}

- (void)didPinchByfx:(float)fx fy:(float)fy sx:(float)sx sy:(float)sy {
    
    
    [self.tramsformController updateByFx:[self.tramsformController getScope].W - (fx * [[UIScreen mainScreen] scale]) fy:fy * [[UIScreen mainScreen] scale] sx:sx sy:sy];
    
}

- (void)didPinchByfx:(float)fx fy:(float)fy dsx:(float)dsx dsy:(float)dsy {
    float scaleX = [self.tramsformController getScope].scaleX * dsx;
    float scaleY = [self.tramsformController getScope].scaleY * dsy;
    
    [self didPinchByfx:fx fy:fy sx:scaleX sy:scaleY];
}

- (void)didPanByDegreeX:(float)degreex degreey:(float)degreey {
    [self.tramsformController scrollByDegreeX:degreex degreey:degreey];
}

- (void)didRotate:(float)rotateRadians {
    [self.tramsformController rotate: rotateRadians * 180 / M_PI];
}

static BOOL validateProgram(GLuint prog)
{
    GLint status;
    
    glValidateProgram(prog);
    
    //#ifdef DEBUG
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    //#endif
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == GL_FALSE) {
        NSLog(@"Failed to validate program %d", prog);
        return NO;
    }
    
    return YES;
}

static GLuint compileShader(GLenum type, NSString *shaderString)
{
    GLint status;
    const GLchar *sources = (GLchar *)shaderString.UTF8String;
    
    GLuint shader = glCreateShader(type);
    if (shader == 0 || shader == GL_INVALID_ENUM) {
        NSLog(@"Failed to create shader %d", type);
        return 0;
    }
    
    glShaderSource(shader, 1, &sources, NULL);
    glCompileShader(shader);
    
#ifdef DEBUG
    GLint logLength;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_FALSE) {
        glDeleteShader(shader);
        NSLog(@"Failed to compile shader:\n");
        return 0;
    }
    
    return shader;
}

-(void)didDoubleTap{
    if(self.doResetToDefaultScaleBlock && self.doResetToDefaultScaleBlock(self))
        return;
    
    [self.tramsformController updateToDefault];
}

-(void)willScrollByDx:(float)dx dy:(float)dy withTramsformController:(IRGLTransformController *)tramsformController{
    
}

-(BOOL)doScrollHorizontalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController{
    return YES;
}

-(BOOL)doScrollVerticalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController{
    return YES;
}

-(void)didScrollWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController{
    
    BOOL didScrollToBoundsHorizontal = NO;
    BOOL didScrollToBoundsVertical = NO;
    IRGLTransformControllerScrollToBounds scrollToBounds = IRGLTransformControllerScrollToBoundsNone;
    
    if(status & IRGLTransformControllerScrollToMaxX || status & IRGLTransformControllerScrollToMinX){
        didScrollToBoundsHorizontal = YES;
        scrollToBounds = IRGLTransformControllerScrollToHorizontalBounds;
    }
    if(status & IRGLTransformControllerScrollToMaxY || status & IRGLTransformControllerScrollToMinY){
        didScrollToBoundsVertical = YES;
        scrollToBounds = IRGLTransformControllerScrollToVerticalBounds;
    }
    
    if(didScrollToBoundsHorizontal && didScrollToBoundsVertical)
        scrollToBounds = IRGLTransformControllerScrollToHorizontalandVerticalBounds;
    
    if(self.delegate && scrollToBounds!=IRGLTransformControllerScrollToBoundsNone)
        [self.delegate didScrollToBounds:scrollToBounds withProgram:self];
}

@end
