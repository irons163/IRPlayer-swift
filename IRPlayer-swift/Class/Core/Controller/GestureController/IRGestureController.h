//
//  IRGestureController.h
//  IRPlayer
//
//  Created by Phil on 2019/8/19.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRGestureType) {
    IRGestureTypeUnknown,
    IRGestureTypeSingleTap,
    IRGestureTypeDoubleTap,
    IRGestureTypePan,
    IRGestureTypePinch
};

typedef NS_ENUM(NSUInteger, IRPanDirection) {
    IRPanDirectionUnknown,
    IRPanDirectionV,
    IRPanDirectionH,
};

typedef NS_ENUM(NSUInteger, IRPanLocation) {
    IRPanLocationUnknown,
    IRPanLocationLeft,
    IRPanLocationRight,
};

typedef NS_ENUM(NSUInteger, IRPanMovingDirection) {
    IRPanMovingDirectionUnkown,
    IRPanMovingDirectionTop,
    IRPanMovingDirectionLeft,
    IRPanMovingDirectionBottom,
    IRPanMovingDirectionRight,
};

/// This enumeration lists some of the gesture types that the player has by default.
typedef NS_OPTIONS(NSUInteger, IRDisableGestureTypes) {
    IRDisableGestureTypesNone         = 0,
    IRDisableGestureTypesSingleTap    = 1 << 0,
    IRDisableGestureTypesDoubleTap    = 1 << 1,
    IRDisableGestureTypesPan          = 1 << 2,
    IRDisableGestureTypesPinch        = 1 << 3,
    IRDisableGestureTypesAll          = (IRDisableGestureTypesSingleTap | IRDisableGestureTypesDoubleTap | IRDisableGestureTypesPan | IRDisableGestureTypesPinch)
};

/// This enumeration lists some of the pan gesture moving direction that the player not support.
typedef NS_OPTIONS(NSUInteger, IRDisablePanMovingDirection) {
    IRDisablePanMovingDirectionNone         = 0,       /// Not disable pan moving direction.
    IRDisablePanMovingDirectionVertical     = 1 << 0,  /// Disable pan moving vertical direction.
    IRDisablePanMovingDirectionHorizontal   = 1 << 1,  /// Disable pan moving horizontal direction.
    IRDisablePanMovingDirectionAll          = (IRDisablePanMovingDirectionVertical | IRDisablePanMovingDirectionHorizontal)  /// Disable pan moving all direction.
};

@interface IRGestureController : NSObject<UIGestureRecognizerDelegate>

@property (nonatomic, weak, readonly) UIView *targetView;

/// Gesture condition callback.
@property (nonatomic, copy, nullable) BOOL(^triggerCondition)(IRGestureController *control, IRGestureType type, UIGestureRecognizer *gesture, UITouch *touch);

/// Single tap gesture callback.
@property (nonatomic, copy, nullable) void(^singleTapped)(IRGestureController *control);

/// Double tap gesture callback.
@property (nonatomic, copy, nullable) void(^doubleTapped)(IRGestureController *control);

/// Begin pan gesture callback.
@property (nonatomic, copy, nullable) void(^beganPan)(IRGestureController *control, IRPanDirection direction, IRPanLocation location);

/// Pan gesture changing callback.
@property (nonatomic, copy, nullable) void(^changedPan)(IRGestureController *control, IRPanDirection direction, IRPanLocation location, CGPoint velocity);

/// End the Pan gesture callback.
@property (nonatomic, copy, nullable) void(^endedPan)(IRGestureController *control, IRPanDirection direction, IRPanLocation location);

/// Pinch gesture callback.
@property (nonatomic, copy, nullable) void(^pinched)(IRGestureController *control, float scale);

/// The single tap gesture.
@property (nonatomic, strong, readonly) UITapGestureRecognizer *singleTapGR;

/// The double tap gesture.
@property (nonatomic, strong, readonly) UITapGestureRecognizer *doubleTapGR;

/// The pan tap gesture.
@property (nonatomic, strong, readonly) UIPanGestureRecognizer *panGR;

/// The pinch tap gesture.
@property (nonatomic, strong, readonly) UIPinchGestureRecognizer *pinchGR;

/// The pan gesture direction.
@property (nonatomic, readonly) IRPanDirection panDirection;

@property (nonatomic, readonly) IRPanLocation panLocation;

@property (nonatomic, readonly) IRPanMovingDirection panMovingDirection;

/// The gesture types that the player not support.
@property (nonatomic) IRDisableGestureTypes disableTypes;

/// The pan gesture moving direction that the player not support.
@property (nonatomic) IRDisablePanMovingDirection disablePanMovingDirection;

/**
 Add gestures to the view.
 */
- (void)addGestureToView:(UIView *)view;

/**
 Remove gestures form the view.
 */
- (void)removeGestureToView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
