//
//  IRGLRenderMode.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRePTZShiftController.h"
//#import "IRGLProgram2D.h"
//#import "IRMediaParameter.h"
#import "IRGLRenderContentMode.h"
#import "IRGLRender.h"

@class IRGLProgram2DFactory;
@class IRMediaParameter;
@class IRGLProgram2D;
@class IRGLScopeRange;
@class IRGLScaleRange;
@class IRGLRenderBase;

NS_ASSUME_NONNULL_BEGIN

@protocol IRGLRenderModeDelegate

@optional
- (void)programDidCreate:(IRGLProgram2D *)program;
@end

@interface IRGLRenderMode : NSObject {
@protected
    IRGLProgram2D* _program;
    IRGLProgram2DFactory* programFactory;
}

@property (weak) id<IRGLRenderModeDelegate> delegate;
@property IRePTZShiftController* shiftController;
@property (nonatomic) float wideDegreeX;
@property (nonatomic) float wideDegreeY;
@property (nonatomic) float defaultScale;
@property (nonatomic) float aspect;
@property (nonatomic) IRGLScaleRange *scaleRange;
@property (nonatomic) IRGLScopeRange *scopeRange;
@property (nonatomic) IRGLRenderContentMode contentMode;
@property (nonatomic) IRMediaParameter* parameter;
@property (nonatomic) NSString* name;
@property (readonly) IRGLProgram2D* program;
@property (nonatomic) id<IRGLRender> renderer;

- (void)setting;
- (void)update;

@end

NS_ASSUME_NONNULL_END
