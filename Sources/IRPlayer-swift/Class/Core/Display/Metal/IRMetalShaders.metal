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

vertex VertexOut irVertex(VertexIn in [[stage_in]],
                          constant float2 &scale [[buffer(1)]]) {
    VertexOut out;
    float2 scaled = in.position * scale;
    out.position = float4(scaled, 0.0, 1.0);
    out.texCoord = float2(in.texCoord.x, 1.0 - in.texCoord.y);
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
