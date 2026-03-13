//
//  IRMetalShaders.metal
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/8.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct DistortionVertexIn {
    float2 position [[attribute(0)]];
    float vignette [[attribute(1)]];
    float2 redTexCoord [[attribute(2)]];
    float2 greenTexCoord [[attribute(3)]];
    float2 blueTexCoord [[attribute(4)]];
};

struct DistortionVertexOut {
    float4 position [[position]];
    float vignette;
    float2 redTexCoord;
    float2 greenTexCoord;
    float2 blueTexCoord;
};

struct Fish2PanoParams {
    int fishwidth;
    int fishheight;
    int panowidth;
    int panoheight;
    int antialias;
    float offsetX;
    float2 _padding;
};

vertex VertexOut irVertex(VertexIn in [[stage_in]],
                          constant float2 &scale [[buffer(1)]]) {
    VertexOut out;
    float2 scaled = in.position * scale;
    out.position = float4(scaled, 0.0, 1.0);
    out.texCoord = float2(in.texCoord.x, 1.0 - in.texCoord.y);
    return out;
}

vertex DistortionVertexOut irDistortionVertex(DistortionVertexIn in [[stage_in]]) {
    DistortionVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.vignette = in.vignette;
    out.redTexCoord = in.redTexCoord;
    out.greenTexCoord = in.greenTexCoord;
    out.blueTexCoord = in.blueTexCoord;
    return out;
}

