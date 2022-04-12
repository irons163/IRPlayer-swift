//
//  IRYUVTools.h
//  IRPlayer
//
//  Created by Phil on 2019/7/9.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRPLFImage.h"
#import "pixfmt.h"

int IRYUVChannelFilterNeedSize(int linesize, int width, int height, int channel_count);
void IRYUVChannelFilter(UInt8 * src, int linesize, int width, int height, UInt8 * dst, size_t dstsize, int channel_count);
IRPLFImage IRYUVConvertToImage(UInt8 * src_data[], int src_linesize[], int width, int height, enum AVPixelFormat pixelFormat);
