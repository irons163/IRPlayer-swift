//
//  IRGLFish2PanoShaderParams.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFish2PanoShaderParams.h"
#import "IRGLMath.h"
#import <OpenGLES/ES3/gl.h>


@implementation IRGLFish2PanoShaderParams {
    enum
    {
        UNIFORM_ROTATION_ANGLE,
        UNIFORM_TEXTURE_WIDTH,
        UNIFORM_TEXTURE_HEIGHT,
        UNIFORM_FISH_APERTURE,
        UNIFORM_FISH_CENTERX,
        UNIFORM_FISH_CENTERY,
        UNIFORM_FISH_RADIUS_H,
        UNIFORM_FISH_RADIUS_V,
        UNIFORM_OUTPUT_WIDTH,
        UNIFORM_OUTPUT_HEIGHT,
        UNIFORM_ANTIALIAS,
        UNIFORM_VAPERTURE,
        UNIFORM_LAT1,
        UNIFORM_LAT2,
        UNIFORM_LONG1,
        UNIFORM_LONG2,
        UNIFORM_ENABLE_TRANSFORM_X,
        UNIFORM_ENABLE_TRANSFORM_Y,
        UNIFORM_ENABLE_TRANSFORM_Z,
        UNIFORM_TRANSFORM_X,
        UNIFORM_TRANSFORM_Y,
        UNIFORM_TRANSFORM_Z,
        UNIFORM_OFFSETX,
        NUM_UNIFORMS
    };
    
    GLint _uniformSamplers[NUM_UNIFORMS];
    NSMutableArray *_texUVs, *_ltexUVs;
    float_t** pixUV;
    GLint _uUseTexUVs;
    BOOL useTexUVs;
}

-(instancetype)init {
    if(self = [super init]){
        [self setDefaultValues];
    }
    return self;
}

- (void) resolveUniforms: (GLuint) program {
    _uniformSamplers[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(program, "preferredRotation");
    _uniformSamplers[UNIFORM_TEXTURE_WIDTH] = glGetUniformLocation(program, "fishwidth");
    _uniformSamplers[UNIFORM_TEXTURE_HEIGHT] = glGetUniformLocation(program, "fishheight");
    _uniformSamplers[UNIFORM_FISH_APERTURE] = glGetUniformLocation(program, "fishaperture");
    _uniformSamplers[UNIFORM_FISH_CENTERX] = glGetUniformLocation(program, "fishcenterx");
    _uniformSamplers[UNIFORM_FISH_CENTERY] = glGetUniformLocation(program, "fishcentery");
    _uniformSamplers[UNIFORM_FISH_RADIUS_H] = glGetUniformLocation(program, "fishradiush");
    _uniformSamplers[UNIFORM_FISH_RADIUS_V] = glGetUniformLocation(program, "fishradiusv");
    _uniformSamplers[UNIFORM_OUTPUT_WIDTH] = glGetUniformLocation(program, "panowidth");
    _uniformSamplers[UNIFORM_OUTPUT_HEIGHT] = glGetUniformLocation(program, "panoheight");
    _uniformSamplers[UNIFORM_ANTIALIAS] = glGetUniformLocation(program, "antialias");
    _uniformSamplers[UNIFORM_VAPERTURE] = glGetUniformLocation(program, "vaperture");
    _uniformSamplers[UNIFORM_LAT1] = glGetUniformLocation(program, "lat1");
    _uniformSamplers[UNIFORM_LAT2] = glGetUniformLocation(program, "lat2");
    _uniformSamplers[UNIFORM_LONG1] = glGetUniformLocation(program, "long1");
    _uniformSamplers[UNIFORM_LONG2] = glGetUniformLocation(program, "long2");
    _uniformSamplers[UNIFORM_ENABLE_TRANSFORM_X] = glGetUniformLocation(program, "enableTransformX");
    _uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Y] = glGetUniformLocation(program, "enableTransformY");
    _uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Z] = glGetUniformLocation(program, "enableTransformZ");
    _uniformSamplers[UNIFORM_TRANSFORM_X] = glGetUniformLocation(program, "transformX");
    _uniformSamplers[UNIFORM_TRANSFORM_Y] = glGetUniformLocation(program, "transformY");
    _uniformSamplers[UNIFORM_TRANSFORM_Z] = glGetUniformLocation(program, "transformZ");
    _uniformSamplers[UNIFORM_OFFSETX] = glGetUniformLocation(program, "offsetX");
    
    int texnum = _antialias * _antialias;
    if(texnum <= 0 || texnum > 9){
        NSLog(@"Antialias level should be an integer between 1 and 3.");
        return;
    }
    
    _texUVs = [[NSMutableArray alloc] initWithCapacity:texnum];
    _ltexUVs = [[NSMutableArray alloc] initWithCapacity:texnum];
    
    for (int i = 0; i < texnum; i++) {
        _ltexUVs[i] = [NSNumber numberWithInt:glGetUniformLocation(program, [[NSString stringWithFormat:@"texUV%d", i] UTF8String])];
    }
    
    _uUseTexUVs = glGetUniformLocation(program, "useTexUVs");
}

