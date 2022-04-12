//
//  IRFisheyeParameter.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFisheyeParameter.h"

@implementation IRFisheyeParameter

- (instancetype)initWithWidth:(float)width height:(float)height up:(bool)up rx:(float)rx ry:(float)ry cx:(float)cx cy:(float)cy latmax:(float)latmax {
    if(self = [super initWithWidth:width height:height]){
        _up = up;
        _rx = rx;
        _ry = ry;
        _cx = cx;
        _cy = cy;
        _latmax = latmax;
        NSLog(@"init FisheyeParameter up:%s rx:%f ry:%f cx:%f cy:%f latmax:%f",up?"true":"false",rx,ry,cx,cy,latmax);
    }
    
    return self;
}

@end
