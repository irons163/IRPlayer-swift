//
//  IRGLFragmentFish2PerspShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFragmentFish2PerspShaderGLSL.h"
#import "IRGLDefine.h"
#import "IRGLMath.h"

#define PIXEL_FORMAT_TOKEN  PIXEL_FORMAT_TOKEN
#define PIXEL_FORMAT_PROCESSING_TOKEN  PIXEL_FORMAT_PROCESSING_TOKEN

#define RGB_PIXEL_FORMAT(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_TOKEN) withString:@"uniform highp sampler2D SamplerY; uniform highp sampler2D SamplerUV;"]
#define YUV_PIXEL_FORMAT(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_TOKEN) withString:@"uniform highp sampler2D s_texture_y; uniform highp sampler2D s_texture_u; uniform highp sampler2D s_texture_v;"]
#define NV12_PIXEL_FORMAT(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_TOKEN) withString:@"uniform highp sampler2D SamplerY; uniform highp sampler2D SamplerUV;"]

#define RGB_PIXEL_FORMAT_PROCESSING(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_PROCESSING_TOKEN) withString:@" \
vecTmp.x = (texture2D(SamplerY, vec2(float(u)/float(fishwidth), float(v)/float(fishheight))).r - (16.0/255.0))* lumaThreshold; \
vecTmp.yz = (texture2D(SamplerUV, vec2(float(u)/float(fishwidth), float(v)/float(fishheight))).rg - vec2(0.5, 0.5))* chromaThreshold; \
vecTmp = colorConversionMatrix * vecTmp;"]
#define YUV_PIXEL_FORMAT_PROCESSING(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_PROCESSING_TOKEN) withString:@" \
vecTmp.x = texture2D(s_texture_y, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - (16.0/255.0); \
vecTmp.y = texture2D(s_texture_u, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - 0.5; \
vecTmp.z = texture2D(s_texture_v, vec2(float(u)/float(vars.fishwidth), float(v)/float(vars.fishheight))).r - 0.5; \
vecTmp = colorConversionMatrix * vecTmp;"]
#define NV12_PIXEL_FORMAT_PROCESSING(shaderStr)  [shaderStr stringByReplacingOccurrencesOfString:@STRINGIZE(PIXEL_FORMAT_PROCESSING_TOKEN) withString:@" \
vecTmp.x = (texture2D(SamplerY, vec2(float(u)/float(fishwidth), float(v)/float(fishheight))).r - (16.0/255.0))* lumaThreshold; \
vecTmp.yz = (texture2D(SamplerUV, vec2(float(u)/float(fishwidth), float(v)/float(fishheight))).rg - vec2(0.5, 0.5))* chromaThreshold; \
vecTmp = colorConversionMatrix * vecTmp;"]

@implementation IRGLFragmentFish2PerspShaderGLSL

+(NSString*) getShardString:(IRPixelFormat)pixelFormat{
    NSString *fish2perspFragmentShaderString = SHADER_STRING
    (
     varying highp vec2 v_texcoord;
     precision highp float;
     precision highp int;
     
     uniform float lumaThreshold;
     uniform float chromaThreshold;
     PIXEL_FORMAT_TOKEN
     uniform mat3 colorConversionMatrix;
     uniform int fishwidth;
     uniform int fishheight;
     uniform int fishcenterx;
     uniform int fishcentery;
     uniform int fishradiush;
     uniform int fishradiusv;
     uniform int perspectivewidth;
     uniform int perspectiveheight;
     uniform float fishfov;
     uniform float perspfov;
     uniform int enableTransformX;
     uniform int enableTransformY;
     uniform int enableTransformZ;
     uniform float transformX;
     uniform float transformY;
     uniform float transformZ;
     uniform int antialias;
     
     int perspwidth;
     int perspheight;
     
     
#define XTILT 0 // x
#define YROLL 1 // y
#define ZPAN  2 // z
     
     //#ifndef TRUE
     //#define TRUE  1
     //#define FALSE 0
     //#endif
     
     struct PARAMS {
         float fishfov;    // Field of view
         int fishcenterx;   // Center of fisheye circle
         int fishcentery;
         int fishradius;    // Radius (horizontal) of the fisheye circle
         int fishradiusy;   // Vertical radius, deals with anamorphic lenses
         float fishaspect; // fishradiusy / fishradius
         int antialias;     // Supersampling antialiasing
         float perspfov;   // Horizontal fov of perspective camera
         int imageformat;   // TGA, JPG ....
         int debug;
     };
     
     struct TRANSFORM{
         int axis;
         float value;
         float cvalue,svalue;
     };
     
     struct XYZ{
         float x;
         float y;
         float z;
     };
     
     // Rotation transformations
     TRANSFORM transform[3];
     int ntransform = 0;
     
     PARAMS params;
     
     void CameraRay(float, float, inout XYZ);
     XYZ VectorSum(float,XYZ, float,XYZ, float,XYZ, float,XYZ);
     void Init();
     vec3 convertFish2persp();
     
     vec3 convertFish2persp()
     {
         int i,j,k,ai,aj;
         int w,h,depth,u,v,index;
         float x,y,r,phi,theta,rscale;
         int rsum;
         int gsum;
         int bsum;
         XYZ p = XYZ(0.0,0.0,0.0), q = XYZ(0.0,0.0,0.0);
         
         Init();
         
         perspwidth = perspectivewidth;
         perspheight = perspectiveheight;
         
         if(perspwidth < 8)
             return vec3(0,0,0);
         
         perspwidth /= 2;
         perspwidth *= 2; // Even
         
         if(perspheight < 8)
             return vec3(0,0,0);
         perspheight /= 2;
         perspheight *= 2; // Even
         
         params.fishfov = fishfov;
         params.perspfov = perspfov;
         
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
         
         params.antialias = antialias;
         
         if (params.antialias < 1)
             params.antialias = 1;
         
         params.fishcenterx = fishcenterx;
         params.fishcentery = fishcentery;
         params.fishradius = fishradiush;
         params.fishradiusy = fishradiusv;
         
         
         // Precompute transform sin and cosine
         for (j=0;j<ntransform;j++) {
             transform[j].cvalue = cos(transform[j].value);
             transform[j].svalue = sin(transform[j].value);
         }
         
         // Parameter checking and setting defaults
         if (params.fishcenterx < 0)
             params.fishcenterx = fishwidth / 2;
         if (params.fishcentery < 0)
             params.fishcentery = fishheight / 2;
         else
             params.fishcentery = fishheight - 1 - params.fishcentery; // Bitmaplib assume bottom left
         if (params.fishradius < 0)
             params.fishradius = fishwidth / 2;
         if (params.fishradiusy < 0)
             params.fishradiusy = params.fishradius; // Circular if not anamorphic
         rscale = 2.0 * float(params.fishradius) / params.fishfov;
         params.fishaspect = float(params.fishradiusy) / float(params.fishradius);
         
         // Step through each pixel in the output perspective image
         i = int(v_texcoord.x * float(perspwidth));
         j = int(v_texcoord.y * float(perspheight));
         
         rsum = 0;
         gsum = 0;
         bsum = 0;
         
         // Antialiasing loops, sub-pixel sampling
         for (ai=0;ai<params.antialias;ai++) {
             x = float(i) + float(ai) / float(params.antialias);
             for (aj=0;aj<params.antialias;aj++) {
                 y = float(j) + float(aj) / float(params.antialias);
                 
                 // Calculate vector to each pixel in the perspective image
                 CameraRay(x,y,p);
                 
                 // Apply rotations in order
                 for (k=0;k<ntransform;k++) {
                     if(transform[k].axis == XTILT) {
                         q.x =  p.x;
                         q.y =  p.y * transform[k].cvalue + p.z * transform[k].svalue;
                         q.z = -p.y * transform[k].svalue + p.z * transform[k].cvalue;
                     }
                     else if(transform[k].axis == YROLL) {
                         q.x =  p.x * transform[k].cvalue + p.z * transform[k].svalue;
                         q.y =  p.y;
                         q.z = -p.x * transform[k].svalue + p.z * transform[k].cvalue;
                     }
                     else if(transform[k].axis == ZPAN) {
                         q.x =  p.x * transform[k].cvalue + p.y * transform[k].svalue;
                         q.y = -p.x * transform[k].svalue + p.y * transform[k].cvalue;
                         q.z =  p.z;
                     }
                     p = q;
                 }
                 
                 // Convert to fisheye image coordinates
                 theta = atan(p.z,p.x);
                 phi = atan(sqrt(p.x * p.x + p.z * p.z),p.y);
                 r = rscale * phi;
                 
                 // Convert to fisheye texture coordinates
                 u = int(float(params.fishcenterx) + r * cos(theta));
                 if (u < 0 || u >= fishwidth)
                     continue;
                 v = int(float(params.fishcentery) + r * params.fishaspect * sin(theta));
                 if (v < 0 || v >= fishheight)
                     continue;
                 
                 // Add up antialias contribution
                 vec3 vecTmp;
                 PIXEL_FORMAT_PROCESSING_TOKEN
                 
                 rsum += int(vecTmp.r*255.0);
                 gsum += int(vecTmp.g*255.0);
                 bsum += int(vecTmp.b*255.0);
                 
                 //                             rsum += int(155.0);
                 //                             gsum += int(155.0);
                 //                             bsum += int(155.0);
             }
         }
         
         // Set the pixel
         vec3 panoimage;
         panoimage.r = float(rsum / (params.antialias*params.antialias));
         panoimage.g = float(gsum / (params.antialias*params.antialias));
         panoimage.b = float(bsum / (params.antialias*params.antialias));
         
         //    panoimage.r = 155.0;
         //    panoimage.g = 155.0;
         //    panoimage.b = 155.0;
         
         return panoimage;
     }
     
     /*
      Calculate the vector from the camera for a pixel
      We use a right hand coordinate system
      The camera aperture is the horizontal aperture.
      The projection plane is as follows, one unit away.
      p1 +----------+ p4
      |          |
      |          |
      |          |
      p2 +----------+ p3
      */
     
     XYZ p1 = XYZ(0.0,0.0,0.0), p2 = XYZ(0.0,0.0,0.0), p3 = XYZ(0.0,0.0,0.0), p4 = XYZ(0.0,0.0,0.0); // Corners of the view frustum
     int first = 1;
     XYZ deltah = XYZ(0.0,0.0,0.0), deltav = XYZ(0.0,0.0,0.0);
     float inversew = 0.0,inverseh = 0.0;
     
     void CameraRay(float x,float y, inout XYZ p)
     {
         float h,v;
         float dh,dv;
         XYZ vp = XYZ(0.0,0.0,0.0);
         XYZ  vd = XYZ(0.0,1.0,0.0);
         XYZ  vu = XYZ(0.0,0.0,1.0); // Camera view position, direction, and up
         XYZ right = XYZ(1.0,0.0,0.0);
         
         
         
         // Precompute what we can just once
         if (first == 1) {
             dh = tan(params.perspfov / 2.0);
             dv = float(perspheight) * dh / float(perspwidth);
             p1 = VectorSum(1.0,vp,1.0,vd,-dh,right, dv,vu);
             p2 = VectorSum(1.0,vp,1.0,vd,-dh,right,-dv,vu);
             p3 = VectorSum(1.0,vp,1.0,vd, dh,right,-dv,vu);
             p4 = VectorSum(1.0,vp,1.0,vd, dh,right, dv,vu);
             deltah.x = p4.x - p1.x;
             deltah.y = p4.y - p1.y;
             deltah.z = p4.z - p1.z;
             deltav.x = p2.x - p1.x;
             deltav.y = p2.y - p1.y;
             deltav.z = p2.z - p1.z;
             
             inversew = 1.0 / float(perspwidth);
             inverseh = 1.0 / float(perspheight);
             first = 0;
         }
         
         h = x * inversew;
         v = (float(perspheight) - 1.0 - y) * inverseh;
         p.x = p1.x + h * deltah.x + v * deltav.x;
         p.y = p1.y + h * deltah.y + v * deltav.y;
         p.z = p1.z + h * deltah.z + v * deltav.z;
     }
     
     /*
      Sum 4 vectors each with a scaling factor
      Only used 4 times for the first pixel
      */
     XYZ VectorSum(float d1,XYZ p1, float d2,XYZ p2, float d3,XYZ p3, float d4,XYZ p4)
     {
         XYZ sum;
         
         sum.x = d1 * p1.x + d2 * p2.x + d3 * p3.x + d4 * p4.x;
         sum.y = d1 * p1.y + d2 * p2.y + d3 * p3.y + d4 * p4.y;
         sum.z = d1 * p1.z + d2 * p2.z + d3 * p3.z + d4 * p4.z;
         
         return(sum);
     }
     
     void Init()
     {
         p1 = XYZ(0.0,0.0,0.0);
         p2 = XYZ(0.0,0.0,0.0);
         p3 = XYZ(0.0,0.0,0.0);
         p4 = XYZ(0.0,0.0,0.0); // Corners of the view frustum
         first = 1;
         deltah = XYZ(0.0,0.0,0.0);
         deltav = XYZ(0.0,0.0,0.0);
         inversew = 0.0;
         inverseh = 0.0;
     }
     
     void main()
     {
         vec3 yuv;
         vec3 rgb;
         
         rgb = (convertFish2persp() / 255.0);
         
         gl_FragColor = vec4(rgb,1);
     }
     );
    
    switch (pixelFormat) {
        case RGB_IRPixelFormat:
            fish2perspFragmentShaderString = RGB_PIXEL_FORMAT(fish2perspFragmentShaderString);
            fish2perspFragmentShaderString = RGB_PIXEL_FORMAT_PROCESSING(fish2perspFragmentShaderString);
            break;
        case YUV_IRPixelFormat:
            fish2perspFragmentShaderString = YUV_PIXEL_FORMAT(fish2perspFragmentShaderString);
            fish2perspFragmentShaderString = YUV_PIXEL_FORMAT_PROCESSING(fish2perspFragmentShaderString);
            break;
        case NV12_IRPixelFormat:
            fish2perspFragmentShaderString = NV12_PIXEL_FORMAT(fish2perspFragmentShaderString);
            fish2perspFragmentShaderString = NV12_PIXEL_FORMAT_PROCESSING(fish2perspFragmentShaderString);
            break;
    }
    
    return fish2perspFragmentShaderString;
}
@end
