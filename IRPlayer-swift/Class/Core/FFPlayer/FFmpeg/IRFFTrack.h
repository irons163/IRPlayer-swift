//
//  IRFFTrack.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFMetadata.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRFFTrackType) {
    IRFFTrackTypeVideo,
    IRFFTrackTypeAudio,
    IRFFTrackTypeSubtitle,
};

@interface IRFFTrack : NSObject

@property (nonatomic, assign) int index;
@property (nonatomic, assign) IRFFTrackType type;
@property (nonatomic, strong) IRFFMetadata * metadata;

@end

NS_ASSUME_NONNULL_END
