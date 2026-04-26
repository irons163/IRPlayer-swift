//
//  IRGLProgramVR.h
//  IRPlayer
//
//  Created by Phil on 2019/8/21.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2D.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProgramVR : IRGLProgram2D

@property (nonatomic, assign) GLuint index_id;
@property (nonatomic, assign) GLuint vertex_id;
@property (nonatomic, assign) GLuint texture_id;

@property (nonatomic, assign) int index_count;
@property (nonatomic, assign) int vertex_count;

@end

NS_ASSUME_NONNULL_END
