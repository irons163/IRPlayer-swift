//
//  IRGLScope2D.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLScope2D.h"

@implementation IRGLScope2D

-(instancetype)init{
    if(self = [super init]){
        self.scaleX = self.scaleY = 1.0f;
        self.W = self.H = 0;
        self.panDegree = self.offsetX = self.offsetY = 0.0f;
    }
    return self;
}

-(instancetype)init:(IRGLScope2D*)old1{
    if(self = [super init]){
        self.W = old1.W;
        self.H = old1.H;
        self.scaleX = old1.scaleX;
        self.scaleY = old1.scaleY;
        self.offsetX = old1.offsetX;
        self.offsetY = old1.offsetY;
        self.panDegree = old1.panDegree;
    }
    return self;
}

-(instancetype)initBysx:(float)sx sy:(float) sy offx:(float)offx offy:(float)offy degree:(float)degree w:(int)w h:(int)h{
    if(self = [super init]){
        if(w > 0)
            self.W = w;
        if(h > 0)
            self.H = h;
        self.scaleX = sx;
        self.scaleY = sy;
        self.offsetX = offx;
        self.offsetY = offy;
        self.panDegree = degree;
    }
    return self;
}

@end
