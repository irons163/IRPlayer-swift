//
//  IRMediaParameter.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRMediaParameter.h"

@implementation IRMediaParameter

- (instancetype)initWithWidth:(float)width height:(float)height {
    if (self = [super init]) {
        _width = width;
        _height = height;
        _autoUpdate = YES;
    }
    return self;
}

@end
