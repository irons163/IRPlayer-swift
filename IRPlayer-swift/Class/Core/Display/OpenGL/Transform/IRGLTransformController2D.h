//
//  IRGLTransformController2D.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLTransformController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLTransformController2D : IRGLTransformController {
    float maxX0, maxY0, rW, rH;
}

-(instancetype)initWithViewportWidth:(int)width viewportHeight:(int)height;

@end


NS_ASSUME_NONNULL_END
