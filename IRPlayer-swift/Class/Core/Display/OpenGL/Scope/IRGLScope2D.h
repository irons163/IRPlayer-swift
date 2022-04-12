//
//  IRGLScope2D.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRGLScope2D : NSObject

@property float scaleX;
@property float scaleY;
@property int W;
@property int H;
@property float offsetX;
@property float offsetY;
@property float panDegree;

-(instancetype)init:(IRGLScope2D*)old1;
-(instancetype)initBysx:(float)sx sy:(float) sy offx:(float)offx offy:(float)offy degree:(float)degree w:(int)w h:(int)h;
@end

NS_ASSUME_NONNULL_END
