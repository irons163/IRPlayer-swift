//
//  IRGLProgramMulti.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProgram2D.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProgramMulti : IRGLProgram2D {
@protected
    NSMutableArray *_programs;
}

-(instancetype)initWithPrograms:(NSArray*)programs withViewprotRange:(CGRect)viewprotRange;

@end

NS_ASSUME_NONNULL_END
