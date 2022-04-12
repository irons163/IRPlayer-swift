//
//  IRFFMetadata.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFTools.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFMetadata : NSObject

+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary;

@property (nonatomic, copy) NSString * language;
@property (nonatomic, assign) long long BPS;
@property (nonatomic, copy) NSString * duration;
@property (nonatomic, assign) long long number_of_bytes;
@property (nonatomic, assign) long long number_of_frames;

@end

NS_ASSUME_NONNULL_END
