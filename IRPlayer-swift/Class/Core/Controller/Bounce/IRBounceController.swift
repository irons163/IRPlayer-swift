////
////  IRBounceController.swift
////  IRPlayer-swift
////
////  Created by Phil Chang on 2022/4/12.
////  Copyright © 2022 Phil. All rights reserved.
////
//
//import Foundation
//
//enum IRScrollDirectionType {
//    case none //default
//    case eleft
//    case right
//    case up
//    case down
//}
//
//class IRBounceController {
//
//    private var targetView: IRGLView
//    
//}
//
///**
// Add Bounce to the view.
// */
//- (void)addBounceToView:(UIView *)view;
//
//func addBounceToView(view: UIView) {
//
//}
//
///**
// Remove Bounce form the view.
// */
//- (void)removeBounceToView:(UIView *)view;
//
//- (void)removeAndAddAnimateWithScrollValue:(CGFloat)scrollValue byScrollDirection:(IRScrollDirectionType)type;
//
//private func removeBounceToView() {
//
//}
//
//private finv :(CGFloat)scrollValue byScrollDirection:(IRScrollDirectionType)type {
//    NSString* key = nil;
//    CAShapeLayer* lineLayer = nil;
//    UIBezierPath* startPath = nil;
//    UIBezierPath* endPath = nil;
//
//    startPath = [self getLinePathWithAmount:scrollValue byScrollDirection:type];
//    endPath = [self getLinePathWithAmount:0.0 byScrollDirection:type];
//
//    switch (type) {
//        case Left:{
//            key = @"bounce_right";
//            lineLayer = horizontalLineLayer;
//            break;
//        }
//        case Right:{
//            key = @"bounce_left";
//            lineLayer = horizontalLineLayer;
//            break;
//        }
//        case Up:{
//            key = @"bounce_bottom";
//            lineLayer = verticalLineLayer;
//            break;
//        }
//        case Down:{
//            key = @"bounce_top";
//            lineLayer = verticalLineLayer;
//            break;
//        }
//        default:
//            return;
//    }
//
//    [lineLayer removeAnimationForKey:key];
//    lineLayer.path = [startPath CGPath];
//
//    CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
//    morph.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
//    morph.fromValue = (id) lineLayer.path;
//    morph.toValue = (id) [endPath CGPath];
//    morph.duration = 0.2;
//    morph.removedOnCompletion = NO;
//    morph.fillMode = kCAFillModeForwards;
//    //    morph.delegate = self;
//    [lineLayer addAnimation:morph forKey:key];
//}
//
//private func
