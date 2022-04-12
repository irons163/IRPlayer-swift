//
//  IRGLTransformControllerDistortion.m
//  IRPlayer
//
//  Created by Phil on 2019/8/22.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLTransformControllerDistortion.h"

@implementation IRGLTransformControllerDistortion {
    GLKMatrix4 leftViewMatrix;
    GLKMatrix4 rightViewMatrix;
}
//@synthesize viewMatrix;
//@dynamic viewMatrix;
//@synthesize viewMatrix = _viewMatrix;

-(GLKMatrix4)getModelViewProjectionMatrix {
    CGFloat distance = 0.012;

//    GLKMatrix4 leftViewMatrix = GLKMatrix4MakeLookAt(-distance, 0, 0.0, 0, 0, -1000, 0, 1, 0);
//    GLKMatrix4 rightViewMatrix = GLKMatrix4MakeLookAt(distance, 0, 0.0, 0, 0, -1000, 0, 1, 0);

//    GLKMatrix4 leftMvpMatrix = GLKMatrix4Multiply(leftViewMatrix, leftViewMatrix);
//    GLKMatrix4 rightMvpMatrix = GLKMatrix4Multiply(rightViewMatrix, rightViewMatrix);

//    leftMvpMatrix = GLKMatrix4Multiply(leftMvpMatrix, modelMatrix);
//    rightMvpMatrix = GLKMatrix4Multiply(rightMvpMatrix, modelMatrix);

    
    GLKMatrix4 mv = GLKMatrix4Multiply(leftViewMatrix, modelMatrix); // VM = V x M;
    GLKMatrix4 mvp = GLKMatrix4Multiply(projectMatrix, mv); // PVM = P x VM;
    return mvp;
//    GLKMatrix4 v = GLKMatrix4Translate(self.viewMatrix, -distance, 0, 0);
//    GLKMatrix4 mv = GLKMatrix4Multiply(v, modelMatrix); // VM = V x M;
//    GLKMatrix4 mvp = GLKMatrix4Multiply(projectMatrix, mv); // PVM = P x VM;
//    return mvp;
}

-(GLKMatrix4)getModelViewProjectionMatrix2 {
    CGFloat distance = 0.012;
//
//    GLKMatrix4 leftViewMatrix = GLKMatrix4MakeLookAt(-distance, 0, 0.0, 0, 0, -1000, 0, 1, 0);
//    GLKMatrix4 rightViewMatrix = GLKMatrix4MakeLookAt(distance, 0, 0.0, 0, 0, -1000, 0, 1, 0);
//
//    GLKMatrix4 mv = GLKMatrix4Multiply(rightViewMatrix, modelMatrix); // VM = V x M;
//    GLKMatrix4 mvp = GLKMatrix4Multiply(projectMatrix, mv); // PVM = P x VM;
//    return mvp;

//    GLKMatrix4 v = GLKMatrix4Translate(self.viewMatrix, distance, 0, 0);
//    GLKMatrix4 mv = GLKMatrix4Multiply(v, modelMatrix); // VM = V x M;
//    GLKMatrix4 mvp = GLKMatrix4Multiply(projectMatrix, mv); // PVM = P x VM;
//    return mvp;
    
    GLKMatrix4 mv = GLKMatrix4Multiply(rightViewMatrix, modelMatrix); // VM = V x M;
    GLKMatrix4 mvp = GLKMatrix4Multiply(projectMatrix, mv); // PVM = P x VM;
    return mvp;
}

- (void)updateVertices
{
    CGFloat distance = 0.012;
//    CGFloat distance = fov * 3.6;
//
//    IRGLScope3D* s = [self getScope];
//    s.lng = s.lng - distance;
    [super updateVertices];
//    leftViewMatrix = self.viewMatrix;
////    leftViewMatrix = GLKMatrix4MakeLookAt(camera[0], camera[1] , camera[2] , 0, 0, -1000, 0, 1, 0);
//
//    s = [self getScope];
//    s.lng = s.lng + distance;
//    [super updateVertices];
//    rightViewMatrix = self.viewMatrix;
////    rightViewMatrix = GLKMatrix4MakeLookAt(camera[0], camera[1] , camera[2] , 0, 0, -1000, 0, 1, 0);
    
    leftViewMatrix = GLKMatrix4MakeLookAt(camera[0] - distance, camera[1] , camera[2] , 0, 0, 0, 0, 1, 0);
    rightViewMatrix = GLKMatrix4MakeLookAt(camera[0] + distance, camera[1] , camera[2] , 0, 0, 0, 0, 1, 0);
}

@end
