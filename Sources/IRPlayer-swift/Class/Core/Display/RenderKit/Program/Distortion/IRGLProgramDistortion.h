//
//  IRGLProgramDistortion.h
//  IRPlayer
//
//  Created by Phil on 2019/8/22.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2D.h"
#import "IRGLTransformControllerDistortion.h"

NS_ASSUME_NONNULL_BEGIN


@interface IRGLProgramDistortion : IRGLProgram2D

@property (nonatomic) IRGLTransformControllerDistortion* tramsformController;

@property (nonatomic, assign) int index_count;
@property (nonatomic, assign) GLint index_buffer_id;
@property (nonatomic, assign) GLint vertex_buffer_id;

@end

NS_ASSUME_NONNULL_END
