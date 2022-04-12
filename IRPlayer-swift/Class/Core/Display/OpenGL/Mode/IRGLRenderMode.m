//
//  IRGLRenderMode.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderMode.h"
#import "IRGLProgram2D.h"
#import "IRGLProgram2DFactory.h"

#define IRGLRenderModeConfigurationKey_setDefaultScale     @"setDefaultScale"
#define IRGLRenderModeConfigurationKey_setWideDegreeX      @"setWideDegreeX"
#define IRGLRenderModeConfigurationKey_setWideDegreeY      @"setWideDegreeY"
#define IRGLRenderModeConfigurationKey_setContentMode      @"setContentMode"
#define IRGLRenderModeConfigurationKey_setScaleRange       @"setScaleRange"
#define IRGLRenderModeConfigurationKey_setScopeRange       @"setScopeRange"
#define IRGLRenderModeConfigurationKey_setRenderer         @"setRenderer"

@implementation IRGLRenderMode {
    NSMutableArray *configurationKeySequence;
}
@synthesize program = _program;

- (instancetype)init {
    if(self = [super init]) {
        [self initProgramFactory];
        _shiftController = [[IRePTZShiftController alloc] init];
        _name = @"";
        _defaultScale = 1.0;
        configurationKeySequence = [NSMutableArray array];
    }
    return self;
}

- (void)initProgramFactory {
    programFactory = [[IRGLProgram2DFactory alloc] init];
}

- (void)setDefaultScale:(float)scale {
    _defaultScale = scale;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setDefaultScale];
}

- (void)setWideDegreeX:(float)wideDegreeX {
    _wideDegreeX = wideDegreeX;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setWideDegreeX];
}

- (void)setWideDegreeY:(float)wideDegreeY {
    _wideDegreeY = wideDegreeY;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setWideDegreeY];
}

- (void)setContentMode:(IRGLRenderContentMode)contentMode {
    _contentMode = contentMode;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setContentMode];
}

- (void)setScaleRange:(IRGLScaleRange *)scaleRange {
    _scaleRange = scaleRange;
    //    program.tramsformController.scaleRange = _scaleRange;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setScaleRange];
}

- (void)setScopeRange:(IRGLScopeRange *)scopeRange {
    _scopeRange = scopeRange;
    //    program.tramsformController.scopeRange = _scopeRange;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setScopeRange];
}

- (void)setRenderer:(id<IRGLRender>)renderer {
    _renderer = renderer;
    //    program.tramsformController.scopeRange = _scopeRange;
    [configurationKeySequence addObject:IRGLRenderModeConfigurationKey_setRenderer];
}

- (void)settingConfig:(NSString *)key {
    [self settingDefaultScale:key];
    [self settingWideDegreeX:key];
    [self settingWideDegreeY:key];
    [self settingContentMode:key];
    [self settingScaleRange:key];
    [self settingScopeRange:key];
    [self settingRenderer:key];
}

- (void)settingDefaultScale:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setDefaultScale])
        return;
    
    [_program setDefaultScale:self.defaultScale];
}


- (void)settingWideDegreeX:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setWideDegreeX])
        return;
    
//    _shiftController.wideDegreeX = self.wideDegreeX;
//    [_program setWideDegreeX:self.wideDegreeX];
}

- (void)settingWideDegreeY:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setWideDegreeY])
        return;
    
//    _shiftController.wideDegreeY = self.wideDegreeY;
//    [_program setWideDegreeY:self.wideDegreeY];
}

- (void)settingContentMode:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setContentMode])
        return;
    
    [_program setContentMode:self.contentMode];
}

- (void)settingScaleRange:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setScaleRange])
        return;
    
    [_program.tramsformController setScaleRange:self.scaleRange];
}

- (void)settingScopeRange:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setScopeRange])
        return;
    
    [_program.tramsformController setScopeRange:self.scopeRange];
}

- (void)settingRenderer:(NSString *)key {
    if(![key isEqualToString:IRGLRenderModeConfigurationKey_setRenderer])
        return;
    
    [_program setRenderer:self.renderer];
}

- (void)setting {
    if(_program){
        for(NSString* key in configurationKeySequence){
            [self settingConfig:key];
        }
    }
}

- (void)update {
    
    
}

@end

