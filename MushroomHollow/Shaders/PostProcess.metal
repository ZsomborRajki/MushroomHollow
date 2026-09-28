#include <metal_stdlib>
using namespace metal;

// Must match `GradeUniforms` in ColorGradeEffect.swift.
struct GradeUniforms {
    float4 tint;        // rgb multiplier, a = saturation
    float4 fog;         // rgb fog color, a = density per meter
    float4 settings;    // x = vignette, y = highlight keep (night glow), z = projection a, w = projection b
    float4 ink;         // x = boil frame, y = line radius (px), z = boil amount (px), w = paper grain strength
    float4 inkColor;    // rgb = line color, a = line strength (0 = no ink: the classic style)
    float4 inkShape;    // x = radians per pixel, y/z = lines fade out between these distances (m), w = pixels per point
};

struct FullscreenVertex {
    float4 position [[position]];
};

/// One triangle covering the screen; the fragment functions read pixels by position.
vertex FullscreenVertex fullscreenVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    FullscreenVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - Noise

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p), s = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), s.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), s.x), s.y);
}

// MARK: - Grade

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

// MARK: - Ink

/// Linear view distance at a pixel (depth may be a different resolution than color).
static float viewDistance(depth2d<float, access::read> depth, float2 p, float2 toDepth, constant GradeUniforms &u) {
    float2 limit = float2(depth.get_width(), depth.get_height()) - 1.0;
    uint2 c = uint2(clamp(p * toDepth, float2(0), limit));
    // From the projection's z terms (works for standard and reverse-Z).
    return u.settings.w / max(depth.read(c) + u.settings.z, 1e-6);
}

static half lumaAt(texture2d<half, access::read> source, float2 p) {
    float2 limit = float2(source.get_width(), source.get_height()) - 1.0;
    return dot(source.read(uint2(clamp(p, float2(0), limit))).rgb, half3(0.2126h, 0.7152h, 0.0722h));
}

/// How much ink this pixel gets: 0 = paper, 1 = a full line.
///
/// Edges come from the second difference of *inverse* depth, which is exactly zero on any flat
/// surface (however steeply it's seen) and jumps at silhouettes. Divided by the local inverse depth
/// and the pixel angle it reads as "how much the surface slope changes here", so creases get lines
/// at the same angle near and far. A little luminance edge on top picks up painted detail.
static float inkAmount(float2 p, float2 toDepth, depth2d<float, access::read> depth,
                       texture2d<half, access::read> source, constant GradeUniforms &u)
{
    float frame = u.ink.x;
    float2 n = p / u.inkShape.w; // in points, so the pattern is the same on every screen

    // Boil: the sample point wanders a little, re-seeded every boil frame, so lines get redrawn
    // (jitter on twos) rather than slide.
    float2 wobble = float2(valueNoise(n * 0.03 + frame * 17.13), valueNoise(n * 0.03 + frame * 31.71 + 5.0)) - 0.5;
    float2 q = p + wobble * 2.0 * u.ink.z;
    // Brush: the kernel radius swells and thins along a stroke, like a marker pressed harder.
    float r = u.ink.y * (0.55 + 0.9 * valueNoise(n * 0.02 + float2(frame * 0.61, 3.7)));

    float2 dx = float2(r, 0), dy = float2(0, r), d1 = float2(r, r) * 0.7071, d2 = float2(r, -r) * 0.7071;
    half gx = lumaAt(source, q + dx) - lumaAt(source, q - dx);
    half gy = lumaAt(source, q + dy) - lumaAt(source, q - dy);
    float colorEdge = smoothstep(0.22, 0.45, float(abs(gx) + abs(gy)));
    float dryBrush = 0.72 + 0.28 * smoothstep(0.25, 0.55, valueNoise(n * 0.11 + frame * 7.7));

    // Some renderers (the Simulator) hand over an empty depth buffer: then the lines come from
    // color edges alone (materials draw their own contours, actors have hull outlines).
    float2 limit = float2(depth.get_width(), depth.get_height()) - 1.0;
    if (depth.read(uint2(clamp(q * toDepth, float2(0), limit))) <= 0.0) {
        return 0.8 * colorEdge * dryBrush;
    }

    float wc = 1.0 / viewDistance(depth, q, toDepth, u);
    float h = abs(1.0 / viewDistance(depth, q - dx, toDepth, u) + 1.0 / viewDistance(depth, q + dx, toDepth, u) - 2.0 * wc);
    float v = abs(1.0 / viewDistance(depth, q - dy, toDepth, u) + 1.0 / viewDistance(depth, q + dy, toDepth, u) - 2.0 * wc);
    float a = abs(1.0 / viewDistance(depth, q - d1, toDepth, u) + 1.0 / viewDistance(depth, q + d1, toDepth, u) - 2.0 * wc);
    float b = abs(1.0 / viewDistance(depth, q - d2, toDepth, u) + 1.0 / viewDistance(depth, q + d2, toDepth, u) - 2.0 * wc);
    float bend = max(max(h, v), max(a, b)) / (wc * r * u.inkShape.x);
    // Silhouettes and creases, plus faint painted detail (spots, stripes, the eyes); kept faint so
    // shading bands don't all get outlined.
    float edge = max(smoothstep(1.3, 2.6, bend), 0.55 * colorEdge) * dryBrush;

    // Thin out into the haze, and never draw on the sky.
    float distance = 1.0 / wc;
    return edge * (1.0 - smoothstep(u.inkShape.y, u.inkShape.z, distance));
}