-(void) initPixelMaps {
    float_t transX = self.transformX * DTOR;
    float_t transY = self.transformY * DTOR;
    float_t transZ = self.transformZ * DTOR;
    float_t tlat1 = tan(self.lat1 * DTOR);
    float_t tlat2 = tan(self.lat2 * DTOR);
    float_t lng1 = self.long1 * DTOR;
    float_t dlng = (self.long2 * DTOR - lng1);
    float_t raperture = 2.0 / (self.fishaperture * DTOR);
    float_t y0 = (tlat1 + tlat2) / (tlat1 - tlat2);
    //        float_t tvaperture = Math.tan(0.5 * Math.toRadians(DEFAULT_VAPERTURE));
    //        boolean symmetric = Math.abs(DEFAULT_LAT1) >= 90 ||
    //                Math.abs(DEFAULT_LAT2) >= 90;
    for(int y = 0; y < self.outputHeight; y++){
        for(int x = 0 ; x < self.outputWidth; x++){
            for (int i = 0; i < self.antialias; i++) {
                float_t xx = (x + i / (float_t)self.antialias) / (float_t)self.outputWidth;
                float_t longitude = lng1 + xx * dlng;
                for (int j = 0; j < self.antialias; j++) {
                    float_t yy = 2.0 * (y + j /(float_t)self.antialias) / (float_t)self.outputHeight - 1.0;
                    float_t latitude;
                    //                if (symmetric)
                    //                    latitude = Math.atan(yy * tvaperture);
                    //                else
                    if (yy > y0) {
                        if (1.0 - y0 == 0) {
                            latitude = 0;
                        } else {
                            latitude = atan((yy - y0) * tlat2 / (1.0 - y0));
                        }
                    } else {
                        if (-1.0 - y0 == 0) {
                            latitude = 0;
                        } else {
                            latitude = atan((yy - y0) * tlat1 / (-1.0 - y0));
                        }
                    }
                    [self setPixelFactors:latitude :longitude :self.antialias*i+j :x :y :transX :transY :transZ :raperture];
                }
            }
        }
    }
}

-(void) setPixelFactors:(float_t) latitude :(float_t) longitude :(int) index :(int) x :(int) y :(float_t) transX :(float_t) transY :(float_t) transZ :(float_t) raperture{
    XYZ p;
    float_t latcos = cos(latitude);
    p.x = latcos * cos(longitude);
    p.y = latcos * sin(longitude);
    p.z = sin(latitude);
    if(transX != 0)
        p = PRotateX(p, transX);
    if(transY != 0)
        p = PRotateY(p, transY);
    if(transZ != 0)
        p = PRotateZ(p, transZ);
    float_t theta = atan2(p.y, p.x);
    float_t phi = atan2(sqrt(p.x * p.x + p.y * p.y), p.z);
    float_t r = phi * raperture;
    //    int u = (int)(self.fishcenterx + self.fishradiush * r * cos(theta));
    float u = self.fishcenterx + self.fishradiush * r * cos(theta);
    if (u < 0 || u >= self.textureWidth){
        float_t *bytes = pixUV[index];
        //        bytes[(self.outputWidth*y + x) * 4] = (float_t)0xff;
        //        bytes[(self.outputWidth*y + x) * 4 + 1] = (float_t)0xff;
        //        bytes[(self.outputWidth*y + x) * 4 + 2] = (float_t)0xff;
        //        bytes[(self.outputWidth*y + x) * 4 + 3] = (float_t)0xff;
        bytes[(self.outputWidth*y + x) * 2] = (float_t)-1;
        bytes[(self.outputWidth*y + x) * 2 + 1] = (float_t)-1;
        return;
    }
    //    int v = (int)((self.textureHeight - self.fishcentery) + self.fishradiush * r * sin(theta));
    //    int v = (int)(self.fishcentery + self.fishradiush * r * sin(theta));
    //    float v = self.fishcentery + self.fishradiush * r * sin(theta);
    float v = (self.textureHeight - self.fishcentery) + self.fishradiush * r * sin(theta);
    if (v < 0 || v >= self.textureHeight){
        float_t *bytes = pixUV[index];
        bytes[(self.outputWidth*y + x) * 2] = (float_t)-1;
        bytes[(self.outputWidth*y + x) * 2 + 1] = (float_t)-1;
        return;
    }
    
    float_t *bytes = pixUV[index];
    bytes[(self.outputWidth*y + x) * 2] = (float_t)(u );
    bytes[(self.outputWidth*y + x) * 2 + 1] = (float_t)(v );
}

