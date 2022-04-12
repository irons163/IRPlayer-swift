//
//  IRGLFragmentFish2PanoShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFragmentFish2PanoShaderGLSL.h"
#import "IRGLDefine.h"
#import "IRGLMath.h"

#define PIXEL_FORMAT_TOKEN  PIXEL_FORMAT_TOKEN
#define PIXEL_FORMAT_PROCESSING_TOKEN  PIXEL_FORMAT_PROCESSING_TOKEN
#define AA_TEXTURE_FORMAT_TOKEN  AA_TEXTURE_FORMAT_TOKEN
#define AA_TEXTURE_FORMAT_PROCESSING_TOKEN  AA_TEXTURE_FORMAT_PROCESSING_TOKEN
#define AA_TEXTURE_FORMAT_CHECK_EXIST_TOKEN  AA_TEXTURE_FORMAT_CHECK_EXIST_TOKEN

#define RGB_PIXEL_FORMAT(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_TOKEN) withString:@"uniform highp sampler2D s_texture;"]
#define YUV_PIXEL_FORMAT(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_TOKEN) withString:@"uniform highp sampler2D s_texture_y; uniform highp sampler2D s_texture_u; uniform highp sampler2D s_texture_v;"]
#define NV12_PIXEL_FORMAT(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_TOKEN) withString:@"uniform highp sampler2D SamplerY; uniform highp sampler2D SamplerUV;"]

#define AA_TEXTURE_FORMAT(shaderStr, replacedStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(AA_TEXTURE_FORMAT_TOKEN) withString:replacedStr]
#define AA_TEXTURE_FORMAT_PROCESSING(shaderStr, replacedStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(AA_TEXTURE_FORMAT_PROCESSING_TOKEN) withString:replacedStr]
#define AA_TEXTURE_FORMAT_CHECK_EXIST(shaderStr, replacedStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(AA_TEXTURE_FORMAT_CHECK_EXIST_TOKEN) withString:replacedStr]

