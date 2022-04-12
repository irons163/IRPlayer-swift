//
//  IRFFMetadata.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFMetadata.h"

@implementation IRFFMetadata

+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary
{
    return [[self alloc] initWithAVDictionary:avDictionary];
}

- (instancetype)initWithAVDictionary:(AVDictionary *)avDictionary
{
    if (self = [super init]) {
        NSDictionary * dic = IRFFFoundationBrigeOfAVDictionary(avDictionary);
        self.language = [dic objectForKey:@"language"];
        self.BPS = [[dic objectForKey:@"BPS"] longLongValue];
        self.duration = [dic objectForKey:@"DURATION"];
        self.number_of_bytes = [[dic objectForKey:@"NUMBER_OF_BYTES"] longLongValue];
        self.number_of_frames = [[dic objectForKey:@"NUMBER_OF_FRAMES"] longLongValue];
    }
    return self;
}

@end
