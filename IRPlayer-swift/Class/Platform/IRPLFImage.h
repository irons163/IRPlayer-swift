//
//  IRPLFImage.h
//  IRPlayer
//
//  Created by Phil on 2019/7/9.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef UIImage* IRPLFImage;

IRPLFImage IRPLFImageWithCGImage(CGImageRef image);
// RGB data buffer
IRPLFImage IRPLFImageWithRGBData(UInt8 * rgb_data, int linesize, int width, int height);
CGImageRef IRPLFImageCGImageWithRGBData(UInt8 * rgb_data, int linesize, int width, int height);
