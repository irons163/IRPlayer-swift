//
//  IRBounceController.h
//  IRPlayer
//
//  Created by Phil on 2019/8/19.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IRScrollDirectionType){
    None, //default
    Left,
    Right,
    Up,
    Down
};

@interface IRBounceController : NSObject

/**
 Add Bounce to the view.
 */
- (void)addBounceToView:(UIView *)view;

/**
 Remove Bounce form the view.
 */
- (void)removeBounceToView:(UIView *)view;

- (void)removeAndAddAnimateWithScrollValue:(CGFloat)scrollValue byScrollDirection:(IRScrollDirectionType)type;

@end

NS_ASSUME_NONNULL_END