/// Paper under everything: faint fibers plus a coarser tooth, boiling at a slower rate.
static half paperGrain(float2 p, constant GradeUniforms &u) {
    float2 n = p / u.inkShape.w;
    float slow = floor(u.ink.x * 0.25);
    float fiber = valueNoise(float2(n.x * 0.9, n.y * 0.14) + slow * 3.1);
    float tooth = valueNoise(n * 0.55 + slow * 1.7);
    return half(1.0 - u.ink.w * ((fiber * 0.5 + tooth * 0.5) - 0.5) * 2.0);
}

// MARK: - Passes

/// Ink lines, color grade, distance haze, and paper, from the color and depth buffers.
fragment half4 gradeInkFragment(FullscreenVertex in [[stage_in]],
                                texture2d<half, access::read> source [[texture(0)]],
                                depth2d<float, access::read> depth [[texture(1)]],
                                constant GradeUniforms &u [[buffer(0)]])
{
    float2 size = float2(source.get_width(), source.get_height());
    float2 p = min(in.position.xy, size - 0.5);
    half4 color = source.read(uint2(p));
    float2 toDepth = float2(depth.get_width(), depth.get_height()) / size;

    float distance = viewDistance(depth, p, toDepth, u);
    float ink = u.inkColor.a > 0.0 ? inkAmount(p, toDepth, depth, source, u) * u.inkColor.a : 0.0;

    float haze = (1.0 - exp(-distance * u.fog.a)) * 0.8;
    haze *= 1.0 - smoothstep(350.0, 700.0, distance); // leave the sky dome alone
    color.rgb = mix(color.rgb, half3(u.fog.rgb), half(saturate(haze)));

    half3 graded = grade(color.rgb, p / size, u);
    // Lines go on after the grade, so they stay ink-dark by day and chalk-pale by night.
    graded = mix(graded, half3(u.inkColor.rgb), half(saturate(ink)));
    if (u.ink.w > 0.0) graded *= paperGrain(p, u);
    return half4(graded, color.a);
}

/// Fallback when depth isn't readable as a plain 2D depth texture: grade (and paper) only.
fragment half4 gradeFragment(FullscreenVertex in [[stage_in]],
                             texture2d<half, access::read> source [[texture(0)]],
                             constant GradeUniforms &u [[buffer(0)]])
{
    float2 size = float2(source.get_width(), source.get_height());
    float2 p = min(in.position.xy, size - 0.5);
    half4 color = source.read(uint2(p));
    half3 graded = grade(color.rgb, p / size, u);
    if (u.ink.w > 0.0) graded *= paperGrain(p, u);
    return half4(graded, color.a);
}
