//
//  IRGLProjectionDistortion.h
//  IRPlayer
//
//  Created by Phil on 2019/8/22.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProjectionVR.h"
#import <OpenGLES/ES2/gl.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRDistortionModelType) {
    IRDistortionModelTypeLeft,
    IRDistortionModelTypeRight,
};

@interface IRGLProjectionDistortion : NSObject<IRGLProjection>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithModelType:(IRDistortionModelType)modelType;

@property (nonatomic, assign, readonly) IRDistortionModelType modelType;

@property (nonatomic, assign) GLint index_buffer_id;
@property (nonatomic, assign) GLint vertex_buffer_id;

@property (nonatomic, assign) int index_count;

@end

NS_ASSUME_NONNULL_END
