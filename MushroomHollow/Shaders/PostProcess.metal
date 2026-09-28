#include <metal_stdlib>
using namespace metal;

// Must match `GradeUniforms` in ColorGradeEffect.swift.
struct GradeUniforms {
    float4 tint;        // rgb multiplier, a = saturation
    float4 fog;         // rgb fog color, a = density per meter
    float4 settings;    // x = vignette, y = highlight keep (night glow), z = projection a, w = projection b
};

static half3 grade(half3 color, float2 uv, constant GradeUniforms &u) {
    half luma = dot(color, half3(0.2126h, 0.7152h, 0.0722h));
    half3 saturated = mix(half3(luma), color, half(u.tint.a));
    half3 tinted = saturated * half3(u.tint.rgb);
    // Keep bright emissive things (lanterns, glowing mushrooms) glowing at night.
    half keep = half(u.settings.y) * smoothstep(0.55h, 1.1h, luma);
    half3 result = mix(tinted, color, keep);

    float2 centered = uv - 0.5;
    float vignette = 1.0 - u.settings.x * smoothstep(0.25, 0.75, dot(centered, centered) * 2.0);
    return result * half(vignette);
}

/// Color grade + distance haze from the depth buffer.
kernel void colorGradeFog(texture2d<half, access::read> source [[texture(0)]],
                          depth2d<float, access::read> depth [[texture(1)]],
                          texture2d<half, access::write> target [[texture(2)]],
                          constant GradeUniforms &u [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    uint2 size = uint2(target.get_width(), target.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    uint2 srcSize = uint2(source.get_width(), source.get_height());
    if (gid.x >= srcSize.x || gid.y >= srcSize.y) return;
    half4 color = source.read(gid);

    // Depth may be a different resolution than color.
    uint2 depthCoord = uint2(float2(gid) * float2(depth.get_width(), depth.get_height()) / float2(size));
    float d = depth.read(depthCoord);
    // Linear view distance from the projection's z terms (works for standard and reverse-Z).
    float distance = u.settings.w / max(d + u.settings.z, 1e-6);
    float haze = (1.0 - exp(-distance * u.fog.a)) * 0.8;
    haze *= 1.0 - smoothstep(350.0, 700.0, distance); // leave the sky dome alone
    color.rgb = mix(color.rgb, half3(u.fog.rgb), half(saturate(haze)));

    float2 uv = (float2(gid) + 0.5) / float2(size);
    target.write(half4(grade(color.rgb, uv, u), color.a), gid);
}

/// Fallback when depth isn't readable as a plain 2D depth texture.
kernel void colorGrade(texture2d<half, access::read> source [[texture(0)]],
                       texture2d<half, access::write> target [[texture(2)]],
                       constant GradeUniforms &u [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]])
{
    uint2 size = uint2(target.get_width(), target.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    uint2 srcSize = uint2(source.get_width(), source.get_height());
    if (gid.x >= srcSize.x || gid.y >= srcSize.y) return;
    half4 color = source.read(gid);
    float2 uv = (float2(gid) + 0.5) / float2(size);
    target.write(half4(grade(color.rgb, uv, u), color.a), gid);
}
