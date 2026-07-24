//
//  IRFFMpegErrorUtil.m
//  IRPlayer-swift
//
//  Created by irons on 2024/7/14.
//

#include "IRFFMpegErrorUtil.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#import "libavutil/avutil.h"
#pragma clang diagnostic pop

int IR_AVERROR_EOF = AVERROR_EOF;
long long IR_AV_NOPTS_VALUE = AV_NOPTS_VALUE;
