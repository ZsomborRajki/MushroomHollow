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
    float4 depthInfo;   // x = smallest depth step the format can store (0 for float depth)
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

/// Integer hash of a lattice point: no `sin`, so it's cheap and never bands at large coordinates.
static float hash21(float2 p) {
    uint2 q = uint2(int2(floor(p))) * uint2(1597334673u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334673u;
    return float(n) * (1.0 / 4294967296.0);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = p - i, s = f * f * (3.0 - 2.0 * f);
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

static float depthAt(depth2d<float, access::read> depth, int2 c, int2 limit) {
    return depth.read(uint2(clamp(c, int2(0), limit)));
}

static half lumaAt(texture2d<half, access::read> source, float2 p) {
    float2 limit = float2(source.get_width(), source.get_height()) - 1.0;
    return dot(source.read(uint2(clamp(p, float2(0), limit))).rgb, half3(0.2126h, 0.7152h, 0.0722h));
}

/// How strongly the surface bends across `c` along `step` (depth texels): 0 on anything flat.
///
/// Inverse view distance is `(depth + a) / b`, affine in the stored depth, and on a plane it's affine
/// in screen position too, so the second difference of the raw depth is exactly zero on any flat
/// surface however steeply it's seen. The taps must sit symmetrically on whole texels for that to
/// hold: truncating fractional sample points unevenly turns a plane's slope into fake "edges" all
/// over grazing ground (the smoky, boiling blotches this used to draw on device).
///
/// A silhouette (one side jumps away) scores up to ~8. A crease scores its slope change, damped where
/// the surface is seen edge-on, so terrain facets at grazing angles don't light up.
static float bendAlong(depth2d<float, access::read> depth, int2 c, int2 step, int2 limit, float center,
                       float scale, float quantum) {
    float before = depthAt(depth, c - step, limit);
    float after = depthAt(depth, c + step, limit);
    float second = max(abs(before + after - 2.0 * center) - 2.0 * quantum, 0.0) * scale;
    float slope = max(abs(after - before) - quantum, 0.0) * 0.5 * scale;
    return second / (1.0 + 0.25 * slope);
}

/// How much ink this pixel gets: 0 = paper, 1 = a full line.
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

    half gx = lumaAt(source, q + float2(r, 0)) - lumaAt(source, q - float2(r, 0));
    half gy = lumaAt(source, q + float2(0, r)) - lumaAt(source, q - float2(0, r));
    float colorEdge = smoothstep(0.2, 0.4, float(abs(gx) + abs(gy)));
    // A marker, not a dry brush: the line only rarely runs a little thin.
    float dryBrush = 0.88 + 0.12 * smoothstep(0.25, 0.55, valueNoise(n * 0.11 + frame * 7.7));

    int2 limit = int2(depth.get_width(), depth.get_height()) - 1;
    int2 c = int2(q * toDepth);
    float center = depthAt(depth, c, limit);
    // Some renderers (the Simulator) hand over an empty depth buffer: then the lines come from
    // color edges alone (materials draw their own contours, actors have hull outlines).
    if (center <= 0.0) {
        return colorEdge * dryBrush;
    }
    float wc = center + u.settings.z;        // inverse distance × projection b
    float distance = u.settings.w / max(wc, 1e-9);
    // Thin out into the haze, and never draw on the sky.
    float fade = 1.0 - smoothstep(u.inkShape.y, u.inkShape.z, distance);
    if (fade <= 0.0) return 0.0;

    // Whole-texel taps, `k` texels out (about the brush radius), in four directions.
    int k = max(1, int(round(r * toDepth.x)));
    float perTexel = u.inkShape.x / toDepth.x; // radians per depth texel
    float axis = 1.0 / (abs(wc) * float(k) * perTexel);
    float diagonal = axis * 0.70710678;
    float quantum = u.depthInfo.x;
    float bend = max(max(bendAlong(depth, c, int2(k, 0), limit, center, axis, quantum),
                         bendAlong(depth, c, int2(0, k), limit, center, axis, quantum)),
                     max(bendAlong(depth, c, int2(k, k), limit, center, diagonal, quantum),
                         bendAlong(depth, c, int2(k, -k), limit, center, diagonal, quantum)));
    // Silhouettes and creases, plus the borders between flat colors (spots, stripes, the eyes), like
    // a coloring book. The one soft shadow tone is too close to its lit color to be outlined.
    float edge = max(smoothstep(1.3, 2.6, bend), 0.8 * colorEdge) * dryBrush;
    return edge * fade;
}

/// Paper under everything: faint fibers plus a coarser tooth, re-laid at a slower beat than the lines.
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

    int2 limit = int2(depth.get_width(), depth.get_height()) - 1;
    float d = depthAt(depth, int2(p * toDepth), limit);
    float distance = d > 0.0 ? u.settings.w / max(d + u.settings.z, 1e-9) : 0.0;
    float ink = u.inkColor.a > 0.0 ? inkAmount(p, toDepth, depth, source, u) * u.inkColor.a : 0.0;

    float haze = (1.0 - exp(-distance * u.fog.a)) * 0.8;
    haze *= 1.0 - smoothstep(350.0, 700.0, distance); // leave the sky dome alone
    color.rgb = mix(color.rgb, half3(u.fog.rgb), half(saturate(haze)));

    half3 graded = grade(color.rgb, p / size, u);
    // Lines go on after the grade and the haze, so they stay marker-dark at every hour.
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
