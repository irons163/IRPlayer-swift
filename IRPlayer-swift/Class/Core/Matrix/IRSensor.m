//
//  IRSensor.m
//  IRPlayer
//
//  Created by Phil on 2019/8/14.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRSensor.h"
#import <CoreMotion/CoreMotion.h>
#import "IRGLView.h"

@interface IRSensor () {
    CMAttitude *referenceAttitude;
}

@property (nonatomic, strong) CMMotionManager * manager;
@property (nonatomic, assign) UIInterfaceOrientation orientation;

@end

@implementation IRSensor

- (instancetype)init {
    if (self = [super init]) {
        self.manager = [[CMMotionManager alloc] init];
        [self updateDeviceOrientation:[UIApplication sharedApplication].statusBarOrientation];
    }
    return self;
}

- (void)updateDeviceOrientation:(UIInterfaceOrientation)orientation {
    _orientation = orientation;
}

#pragma mark - Wide Functions
- (BOOL)resetUnit {
    [self stopMotionDetection];
    referenceAttitude = nil;
    
    __block CGFloat lastOffsetXByDeviceMotion, lastOffsetYByDeviceMotion;
    
    NSOperationQueue *motionQueue = [[NSOperationQueue alloc] init];
    [self.manager startDeviceMotionUpdatesToQueue:motionQueue withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
     {
//         dispatch_sync(dispatch_get_main_queue(), ^{
//             if(self->_orientation != [UIApplication sharedApplication].statusBarOrientation) {
//                 [self updateDeviceOrientation:[UIApplication sharedApplication].statusBarOrientation];
//                 [self resetUnit];
//                 return;
//             }
//         });
         
         BOOL doScroll = YES;
         if (self->referenceAttitude == nil){
             NSLog(@"referenceAttitude nil");
             self->referenceAttitude = [motion.attitude copy];
             lastOffsetXByDeviceMotion = 0;
             lastOffsetYByDeviceMotion = 0;
             doScroll = NO;
         }
         
         float pitch = motion.attitude.pitch * 180.f / M_PI;
         float roll = motion.attitude.roll * 180.f / M_PI;
         
         CMAttitude *currentAttitude = motion.attitude;
         if(!self->referenceAttitude)
             return;
         [currentAttitude multiplyByInverseOfAttitude:self->referenceAttitude];
         CMQuaternion inQuat = currentAttitude.quaternion;
         
         float inversePitch = atan2(2*(inQuat.x*inQuat.w + inQuat.y*inQuat.z), 1 - 2*inQuat.x*inQuat.x - 2*inQuat.z*inQuat.z);
         float inverseRoll = atan2(2*(inQuat.y*inQuat.w - inQuat.x*inQuat.z), 1 - 2*inQuat.y*inQuat.y - 2*inQuat.z*inQuat.z);
         
         float degreeX = 0;
         float degreeY = 0;
         
         switch (self.orientation) {
             case UIInterfaceOrientationPortrait:
             {
                 if (pitch < 15) {
                     self->referenceAttitude = nil;
                     return;
                 }
                 
                 degreeX = inverseRoll * 180.0 / M_PI;
                 degreeY = inversePitch * 180.0 / M_PI;
             }
                 break;
             case UIInterfaceOrientationPortraitUpsideDown:
             {
                 if (pitch > -15) {
                     self->referenceAttitude = nil;
                     return;
                 }
                 
                 degreeX = (inverseRoll * 180.0 / M_PI) * -1;
                 degreeY = (inversePitch * 180.0 / M_PI) * -1;
             }
                 break;
             case UIInterfaceOrientationLandscapeLeft:
             {
                 if (roll < 15) {
                     self->referenceAttitude = nil;
                     return;
                 }
                 
                 degreeX = (inversePitch * 180.0 / M_PI) * -1;
                 degreeY = inverseRoll * 180.0 / M_PI ;
             }
                 break;
             case UIInterfaceOrientationLandscapeRight:
             {
                 if (roll > -15) {
                     self->referenceAttitude = nil;
                     return;
                 }
                 
                 degreeX = inversePitch * 180.0 / M_PI;
                 degreeY = (inverseRoll * 180.0 / M_PI) * -1;
             }
                 break;
             default:
             {
                 self->referenceAttitude = nil;
                 return;
             }
                 break;
         }
         
         CGFloat newOffsetXByDeviceMotion = degreeX;
         CGFloat newOffsetYByDeviceMotion = -degreeY;
         CGFloat dx = newOffsetXByDeviceMotion - lastOffsetXByDeviceMotion;
         CGFloat dy = newOffsetYByDeviceMotion - lastOffsetYByDeviceMotion;
         lastOffsetXByDeviceMotion = newOffsetXByDeviceMotion;
         lastOffsetYByDeviceMotion = newOffsetYByDeviceMotion;
         
         if(dx < -180){
             dx = 360 + (dx);
             //             referenceAttitude = nil;
         }else if(dx > 180){
             dx = (dx) - 360;
             //             referenceAttitude = nil;
         }
         
         //NSLog(@"degreeX:%f degreeY:%f", degreeX, degreeY);
         
         dispatch_async(dispatch_get_main_queue(), ^{
             if(self->_orientation != [UIApplication sharedApplication].statusBarOrientation) {
                 [self updateDeviceOrientation:[UIApplication sharedApplication].statusBarOrientation];
                 return;
             }
             if(doScroll){
                 NSLog(@"scrollBy dx:%f dy:%f", dx * [UIScreen mainScreen].scale, dy * [UIScreen mainScreen].scale);
                 if(self.smoothScroll)
                     [self.smoothScroll shiftDegreeX:dx degreeY:dy];
             }
         });
     }];
    
    return YES;
}

- (void)stopMotionDetection {
    [self.manager stopDeviceMotionUpdates];
}


@end
