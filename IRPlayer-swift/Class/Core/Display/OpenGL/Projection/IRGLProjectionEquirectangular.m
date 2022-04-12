//
//  IRGLProjectionEquirectangular.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProjectionEquirectangular.h"
#import "IRFisheyeParameter.h"

const float SPHERE_RADIUS = 800.0f;

const int SPHERE_SLICES = 180;
const int SPHERE_INDICES_PER_VERTEX = 1; // TODO changeable
const float POLAR_LAT = 85.0f;

@implementation IRGLProjectionEquirectangular {
    int16_t** mIndices;
    int slices;
    float* mVertices;
    float* mVectors;
    int mTotalIndices;
    int indicesPerVertex;
    int* mNumIndices;
    float x0 ;
    float y0 ;
    float z0 ;
    float r0 ;
    float tw ;
    float th ;
    float cr ;
    float cx ;
    float cy ;
}

-(instancetype)initWithTextureWidth:(float)w height:(float)h centerX:(float)centerX centerY:(float)centerY radius:(float)radius {
    if(self = [super init]){
        [self setupWithTextureWidth:w height:h centerX:centerX centerY:centerY radius:radius];
    }
    return self;
}

- (void)setupWithTextureWidth:(float)w height:(float)h centerX:(float)centerX centerY:(float)centerY radius:(float)radius {
    x0 = y0 = z0 = 0;
    r0 = SPHERE_RADIUS;
    slices = SPHERE_SLICES;
    indicesPerVertex = SPHERE_INDICES_PER_VERTEX;
    //        tw = 1440;
    //        th = 1080;
    //        cr = 510;
    //        cx = 680;
    //        cy = 524;
    
    tw = w;
    th = h;
    
    if(radius == 0 ||
       centerX == 0 ||
       centerY == 0 ||
       radius > w / 2 ||
       radius > h / 2 ||
       radius + centerX > w ||
       radius + centerY > h){
        NSLog(@"illegal params, set default ones...");
        centerX = w / 2;
        centerY = h / 2;
        radius = h/ 2;
        radius = w > h? h / 2 : h / 2;
    }
    
    cr = radius;
    cx = centerX;
    cy = centerY;
    
    [self initBuffers:tw :th :cr :cx :cy];
}

