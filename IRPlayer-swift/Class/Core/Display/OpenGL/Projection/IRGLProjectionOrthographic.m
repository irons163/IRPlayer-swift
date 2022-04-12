//
//  IRGLProjectionOrthographic.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProjectionOrthographic.h"

@implementation IRGLProjectionOrthographic{
    GLfloat         _vertices[8];
}

-(instancetype)initWithTextureWidth:(float)w hidth:(float)h{
    if(self = [super init]){
        _vertices[0] = -1.0f;  // x0
        _vertices[1] = -1.0f;  // y0
        _vertices[2] =  1.0f;  // ..
        _vertices[3] = -1.0f;
        _vertices[4] = -1.0f;
        _vertices[5] =  1.0f;
        _vertices[6] =  1.0f;  // x3
        _vertices[7] =  1.0f;  // y3
    }
    return self;
}

-(void) updateVertex{
    static const GLfloat texCoords[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };
    
    glVertexAttribPointer(ATTRIBUTE_VERTEX, 2, GL_FLOAT, 0, 0, _vertices);
    glEnableVertexAttribArray(ATTRIBUTE_VERTEX);
    glVertexAttribPointer(ATTRIBUTE_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
    glEnableVertexAttribArray(ATTRIBUTE_TEXCOORD);
}

-(void)draw{
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

@end