//    private String getPixUVString(int index, int x, int y) {
//        int resu, resv;
//        resu = ((int)pixUV[index].get((panoramaWidth*y + x) * 4) & 0xff);
//        resu |= (((int)pixUV[index].get((panoramaWidth*y + x) * 4 + 1)) << 8);
//        resv = ((int)pixUV[index].get((panoramaWidth*y + x) * 4 + 2) & 0xff);
//        resv |= (((int)pixUV[index].get((panoramaWidth*y + x) * 4 + 3)) << 8);
//        return "("+resu+","+resv+")";
//    }

struct XYZ {
    float_t x;
    float_t y;
    float_t z;
};

typedef struct XYZ XYZ;

XYZ PRotateX(XYZ p, float_t theta)
{
    float_t costheta = cos(theta);
    float_t sintheta = sin(theta);
    float_t y = p.y;
    float_t z = p.z;
    p.y = y * costheta + z * sintheta;
    p.z = -y * sintheta + z * costheta;
    return p;
}

XYZ PRotateY(XYZ p, float_t theta)
{
    float_t costheta = cos(theta);
    float_t sintheta = sin(theta);
    float_t x = p.x;
    float_t z = p.z;
    p.x = x * costheta - z * sintheta;
    p.z = x * sintheta + z * costheta;
    return p;
}

XYZ PRotateZ(XYZ p, float_t theta)
{
    float_t costheta = cos(theta);
    float_t sintheta = sin(theta);
    float_t x = p.x;
    float_t y = p.y;
    p.x = x * costheta + y * sintheta;
    p.y = -x * sintheta + y * costheta;
    return p;
}

-(void)prepareRender{
    // 0 and 1 are the texture IDs of _lumaTexture and _chromaTexture respectively.
    glUniform1f(_uniformSamplers[UNIFORM_ROTATION_ANGLE], self.preferredRotation);
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_WIDTH], self.textureWidth);
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_HEIGHT], self.textureHeight);
    glUniform1f(_uniformSamplers[UNIFORM_FISH_APERTURE], self.fishaperture);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_CENTERX], self.fishcenterx);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_CENTERY], self.fishcentery);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_RADIUS_H], self.fishradiush);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_RADIUS_V], self.fishradiusv);
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_WIDTH], self.outputWidth);
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_HEIGHT], self.outputHeight);
    glUniform1i(_uniformSamplers[UNIFORM_ANTIALIAS], self.antialias);
    glUniform1f(_uniformSamplers[UNIFORM_VAPERTURE], self.vaperture);
    glUniform1f(_uniformSamplers[UNIFORM_LAT1], self.lat1);
    glUniform1f(_uniformSamplers[UNIFORM_LAT2], self.lat2);
    glUniform1f(_uniformSamplers[UNIFORM_LONG1], self.long1);
    glUniform1f(_uniformSamplers[UNIFORM_LONG2], self.long2);
    glUniform1i(_uniformSamplers[UNIFORM_ENABLE_TRANSFORM_X], self.enableTransformX);
    glUniform1i(_uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Y], self.enableTransformY);
    glUniform1i(_uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Z], self.enableTransformZ);
    glUniform1f(_uniformSamplers[UNIFORM_TRANSFORM_X], self.transformX);
    glUniform1f(_uniformSamplers[UNIFORM_TRANSFORM_Y], self.transformY);
    glUniform1f(_uniformSamplers[UNIFORM_TRANSFORM_Z], self.transformZ);
    glUniform1f(_uniformSamplers[UNIFORM_OFFSETX], self.offsetX);
    
    //        GLKMatrix4 texMatrix = GLKMatrix4Translate(GLKMatrix4Identity, 0, 0, 1);
    //        GLKMatrix4 texMatrix = GLKMatrix4Identity;
    
    if(useTexUVs){
        int texnum = [_ltexUVs count];
        
        for (int i = 0; i < texnum; i++) {
            GLuint tex[1];
            glActiveTexture(GL_TEXTURE4+i);
            glGenTextures(1, tex);
            
            _texUVs[i] = [NSNumber numberWithUnsignedInt:tex[0]];
            glBindTexture(GL_TEXTURE_2D, [_texUVs[i] unsignedIntValue]);
            
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RG32F, self.outputWidth, self.outputHeight, 0,
                         GL_RG, GL_FLOAT, pixUV[i]);
            
            glUniform1i([_ltexUVs[i] intValue], i+4);
        }
        
        glUniform1i(_uUseTexUVs, 1);
        useTexUVs = NO;
    }else{
        int texnum = [_texUVs count];
        for (int i = 0; i < texnum; ++i) {
            glActiveTexture(GL_TEXTURE4 + i);
            glBindTexture(GL_TEXTURE_2D, [_texUVs[i] unsignedIntValue]);
            glUniform1i([_ltexUVs[i] intValue], i+4);
        }
    }
}

