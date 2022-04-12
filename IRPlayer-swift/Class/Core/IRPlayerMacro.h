//
//  IRPlayerMacro.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#ifndef IRPlayerMacro_h
#define IRPlayerMacro_h

#import "IRScope.h"
// log level
#ifdef DEBUG
#define IRPlayerLog(...) NSLog(__VA_ARGS__)
#else
#define IRPlayerLog(...)
#endif

#endif /* IRPlayerMacro_h */
