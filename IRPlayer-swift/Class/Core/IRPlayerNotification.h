//
//  IRPlayerNotification.h
//  IRPlayer
//
//  Created by Phil on 2019/7/9.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import "IRPlayerImp.h"
#import "IRPlayerAction.h"
@class IRPlayerImp;

NS_ASSUME_NONNULL_BEGIN

@interface IRPlayerNotification : NSObject

+ (void)postPlayer:(IRPlayerImp *)player error:(IRError *)error;
+ (void)postPlayer:(IRPlayerImp *)player statePrevious:(IRPlayerState)previous current:(IRPlayerState)current;
+ (void)postPlayer:(IRPlayerImp *)player progressPercent:(NSNumber *)percent current:(NSNumber *)current total:(NSNumber *)total;
+ (void)postPlayer:(IRPlayerImp *)player playablePercent:(NSNumber *)percent current:(NSNumber *)current total:(NSNumber *)total;

@end

NS_ASSUME_NONNULL_END