-(void) setDefaultValues
{
    [super setTextureWidth:-1];       // Derived from input fisheye file
    [super setTextureHeight:-1];
    _fishaperture = 180.0;   // Aperture of the fisheye
    _fishcenterx = -1;     // Center of the fisheye (pixels), measured from lower-left corner
    _fishcentery = -1;
    _fishradiush = -1;     // Radius of the fisheye (pixels)
    _fishradiusv = -1;
    [super setOutputWidth:1024];     // Width and height of panoramic view
    [super setOutputHeight:-1];      // If not specified, work it out
    _antialias = 1;
    _vaperture = 60.0;
    _lat1 = -100.0;
    _lat2 = 100.0;
    _long1 = 0.0;
    _long2 = 360.0;
}

-(void)setOutputWidth:(GLint)outputWidth{
    if(self.outputWidth == outputWidth)
        return;
    [super setOutputWidth:outputWidth];
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_WIDTH], self.outputWidth);
}

-(void)setOutputHeight:(GLint)outputHeight{
    if(self.outputHeight == outputHeight)
        return;
    [super setOutputHeight:outputHeight];
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_HEIGHT], self.outputHeight);
}

-(void)setTextureWidth:(GLint)textureWidth{
    if(self.textureWidth == textureWidth)
        return;
    [super setTextureWidth:textureWidth];
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_WIDTH], self.textureWidth);
}

-(void)setTextureHeight:(GLint)textureHeight{
    if(self.textureHeight == textureHeight)
        return;
    [super setTextureHeight:textureHeight];
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_HEIGHT], self.textureHeight);
    
}

-(void)updateTextureWidth:(NSUInteger)w height:(NSUInteger)h{
    if(self.textureWidth != w || self.textureHeight != h){
    self.textureWidth = w;
    self.textureHeight = h;
    
    self.fishcenterx = self.textureWidth / 2.0;
    self.fishcentery = self.textureHeight / 2.0;
    self.fishradiush = self.textureWidth / 2.0;
    self.fishradiusv = self.textureHeight / 2.0;
        
    if(w == 0 || h == 0)
        return;
    
    [self updateOutputWH];
    
    if(self.delegate)
        [self.delegate didUpdateOutputWH:self.outputWidth :self.outputHeight];
    }
}

-(void)updateOutputWH{
    //    self.lat1 = -60.0;
    //    self.lat2 = 0.0;
    self.lat1 = 0.0;
    self.lat2 = 60.0;
    self.vaperture = fabs(self.lat2 - self.lat1);
    self.long1 = 0.0;
    self.long2 = 360.0;
    
    float long1Radians = self.long1 * DTOR;
    float long2Radians = self.long2 * DTOR;
    float vapertureRadians = self.vaperture * DTOR;
    
    // Set pano height if not specified
    if (RTOD*0.5*vapertureRadians > 80.0) {
        vapertureRadians = 160.0*DTOR;
    }
    
    self.outputWidth = 1.422222222222222 * self.textureWidth;
    self.outputHeight = (int)(self.outputWidth * tan(0.5*vapertureRadians) / (0.5*(long2Radians - long1Radians)));
    
//    self.fishcenterx = 680;
    
//    self.fishcentery = 530;
    
//    self.fishradiush = 480;
    self.enableTransformX = 1;
    //    self.transformX = 180;
    //    self.enableTransformY = 1;
    //    self.transformY = -90;
    self.enableTransformZ = 1;
    self.transformZ = -90;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int texnum = [_ltexUVs count];
        
        pixUV = malloc(texnum * sizeof(float_t*));
        for (int i = 0; i < texnum; i++) {
            pixUV[i] = malloc(self.outputWidth * self.outputHeight * 2 * sizeof(float_t));
        }
        
        [self initPixelMaps];
        
        useTexUVs = YES;
    });
}

//-(void)setModelviewProj:(GLKMatrix4) modelviewProj{
//    _modelviewProj = modelviewProj;
//}

@end
