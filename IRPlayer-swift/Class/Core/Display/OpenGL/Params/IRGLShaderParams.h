//
//  IRGLShaderParams.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMatrix4.h>

NS_ASSUME_NONNULL_BEGIN

@protocol IRGLShaderParamsDelegate <NSObject>

-(void)didUpdateOutputWH:(int)w :(int)h;

@end

@interface IRGLShaderParams : NSObject

@property (weak) id<IRGLShaderParamsDelegate> delegate;

@property (nonatomic) GLint textureWidth;
@property (nonatomic) GLint textureHeight;
@property (nonatomic) GLint outputWidth;
@property (nonatomic) GLint outputHeight;

- (void) updateTextureWidth:(NSUInteger)w height:(NSUInteger)h;
- (void) resolveUniforms: (GLuint) program;
- (void) prepareRender;
@end

NS_ASSUME_NONNULL_END