#define RGB_PIXEL_FORMAT_PROCESSING(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_PROCESSING_TOKEN) withString:@" \
vecTmp = texture2D(SamplerY, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight)));"]
#define YUV_PIXEL_FORMAT_PROCESSING(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_PROCESSING_TOKEN) withString:@" \
vecTmp.x = texture2D(s_texture_y, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - (16.0/255.0); \
vecTmp.y = texture2D(s_texture_u, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - 0.5; \
vecTmp.z = texture2D(s_texture_v, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - 0.5; \
vecTmp = colorConversionMatrix * vecTmp;"]
#define NV12_PIXEL_FORMAT_PROCESSING(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_PROCESSING_TOKEN) withString:@" \
vecTmp.x = (texture2D(SamplerY, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - (16.0/255.0))* lumaThreshold; \
vecTmp.yz = (texture2D(SamplerUV, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).rg - vec2(0.5, 0.5))* chromaThreshold; \
vecTmp = colorConversionMatrix * vecTmp;"]

@implementation IRGLFragmentFish2PanoShaderGLSL

+(NSString*) getShardString:(IRPixelFormat)pixelFormat antialias:(int)antialias{
    NSString *nv12FragmentShaderString = SHADER_STRING
    (
     varying highp vec2 v_texcoord;
     precision highp float;
     precision highp int;
     
     uniform float lumaThreshold;
     uniform float chromaThreshold;
     PIXEL_FORMAT_TOKEN
     uniform highp mat3 colorConversionMatrix;
     
     uniform int fishwidth;
     uniform int fishheight;
     uniform float fishaperture;
     uniform int fishcenterx;
     uniform int fishcentery;
     uniform int fishradiush;
     uniform int fishradiusv;
     uniform int panowidth;
     uniform int panoheight;
     uniform int antialias;
     uniform float vaperture;
     uniform float lat1;
     uniform float lat2;
     uniform float long1;
     uniform float long2;
     uniform int enableTransformX;
     uniform int enableTransformY;
     uniform int enableTransformZ;
     uniform float transformX;
     uniform float transformY;
     uniform float transformZ;
     uniform float offsetX;
     AA_TEXTURE_FORMAT_TOKEN
     
     /*
      Turn a fisheye projection into a panoramic projection
      Use supersmapling antialiasing.
      Right hand coordinate system
      Jun 2016 - Added differential radii, for elliptical views
      Aug 2016 - Added latitude range, otherwise +- vaperture/2
      Oct 2016 - Added arbitrary rotation order
      Oct 2016 - fish2sphere superceeds this, so confine to cylindrical panoramas
      Strip out all but cylindrical code
      Oct 2016 - Fixed long standing bug with the calculation of the height of the pano
      Nov 2016 - Added split screen output
      - general cleanup of code
      Jan 2017 - Added longitude range
      May 2017 - Fixed vertical center bug
      */
     
#define TGA 0
     
#define XTILT 0 // x
#define YROLL 1 // y
#define ZPAN  2 // z
     
     /* 18 bytes long */
     struct TGAHEADER{
         int  idlength;
         int  colourmaptype;
         int  datatypecode;
         int colourmaporigin;
         int colourmaplength;
         int  colourmapdepth;
         int x_origin;
         int y_origin;
         int width;
         int height;
         int  bitsperpixel;
         int  imagedescriptor;
     };
     
     struct VARS{
         int fishwidth;
         int fishheight;      // Derived from input fisheye tga file
         float fishaperture;            // Aperture of the fisheye
         int fishcenterx;
         int fishcentery;   // Center of the fisheye (pixels), measured from lower-left corner
         int fishradiush;
         int fishradiusv;   // Radius of the fisheye (pixels), deal with non circular
         int panowidth;
         int panoheight;      // Width and height of pano view
         int antialias;                 // Antialiasing
         float vaperture;              // Vertical aperture for cylindrical pano
         float lat1;                   // Start latitude, normally -vlatitude/2
         float lat2;                   // Stop latitude, normally vlatitude/2
         float long1;
         float long2;            // Longitude range, default -pi to pi
     };
     
     struct TRANSFORM{
         int axis;
         float value;
     };
     
     struct XYZ{
         float x;
         float y;
         float z;
     };
     
     // Prototypes
     
     vec3 convertFish2pano();
     void Convert(void);
     void SetDefaultValues(void);
     float GetRunTime(void);
     XYZ PRotateX(XYZ, float);
     XYZ PRotateY(XYZ, float);
     XYZ PRotateZ(XYZ, float);
     int FindFishPixel(float latitude, float longitude, inout float u, inout float v);
     int FindFishPixel(int aa, vec2 xy, inout float u, inout float v);
     
     // Variables
     VARS vars;
     TRANSFORM transform[3];
     int ntransform = 0;
     
     int debug = 0;
     
     
     vec3 convertFish2pano()
     {
         int ai;
         int aj;
         float u;
         float v;
         int rsum;
         int gsum;
         int bsum;            // Adds up supersampling contribution
         vars.antialias = antialias;
         vars.fishwidth = fishwidth;
         vars.fishheight = fishheight;
         vars.panowidth = panowidth;
         vars.panoheight = panoheight;
         
         rsum = 0;
         gsum = 0;
         bsum = 0;
         
         if(AA_TEXTURE_FORMAT_CHECK_EXIST_TOKEN){
             // Antialiasing loops
             for (ai=0;ai<vars.antialias;ai++) {
                 for (aj=0;aj<vars.antialias;aj++) {
                     if (FindFishPixel(ai*vars.antialias+aj,v_texcoord,u,v) > 0) {
                         mediump vec3 vecTmp;
                         PIXEL_FORMAT_PROCESSING_TOKEN
                         
                         rsum += int(vecTmp.r*255.0);
                         gsum += int(vecTmp.g*255.0);
                         bsum += int(vecTmp.b*255.0);
                     }
                 }
             }
         }else{
             float i;
             float j;
             int index=0;
             float xx;
             float yy;
             float y0;
             float longitude;
             float latitude;
             
             
             vars.fishaperture = fishaperture;
             vars.fishcenterx = fishcenterx;
             vars.fishcentery = fishcentery;
             vars.fishradiush = fishradiush;
             vars.fishradiusv = fishradiusv;
             
             
             vars.lat1 = lat1;
             vars.lat2 = lat2;
             vars.long1 = long1;
             vars.long2 = long2;
             vars.vaperture = vaperture;
             
             if(enableTransformX > 0){
                 transform[ntransform].axis = XTILT;
                 transform[ntransform].value = DTOR*transformX;
                 ntransform++;
             }
             
             if(enableTransformY > 0){
                 transform[ntransform].axis = YROLL;
                 transform[ntransform].value = DTOR*transformY;
                 ntransform++;
             }
             
             if(enableTransformZ > 0){
                 transform[ntransform].axis = ZPAN;
                 transform[ntransform].value = DTOR*transformZ;
                 ntransform++;
             }
             
             // Convert all angles to radians
             vars.lat1 *= DTOR;
             vars.lat2 *= DTOR;
             vars.long1 *= DTOR;
             vars.long2 *= DTOR;
             vars.fishaperture *= DTOR;
             vars.vaperture *= DTOR;
             
             // Default values of these variables if not set
             if (vars.fishcenterx < 0 || vars.fishcenterx >= vars.fishwidth)
                 vars.fishcenterx = vars.fishwidth / 2;
             if (vars.fishcentery < 0 || vars.fishcentery >= vars.fishheight)
                 vars.fishcentery = vars.fishheight / 2;
             vars.fishcentery = vars.fishheight - vars.fishcentery;
             if (vars.fishradiush < 0)
                 vars.fishradiush = vars.fishwidth / 2;
             if (vars.fishradiusv < 0)
                 vars.fishradiusv = vars.fishradiush;
             
             // Panowidth will be made a factor of 4
             float f = float(vars.panowidth);
             vars.panowidth = int(4.0 * ceil(f / 4.0));
             
             // Set pano height if not specified
             if (RTOD*0.5*vars.vaperture > 80.0) {
                 vars.vaperture = 160.0*DTOR;
             }
             
             if (vars.panoheight < 0) {
                 vars.panoheight = int(float(vars.panowidth) * tan(0.5*vars.vaperture) / (0.5*(vars.long2 - vars.long1)));
             }
             
             // Do the conversion
             y0 = (tan(vars.lat1) + tan(vars.lat2)) / (tan(vars.lat1) - tan(vars.lat2)); // middle latitude
             
             i = float(v_texcoord.x * float(vars.panowidth)) + offsetX;
             j = float(v_texcoord.y * float(vars.panoheight));
             if(i > float(vars.panowidth)){
                 i = i - float(vars.panowidth);
             }else if(i < 0.0){
                 i = i + float(vars.panowidth);
             }
             //    i = int(gl_FragCoord.x);
             //        j = int(gl_FragCoord.y);
             //    j = viewportHeight - int(gl_FragCoord.y);
             
             // Antialiasing loops
             for (ai=0;ai<vars.antialias;ai++) {
                 xx = (float(i) + float(ai)/float(vars.antialias)) / float(vars.panowidth); // 0 ... 1
                 longitude = vars.long1 + xx * (vars.long2 - vars.long1); // 0 .. 2pi
                 
                 for (aj=0;aj<vars.antialias;aj++) {
                     yy = 2.0 * (float(j) + float(aj)/float(vars.antialias)) / float(vars.panoheight) - float(1); // -1 to 1
                     
                     // Longitude and latitude of vector into world
                     if (abs(vars.lat1) >= PID2 || abs(vars.lat2) >= PID2) { // Symmetric case
                         latitude = atan(yy * tan(0.5*vars.vaperture));
                     } else {
                         if (yy > y0)
                             latitude = atan((yy-y0) * tan(vars.lat2) / (1.0-y0));
                         else
                             latitude = atan((yy-y0) * tan(vars.lat1) / (-1.0-y0));
                     }
                     
                     // Add up the pixel contributions
                     if (FindFishPixel(latitude,longitude,u,v) > 0) {
                         mediump vec3 vecTmp;
                         PIXEL_FORMAT_PROCESSING_TOKEN
                         
                         rsum += int(vecTmp.r*255.0);
                         gsum += int(vecTmp.g*255.0);
                         bsum += int(vecTmp.b*255.0);
                     }
                     
                 } // aj
             } // ai
         }
         
         
         // Set the pixel
         vec3 panoimage;
         panoimage.r = float(rsum / (vars.antialias*vars.antialias));
         panoimage.g = float(gsum / (vars.antialias*vars.antialias));
         panoimage.b = float(bsum / (vars.antialias*vars.antialias));
         
         return panoimage;
     }
     
     int FindFishPixel(int aa, highp vec2 xy, inout float u, inout float v){
         xy.x = xy.x + offsetX/float(vars.panowidth);
         if(xy.x > 1.0){
             xy.x = xy.x - 1.0;
         }else if(xy.x < 0.0){
             xy.x = xy.x + 1.0;
         }
         
         highp vec4 rgba;
         AA_TEXTURE_FORMAT_PROCESSING_TOKEN
         else
             return 0;
         //         u = float(int((rgba.r + rgba.g * 256.0) * 255.0));
         //         v = float(int((rgba.b + rgba.a * 256.0) * 255.0));
         u = float(rgba.r);
         v = float(rgba.g);
         if (u < 0.0 || u > float(vars.fishwidth) || v < 0.0 || v > float(vars.fishheight))
             return 0;
         return 1;
     }
     
     /*
      Rotate vectors around each axis
      Clockwise looking into the origin from along the positive axis
      */
     XYZ PRotateX(XYZ p, float theta)
     {
         XYZ q;
         
         q.x = p.x;
         q.y = p.y * cos(theta) + p.z * sin(theta);
         q.z = -p.y * sin(theta) + p.z * cos(theta);
         return(q);
     }
     XYZ PRotateY(XYZ p, float theta)
     {
         XYZ q;
         
         q.x = p.x * cos(theta) - p.z * sin(theta);
         q.y = p.y;
         q.z = p.x * sin(theta) + p.z * cos(theta);
         return(q);
     }
     XYZ PRotateZ(XYZ p, float theta)
     {
         XYZ q;
         
         q.x = p.x * cos(theta) + p.y * sin(theta);
         q.y = -p.x * sin(theta) + p.y * cos(theta);
         q.z = p.z;
         return(q);
     }
     
     /*
      Given a longitude and latitude calculate the (u,v) pixel coordinates in the fisheye
      Return FALSE if the pixel is outside the fisheye image
      */
     int FindFishPixel(float latitude, float longitude, inout float u, inout float v)
     {
         int k;
         XYZ p;
         float theta;
         float phi;
         float r;
         
         // Vector into the world
         p.x = cos(latitude) * cos(longitude);
         p.y = cos(latitude) * sin(longitude);
         p.z = sin(latitude);
         
         // Apply transformation
         for (k=0;k<ntransform;k++) {
             if(transform[k].axis == XTILT) {
                 p = PRotateX(p,transform[k].value);
             }else if(transform[k].axis == YROLL){
                 p = PRotateY(p,transform[k].value);
             }else if(transform[k].axis == ZPAN){
                 p = PRotateZ(p,transform[k].value);
             }
         }
         
         // Convert to fisheye coordinates
         theta = atan(p.y,p.x);
         phi = atan(sqrt(p.x*p.x+p.y*p.y),p.z);
         r = phi / (0.5 * vars.fishaperture);
         
         // Convert to fisheye image coordinates
         u = float(vars.fishcenterx) + float(vars.fishradiush) * r * cos(theta);
         if (u < 0.0 || u >= float(vars.fishwidth))
             return 0;
         v = float(vars.fishcentery) + float(vars.fishradiusv) * r * sin(theta);
         if (v < 0.0 || v >= float(vars.fishheight))
             return 0;
         
         return 1;
     }
     
     void main()
     {
         mediump vec3 yuv;
         mediump vec3 rgb;
         
         rgb = (convertFish2pano() / 255.0);
         
         gl_FragColor = vec4(rgb,1);
     }
     );
    
    switch (pixelFormat) {
        case RGB_IRPixelFormat:
            nv12FragmentShaderString = RGB_PIXEL_FORMAT(nv12FragmentShaderString);
            nv12FragmentShaderString = RGB_PIXEL_FORMAT_PROCESSING(nv12FragmentShaderString);
            break;
        case YUV_IRPixelFormat:
            nv12FragmentShaderString = YUV_PIXEL_FORMAT(nv12FragmentShaderString);
            nv12FragmentShaderString = YUV_PIXEL_FORMAT_PROCESSING(nv12FragmentShaderString);
            break;
        case NV12_IRPixelFormat:
            nv12FragmentShaderString = NV12_PIXEL_FORMAT(nv12FragmentShaderString);
            nv12FragmentShaderString = NV12_PIXEL_FORMAT_PROCESSING(nv12FragmentShaderString);
            break;
    }
    
    NSString* settex = @"uniform int useTexUVs;";
    NSString* gettex = @"";
    int texnum = antialias*antialias;
    for(int i = 0 ; i < texnum; i++){
        settex = [settex stringByAppendingString:[NSString stringWithFormat:@"uniform highp sampler2D texUV%d%@",i,@";"]];
        gettex = [gettex stringByAppendingString:[NSString stringWithFormat:@"%@if(aa==%d)",(i==0?@"":@"else "),i]];
        gettex = [gettex stringByAppendingString:[NSString stringWithFormat:@"rgba = texture2D(texUV%i, xy);",i]];
    }
    
    nv12FragmentShaderString = AA_TEXTURE_FORMAT(nv12FragmentShaderString, settex);
    nv12FragmentShaderString = AA_TEXTURE_FORMAT_PROCESSING(nv12FragmentShaderString, gettex);
    nv12FragmentShaderString = AA_TEXTURE_FORMAT_CHECK_EXIST(nv12FragmentShaderString, @"useTexUVs != 0");
    
    NSLog(@"Sharder String:%@", nv12FragmentShaderString);
    
    int p;
    if(YES)p = 0;else p = 0;
    
    return nv12FragmentShaderString;
}

@end
