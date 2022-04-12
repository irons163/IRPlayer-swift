//
//  IRFisheyeParameter.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRMediaParameter.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFisheyeParameter : IRMediaParameter
@property (readonly) bool up;
@property (readonly) float rx;
@property (readonly) float ry;
@property (readonly) float cx;
@property (readonly) float cy;
@property (readonly) float latmax;

- (instancetype)initWithWidth:(float)width height:(float)height up:(bool)up rx:(float)rx ry:(float)ry cx:(float)cx cy:(float)cy latmax:(float)latmax;
@end

NS_ASSUME_NONNULL_END