-(void) initBuffers:(float) tw :(float) th :(float) cr :(float) cx :(float) cy {
    if (cr <= 0 || cx <= 0 || cy <= 0 || tw < cr || th < cr || cx + cr > tw || cy + cr > th) {
        NSLog(@"illegal params");
        //        return; // if return, when call draw method make APP crash.
    }
    int iMax = slices + 1;
    int nVertices = iMax * iMax;
    if (nVertices > NSIntegerMax) {
        // this cannot be handled in one vertices / indices pair
        NSLog(@"nSlices %d too big for vertex", slices);
        return;
    }
    float offsetX = cx;
    float offsetY = cy;
    // TODO coordinate transfermation in source image
    mVertices = malloc(nVertices * 3 * sizeof(float));
    mVectors = malloc(nVertices * 2 * sizeof(float));
    mTotalIndices = slices * slices * 6;
    mIndices = malloc(indicesPerVertex * sizeof(int16_t*));
    mNumIndices = malloc(indicesPerVertex * sizeof(int));
    int noIndicesPerBuffer = (mTotalIndices / indicesPerVertex / 6) * 6;
    for (int i = 0; i < indicesPerVertex - 1; i++) {
        mNumIndices[i] = noIndicesPerBuffer;
    }
    mNumIndices[indicesPerVertex - 1] = mTotalIndices - noIndicesPerBuffer *
    (indicesPerVertex - 1);
    for (int i = 0; i < indicesPerVertex; i++) {
        mIndices[i] = malloc(mNumIndices[i] * sizeof(int16_t));
    }
    uint32_t mVerticesPosition = 0;
    uint32_t mVectorsPosition = 0;
    float vLineBuffer[iMax * 3];
    float vLineBuffer2[iMax * 2];
    const float angleStep = ((float) PI / slices);
    for (int i = 0; i < iMax; i++) {
        float sini = (float) sin(angleStep * i);
        float cosi = (float) cos(angleStep * i);
        for (int j = 0; j < iMax; j++) {
            int vertexBase = j * 3;
            //            int vectorBase = j * 2;
            int vectorBase = (iMax - j - 1) * 2;
            float sinisinj = (float) sin(angleStep * j) * sini;
            float sinicosj = (float) cos(angleStep * j) * sini;
            // vertex x,y,z
            vLineBuffer[vertexBase + 0] = x0 + r0 * sinisinj;
            vLineBuffer[vertexBase + 1] = y0 + r0 * sinicosj;
            vLineBuffer[vertexBase + 2] = z0 + r0 * cosi;
            
            vLineBuffer2[vectorBase + 0] = (offsetX - cr * sinicosj) / (float)tw;
            vLineBuffer2[vectorBase + 1] = (cr * cosi - offsetY) / (float)th;
        }
        uint32_t mVerticesLength = sizeof(vLineBuffer);
        uint32_t mVectorsLength = sizeof(vLineBuffer2);
        memcpy(mVertices + mVerticesPosition/sizeof(float), vLineBuffer, mVerticesLength);
        memcpy(mVectors + mVectorsPosition/sizeof(float), vLineBuffer2, mVectorsLength);
        mVerticesPosition += mVerticesLength;
        mVectorsPosition += mVectorsLength;
    }
    //    int16_t indexBuffer[[self getMaxItem:mNumIndices]];
    int16_t* indexBuffer = malloc([self getMaxItem:mNumIndices size:indicesPerVertex] * sizeof(int16_t));
    int index = 0;
    int bufferNum = 0;
    for (int i = 0; i < slices; i++) {
        int i1 = i + 1;
        for (int j = 0; j < slices; j++) {
            int j1 = j + 1;
            if (index >= mNumIndices[bufferNum]) {
                // buffer ready for moving to target
                memcpy(mIndices[bufferNum], indexBuffer, mNumIndices[bufferNum] * sizeof(int16_t));
                // move to the next one
                index = 0;
                bufferNum++;
            }
            indexBuffer[index++] = (short) (i * iMax + j);
            indexBuffer[index++] = (short) (i1 * iMax + j);
            indexBuffer[index++] = (short) (i1 * iMax + j1);
            indexBuffer[index++] = (short) (i * iMax + j);
            indexBuffer[index++] = (short) (i1 * iMax + j1);
            indexBuffer[index++] = (short) (i * iMax + j1);
        }
    }
    memcpy(mIndices[bufferNum], indexBuffer, mNumIndices[bufferNum] * sizeof(int16_t));
    
    free(indexBuffer);
}

-(int) getMaxItem:(int*) array size:(int)arraySize{
    int max = array[0];
    for (int i = 1; i < arraySize; i++)
        if (array[i] > max)
            max = array[i];
    return max;
}

-(void) updateVertex{
    glVertexAttribPointer(ATTRIBUTE_VERTEX, 3, GL_FLOAT, 0, 0, mVertices);
    glEnableVertexAttribArray(ATTRIBUTE_VERTEX);
    glVertexAttribPointer(ATTRIBUTE_TEXCOORD, 2, GL_FLOAT, 0, 0, mVectors);
    glEnableVertexAttribArray(ATTRIBUTE_TEXCOORD);
}

-(void)draw{
    for (int j = 0; j < indicesPerVertex; ++j) {
        glDrawElements(GL_TRIANGLES,
                       mNumIndices[j], GL_UNSIGNED_SHORT,
                       mIndices[j]);
    }
}

- (void)updateWithParameter:(IRMediaParameter *)parameter {
    if([parameter isKindOfClass:[IRFisheyeParameter class]]) {
        if(tw == parameter.width && th == parameter.height)
            return;
        
        IRFisheyeParameter *p = (IRFisheyeParameter*)parameter;
        [self setupWithTextureWidth:p.width height:p.height centerX:p.cx centerY:p.cy radius:p.rx];
    }
}

-(void)dealloc{
    for(int i = 0 ; i < indicesPerVertex; i++){
        int16_t* mIndice = mIndices[i];
        free(mIndice);
    }
    free(mIndices);
    free(mVertices);
    free(mVectors);
    free(mNumIndices);
}

@end
