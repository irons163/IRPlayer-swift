//
//  IRPlayer+DisplayView.h
//  IRPlayer
//
//  Created by Phil on 2019/7/9.
//  Copyright © 2019 Phil. All rights reserved.
//

//#import "IRPlayerImp.h"
@class IRPlayerImp;
#import "IRGLView.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRPlayerImp (DisplayView)

@property (nonatomic, strong, readonly) IRGLView * displayView;
@end

NS_ASSUME_NONNULL_END
