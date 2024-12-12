//
//  IRGLProjection.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRMediaParameter.h"

NS_ASSUME_NONNULL_BEGIN

enum {
    ATTRIBUTE_VERTEX,
    ATTRIBUTE_TEXCOORD,
};

@protocol IRGLProjection
- (void) updateWithParameter:(IRMediaParameter *)parameter;
- (void) updateVertex;
- (void) draw;
@end

NS_ASSUME_NONNULL_END
