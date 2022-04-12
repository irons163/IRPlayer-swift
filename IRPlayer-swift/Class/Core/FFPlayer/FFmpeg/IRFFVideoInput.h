//
//  IRFFVideoInput.h
//  IRPlayer
//
//  Created by Phil on 2019/10/24.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFVideoFrame.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFVideoInput : NSObject

- (void)updateFrame:(IRFFVideoFrame *)input;

@end

NS_ASSUME_NONNULL_END
