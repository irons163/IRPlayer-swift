//
//  IRGLDefine.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#ifndef IRGLDefine_h
#define IRGLDefine_h

#define STRINGIZE(...) #__VA_ARGS__
#define STRINGIZE2(...) STRINGIZE(__VA_ARGS__)
#define SHADER_STRING(...) @ STRINGIZE2(__VA_ARGS__)

#endif /* IRGLDefine_h */
