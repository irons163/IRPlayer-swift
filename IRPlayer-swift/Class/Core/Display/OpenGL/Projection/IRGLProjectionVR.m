//
//  IRGLProjectionVR.m
//  IRPlayer
//
//  Created by Phil on 2019/8/21.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProjectionVR.h"

@implementation IRGLProjectionVR {
    GLfloat         _vertices[8];
}

-(instancetype)initWithTextureWidth:(float)w hidth:(float)h{
    if(self = [super init]){
        _vertices[0] = -1.0f;  // x0
        _vertices[1] = -1.0f;  // y0
        _vertices[2] =  1.0f;  // ..
        _vertices[3] = -1.0f;
        _vertices[4] = -1.0f;
        _vertices[5] =  1.0f;
        _vertices[6] =  1.0f;  // x3
        _vertices[7] =  1.0f;  // y3
        
        [self setupModel];
    }
    return self;
}

-(void) updateVertex{
    static const GLfloat texCoords[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };
    
    [self bindPositionLocation:ATTRIBUTE_VERTEX textureCoordLocation:ATTRIBUTE_TEXCOORD];
}

-(void)draw{
    glDrawElements(GL_TRIANGLES, self.index_count, GL_UNSIGNED_SHORT, 0);
}

- (void)bindPositionLocation:(GLint)position_location textureCoordLocation:(GLint)textureCoordLocation
{
    // index
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.index_id);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, self.index_count * sizeof(GLushort), index_buffer_data, GL_STATIC_DRAW);
    
    // vertex
    glBindBuffer(GL_ARRAY_BUFFER, self.vertex_id);
    glBufferData(GL_ARRAY_BUFFER, self.vertex_count * 3 * sizeof(GLfloat), vertex_buffer_data, GL_STATIC_DRAW);
    glEnableVertexAttribArray(position_location);
    glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), NULL);
    
    // texture coord
    glBindBuffer(GL_ARRAY_BUFFER, self.texture_id);
    glBufferData(GL_ARRAY_BUFFER, self.vertex_count * 2 * sizeof(GLfloat), texture_buffer_data, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(textureCoordLocation);
    glVertexAttribPointer(textureCoordLocation, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat)*2, NULL);
}

- (void)setupModel
{
    setup_vr();
    self.index_count = index_count;
    self.vertex_count = vertex_count;
    self.index_id = index_buffer_id;
    self.vertex_id = vertex_buffer_id;
    self.texture_id = texture_buffer_id;
}

static GLuint vertex_buffer_id = 0;
static GLuint index_buffer_id = 0;
static GLuint texture_buffer_id = 0;

static GLfloat * vertex_buffer_data = NULL;
static GLushort * index_buffer_data = NULL;
static GLfloat * texture_buffer_data = NULL;

static int const slices_count = 200;
static int const parallels_count = slices_count / 2;

static int const index_count = slices_count * parallels_count * 6;
static int const vertex_count = (slices_count + 1) * (parallels_count + 1);

void setup_vr()
{
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
    
        float const step = (2.0f * M_PI) / (float)slices_count;
        float const radius = 1.0f;
        
        // model
        index_buffer_data = malloc(sizeof(GLushort) * index_count);
        vertex_buffer_data = malloc(sizeof(GLfloat) * 3 * vertex_count);
        texture_buffer_data = malloc(sizeof(GLfloat) * 2 * vertex_count);
        
        int runCount = 0;
        for (int i = 0; i < parallels_count + 1; i++)
        {
            for (int j = 0; j < slices_count + 1; j++)
            {
                int vertex = (i * (slices_count + 1) + j) * 3;
                
                if (vertex_buffer_data)
                {
                    vertex_buffer_data[vertex + 0] = radius * sinf(step * (float)i) * cosf(step * (float)j);
                    vertex_buffer_data[vertex + 1] = radius * cosf(step * (float)i);
                    vertex_buffer_data[vertex + 2] = radius * sinf(step * (float)i) * sinf(step * (float)j);
                }
                
                if (texture_buffer_data)
                {
                    int textureIndex = (i * (slices_count + 1) + j) * 2;
                    texture_buffer_data[textureIndex + 0] = (float)j / (float)slices_count;
                    texture_buffer_data[textureIndex + 1] = ((float)i / (float)parallels_count);
                }
                
                if (index_buffer_data && i < parallels_count && j < slices_count)
                {
                    index_buffer_data[runCount++] = i * (slices_count + 1) + j;
                    index_buffer_data[runCount++] = (i + 1) * (slices_count + 1) + j;
                    index_buffer_data[runCount++] = (i + 1) * (slices_count + 1) + (j + 1);
                    
                    index_buffer_data[runCount++] = i * (slices_count + 1) + j;
                    index_buffer_data[runCount++] = (i + 1) * (slices_count + 1) + (j + 1);
                    index_buffer_data[runCount++] = i * (slices_count + 1) + (j + 1);
                }
            }
        }
        
        glGenBuffers(1, &index_buffer_id);
        glGenBuffers(1, &vertex_buffer_id);
        glGenBuffers(1, &texture_buffer_id);
//    });
}

@end
