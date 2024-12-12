//
//  IRFFMpeg.h
//  IRPlayer
//
//  Created by irons on 2024/12/18.
//

#import <Foundation/Foundation.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavformat/avformat.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRFFMpeg : NSObject

@end

NS_ASSUME_NONNULL_END
