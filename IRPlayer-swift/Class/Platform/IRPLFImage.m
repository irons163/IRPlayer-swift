//
//  IRPLFImage.m
//  IRPlayer
//
//  Created by Phil on 2019/7/9.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRPLFImage.h"

IRPLFImage IRPLFImageWithCGImage(CGImageRef image)
{
    return [UIImage imageWithCGImage:image];
}

IRPLFImage IRPLFImageWithRGBData(UInt8 * rgb_data, int linesize, int width, int height)
{
    CGImageRef imageRef = IRPLFImageCGImageWithRGBData(rgb_data, linesize, width, height);
    if (!imageRef) return nil;
    IRPLFImage image = IRPLFImageWithCGImage(imageRef);
    CGImageRelease(imageRef);
    return image;
}

CGImageRef IRPLFImageCGImageWithRGBData(UInt8 * rgb_data, int linesize, int width, int height)
{
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, rgb_data, linesize * height);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef imageRef = CGImageCreate(width,
                                        height,
                                        8,
                                        24,
                                        linesize,
                                        colorSpace,
                                        kCGBitmapByteOrderDefault,
                                        provider,
                                        NULL,
                                        NO,
                                        kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    CFRelease(data);
    
    return imageRef;
}