struct VertexIn3D {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

vertex VertexOut irVertex3D(VertexIn3D in [[stage_in]],
                            constant float4x4 &mvp [[buffer(1)]],
                            constant float4x4 &texMatrix [[buffer(2)]]) {
    VertexOut out;
    float4 pos = mvp * float4(in.position, 1.0);
    pos.y = -pos.y;
    out.position = pos;
    out.texCoord = (texMatrix * float4(in.texCoord, 0.0, 1.0)).xy;
    return out;
}

inline float2 sampleTexUV(int idx,
                          float2 uv,
                          array<texture2d<float, access::sample>, 9> texUV,
                          sampler s) {
    idx = clamp(idx, 0, 8);
    float2 uvPixel = texUV[idx].sample(s, uv).rg;
    return uvPixel;
}

fragment float4 irFragmentFish2PanoNV12(VertexOut in [[stage_in]],
                                        constant Fish2PanoParams &params [[buffer(0)]],
                                        texture2d<float, access::sample> yTex [[texture(0)]],
                                        texture2d<float, access::sample> uvTex [[texture(1)]],
                                        array<texture2d<float, access::sample>, 9> texUV [[texture(4)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    if (params.antialias <= 0 || params.panowidth <= 0 || params.panoheight <= 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float3 accum = float3(0.0);
    int samples = 0;
    float2 baseUV = in.texCoord;
    baseUV.x += params.offsetX / float(params.panowidth);
    if (baseUV.x > 1.0) { baseUV.x -= 1.0; }
    if (baseUV.x < 0.0) { baseUV.x += 1.0; }

    for (int ai = 0; ai < params.antialias; ai++) {
        for (int aj = 0; aj < params.antialias; aj++) {
            int aa = ai * params.antialias + aj;
            float2 uvPixel = sampleTexUV(aa, baseUV, texUV, s);
            float u = uvPixel.x;
            float v = uvPixel.y;
            if (u < 0.0 || u > float(params.fishwidth) || v < 0.0 || v > float(params.fishheight)) {
                continue;
            }
            float2 fishUV = float2(u / float(params.fishwidth), v / float(params.fishheight));
            float y = yTex.sample(s, fishUV).r - (16.0 / 255.0);
            float2 uv = uvTex.sample(s, fishUV).rg - float2(0.5, 0.5);
            float r = y + 1.402 * uv.y;
            float g = y - 0.344136 * uv.x - 0.714136 * uv.y;
            float b = y + 1.772 * uv.x;
            accum += float3(r, g, b);
            samples += 1;
        }
    }

    if (samples <= 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return float4(accum / float(samples), 1.0);
}

fragment float4 irFragmentFish2PanoI420(VertexOut in [[stage_in]],
                                        constant Fish2PanoParams &params [[buffer(0)]],
                                        texture2d<float, access::sample> yTex [[texture(0)]],
                                        texture2d<float, access::sample> uTex [[texture(1)]],
                                        texture2d<float, access::sample> vTex [[texture(2)]],
                                        array<texture2d<float, access::sample>, 9> texUV [[texture(4)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    if (params.antialias <= 0 || params.panowidth <= 0 || params.panoheight <= 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float3 accum = float3(0.0);
    int samples = 0;
    float2 baseUV = in.texCoord;
    baseUV.x += params.offsetX / float(params.panowidth);
    if (baseUV.x > 1.0) { baseUV.x -= 1.0; }
    if (baseUV.x < 0.0) { baseUV.x += 1.0; }

    for (int ai = 0; ai < params.antialias; ai++) {
        for (int aj = 0; aj < params.antialias; aj++) {
            int aa = ai * params.antialias + aj;
            float2 uvPixel = sampleTexUV(aa, baseUV, texUV, s);
            float u = uvPixel.x;
            float v = uvPixel.y;
            if (u < 0.0 || u > float(params.fishwidth) || v < 0.0 || v > float(params.fishheight)) {
                continue;
            }
            float2 fishUV = float2(u / float(params.fishwidth), v / float(params.fishheight));
            float y = yTex.sample(s, fishUV).r - (16.0 / 255.0);
            float uVal = uTex.sample(s, fishUV).r - 0.5;
            float vVal = vTex.sample(s, fishUV).r - 0.5;
            float r = y + 1.402 * vVal;
            float g = y - 0.344136 * uVal - 0.714136 * vVal;
            float b = y + 1.772 * uVal;
            accum += float3(r, g, b);
            samples += 1;
        }
    }

    if (samples <= 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return float4(accum / float(samples), 1.0);
}

fragment float4 irFragmentFish2PanoRGB(VertexOut in [[stage_in]],
                                       constant Fish2PanoParams &params [[buffer(0)]],
                                       texture2d<float, access::sample> rgbTex [[texture(0)]],
                                       array<texture2d<float, access::sample>, 9> texUV [[texture(4)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    if (params.antialias <= 0 || params.panowidth <= 0 || params.panoheight <= 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float3 accum = float3(0.0);
    int samples = 0;
    float2 baseUV = in.texCoord;
    baseUV.x += params.offsetX / float(params.panowidth);
    if (baseUV.x > 1.0) { baseUV.x -= 1.0; }
    if (baseUV.x < 0.0) { baseUV.x += 1.0; }

    for (int ai = 0; ai < params.antialias; ai++) {
        for (int aj = 0; aj < params.antialias; aj++) {
            int aa = ai * params.antialias + aj;
            float2 uvPixel = sampleTexUV(aa, baseUV, texUV, s);
            float u = uvPixel.x;
            float v = uvPixel.y;
            if (u < 0.0 || u > float(params.fishwidth) || v < 0.0 || v > float(params.fishheight)) {
                continue;
            }
            float2 fishUV = float2(u / float(params.fishwidth), v / float(params.fishheight));
            float3 color = rgbTex.sample(s, fishUV).rgb;
            accum += color;
            samples += 1;
        }
    }

    if (samples <= 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return float4(accum / float(samples), 1.0);
}

fragment float4 irFragmentNV12(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> yTex [[texture(0)]],
                               texture2d<float, access::sample> uvTex [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float y = yTex.sample(s, in.texCoord).r;
    float2 uv = uvTex.sample(s, in.texCoord).rg - float2(0.5, 0.5);
    float r = y + 1.402 * uv.y;
    float g = y - 0.344136 * uv.x - 0.714136 * uv.y;
    float b = y + 1.772 * uv.x;
    return float4(r, g, b, 1.0);
}

fragment float4 irFragmentI420(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> yTex [[texture(0)]],
                               texture2d<float, access::sample> uTex [[texture(1)]],
                               texture2d<float, access::sample> vTex [[texture(2)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float y = yTex.sample(s, in.texCoord).r;
    float u = uTex.sample(s, in.texCoord).r - 0.5;
    float v = vTex.sample(s, in.texCoord).r - 0.5;
    float r = y + 1.402 * v;
    float g = y - 0.344136 * u - 0.714136 * v;
    float b = y + 1.772 * u;
    return float4(r, g, b, 1.0);
}

fragment float4 irFragmentRGB(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> rgbTex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = rgbTex.sample(s, in.texCoord);
    return float4(color.rgb, 1.0);
}

fragment float4 irFragmentDistortion(DistortionVertexOut in [[stage_in]],
                                    texture2d<float, access::sample> frameTex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float r = frameTex.sample(s, in.redTexCoord).r;
    float g = frameTex.sample(s, in.greenTexCoord).g;
    float b = frameTex.sample(s, in.blueTexCoord).b;
    return float4(r, g, b, 1.0);
}
