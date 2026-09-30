#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Grass blades sit at their own ground height; uv0.y runs from 0 at the root to height / 0.7 m at the tip.
[[visible]]
void grassSway(realitykit::geometry_parameters params)
{
    float3 world = params.geometry().world_position();
    float t = params.uniforms().time();

    // Only the upper part of a blade bends.
    float bend = saturate(params.geometry().uv0().y);
    bend *= bend;

    // Slow rolling gusts across the floor, plus a quick per-blade flutter.
    float gust = sin(t * 0.9 + world.x * 0.08 + world.z * 0.05) * 0.5 + 0.5;
    float flutter = sin(t * 3.1 + world.x * 1.7 + world.z * 1.3);
    float strength = (0.04 + 0.12 * gust) * bend;

    params.geometry().set_model_position_offset(float3(strength * (0.6 + 0.4 * flutter), 0, strength * 0.4 * flutter));
}

[[visible]]
void grassSurface(realitykit::surface_parameters params)
{
    float h = saturate(params.geometry().uv0().y);
    float3 w = params.geometry().world_position();
    float patch = sin(w.x * 0.21) * sin(w.z * 0.17) * 0.5 + 0.5;

    half3 root = half3(0.08, 0.17, 0.05);
    half3 tip = mix(half3(0.36, 0.55, 0.16), half3(0.60, 0.62, 0.22), half(patch));
    params.surface().set_base_color(mix(root, tip, half(h)));
    params.surface().set_roughness(0.85);
}

// Lake water. uv0.x is the depth under this point (0 at the shore, 1 in the deeps): clear and
// greenish in the shallows, dark blue in the middle, with drifting glints and a pale rim at the shore.
[[visible]]
void waterSurface(realitykit::surface_parameters params)
{
    float depth = saturate(params.geometry().uv0().x);
    float3 w = params.geometry().world_position();
    float t = params.uniforms().time();

    half3 shallow = half3(0.36, 0.6, 0.5);
    half3 deep = half3(0.06, 0.2, 0.3);
    half3 color = mix(shallow, deep, half(smoothstep(0.0, 0.7, depth)));

    // Two crossing sets of ripples; their crests catch the light.
    float ripple = sin(w.x * 1.1 + w.z * 0.4 + t * 1.3) * sin(w.z * 0.9 - w.x * 0.3 - t * 1.1);
    float glint = pow(saturate(ripple), 10.0) * 0.35;
    float foam = 1.0 - smoothstep(0.0, 0.08, depth);
    color = mix(color, half3(0.85, 0.9, 0.85), half(foam * 0.5));

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(half3(glint) * half3(0.9, 1.0, 0.95));
    params.surface().set_roughness(0.08);
    params.surface().set_metallic(0);
    params.surface().set_opacity(half(mix(0.45, 0.88, smoothstep(0.0, 0.6, depth))));
}

// Unlit gradient on the inside of the sky sphere: dark leafy canopy overhead, light
// filtering in near the horizon. custom_parameter = (day, dusk, night, 0) weights.
[[visible]]
void skyGradient(realitykit::surface_parameters params)
{
    float3 dir = normalize(params.geometry().model_position());
    float up = dir.y;
    float4 weights = params.uniforms().custom_parameter();
    float total = max(weights.x + weights.y + weights.z, 1e-3);
    weights /= total;

    half3 horizon = half3(0.72, 0.78, 0.55) * half(weights.x)
                  + half3(1.00, 0.58, 0.32) * half(weights.y)
                  + half3(0.08, 0.10, 0.20) * half(weights.z);
    half3 canopy = half3(0.10, 0.22, 0.14) * half(weights.x)
                 + half3(0.22, 0.12, 0.16) * half(weights.y)
                 + half3(0.01, 0.02, 0.05) * half(weights.z);
    half3 below = half3(0.22, 0.28, 0.17) * half(weights.x + weights.y)
                + half3(0.03, 0.04, 0.06) * half(weights.z);

    half3 color = up >= 0
        ? mix(horizon, canopy, half(pow(saturate(up), 0.55)))
        : mix(horizon, below, half(saturate(-up * 4)));

    // Dappled light breaking through the leaves (daytime).
    float dapple = sin(dir.x * 23.0) * sin(dir.z * 19.0) * sin(dir.y * 17.0);
    color += half3(0.25, 0.22, 0.10) * half(saturate(dapple * 3.0 - 2.0) * saturate(up * 2.0) * (weights.x + weights.y * 0.5));

    // Stars peeking through gaps in the canopy (night), gently twinkling.
    float3 cell = floor(dir * 140.0);
    float hash = fract(sin(dot(cell, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    float twinkle = 0.6 + 0.4 * sin(params.uniforms().time() * 3.0 + hash * 40.0);
    float star = step(0.9965, hash) * saturate(up * 3.0) * twinkle * weights.z;
    color += half3(star);

    params.surface().set_emissive_color(color);
}

// Blade swing trail. uv.x runs from the oldest sample (0) to where the blade is now (1),
// uv.y from the hilt (0) to the tip (1). custom_parameter = (r, g, b, strength).
[[visible]]
void swingTrail(realitykit::surface_parameters params)
{
    float2 uv = params.geometry().uv0();
    float4 tint = params.uniforms().custom_parameter();
    float fresh = uv.x;
    float edge = saturate(uv.y);

    // Thin near the hilt, strongest along the edge, fading into the past.
    float alpha = pow(fresh, 1.3) * smoothstep(0.0, 0.35, edge) * (0.6 + 0.4 * edge) * tint.a;
    // A white-hot streak right behind the tip.
    half3 color = mix(half3(tint.rgb), half3(1.0), half(0.7 * pow(edge, 3.0) * fresh));

    params.surface().set_emissive_color(color);
    params.surface().set_opacity(half(saturate(alpha)));
}

// MARK: - Ink style
//
// The hand-drawn look (Rendering/InkStyle.swift), after the "2D café" rooms where everything is
// drawn in bold black marker: matte flat fills in soft cartoon colors, one gentle shadow tone with
// a crisp edge (no gradients, no hatching, no shine), thick contour lines, and a pale paper sky.
// Lines are redrawn about 8 times a second, but only just: a steady marker, not a scribble.
// Every ink material carries the shared 4×1 lighting texture (ToonLighting) in its custom slot:
//   texel 0: rgb = lit multiplier
//   texel 1: rgb = shadow multiplier
//   texel 2: rgb = ink color
//   texel 3: xyz = key light direction
// custom_parameter: y = paint (1 = turn the albedo into a cartoon color, 0 = as given, e.g. the
// painted face), w = opacity (surfaces); x = width (hulls).
// (Static scenery's hand-drawn wobble is baked into its meshes: see InkWobble.)

namespace inkstyle {

/// Integer hashes of the float bits: no `sin`, so they stay cheap and don't fall into visible
/// patterns once the arguments get large (the boil frame keeps counting up).
static uint mixBits(uint n) {
    n ^= n >> 16;
    n *= 0x7feb352du;
    n ^= n >> 15;
    n *= 0x846ca68bu;
    n ^= n >> 16;
    return n;
}

static float toUnit(uint n) {
    return float(n >> 8) * (1.0 / 16777216.0);
}

static float hash11(float x) {
    return toUnit(mixBits(as_type<uint>(x)));
}

static float hash21(float2 p) {
    return toUnit(mixBits(as_type<uint>(p.x) ^ mixBits(as_type<uint>(p.y) + 0x9e3779b9u)));
}

static float hash31(float3 p) {
    uint h = mixBits(as_type<uint>(p.x) ^ mixBits(as_type<uint>(p.y) + 0x9e3779b9u));
    return toUnit(mixBits(h ^ (as_type<uint>(p.z) + 0x7f4a7c15u)));
}

static float noise3(float3 p) {
    float3 i = floor(p), f = fract(p), s = f * f * (3.0 - 2.0 * f);
    float a = mix(hash31(i), hash31(i + float3(1, 0, 0)), s.x);
    float b = mix(hash31(i + float3(0, 1, 0)), hash31(i + float3(1, 1, 0)), s.x);
    float c = mix(hash31(i + float3(0, 0, 1)), hash31(i + float3(1, 0, 1)), s.x);
    float d = mix(hash31(i + float3(0, 1, 1)), hash31(i + float3(1, 1, 1)), s.x);
    return mix(mix(a, b, s.y), mix(c, d, s.y), s.z);
}

/// Lines are redrawn on this beat (keep in step with InkStyle.boilRate).
/// Wrapped, so the noise it seeds never runs out of float precision in a long session.
static float boilFrame(float time) {
    return fmod(floor(time * 8.0), 1024.0);
}

struct Light {
    half3 key;
    half3 shadow;
    half3 ink;
    float3 direction;
};

static Light light(metal::texture2d<half> t) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    half4 a = t.sample(s, float2(0.125, 0.5));
    half4 b = t.sample(s, float2(0.375, 0.5));
    half4 c = t.sample(s, float2(0.625, 0.5));
    half4 d = t.sample(s, float2(0.875, 0.5));
    Light l;
    l.key = a.rgb;
    l.shadow = b.rgb;
    l.ink = c.rgb;
    l.direction = normalize(float3(d.xyz) + float3(0, 1e-3, 0));
    return l;
}

static float3 cameraPosition(float4x4 worldToView) {
    float3x3 r = float3x3(worldToView[0].xyz, worldToView[1].xyz, worldToView[2].xyz);
    return -(transpose(r) * worldToView[3].xyz);
}

/// The palette was picked for a lit, shadowed world, so it runs dark and earthy. Colored in with
/// markers it wants to be lighter and a little brighter: lift the darks, keep the hue, and nudge the
/// saturation up so the lift doesn't turn everything chalky.
static half3 paint(half3 albedo) {
    half3 c = pow(max(albedo, half3(0.0h)), half3(0.72h));
    half luma = dot(c, half3(0.2126h, 0.7152h, 0.0722h));
    c = max(mix(half3(luma), c, 1.18h), half3(0.0h));
    return min(c, half3(1.0h));
}

/// Matte two-tone fill: one flat shadow tone with a crisp, slightly wandering edge, and (with
/// `contour`) ink where the surface turns edge-on to the eye, like a pen tracing its outline.
static half3 shade(thread realitykit::surface_parameters &params, half3 albedo, Light l, float contour = 1.0) {
    float3 n = normalize(params.geometry().normal());
    float3 w = params.geometry().world_position();
    float frame = boilFrame(params.uniforms().time());
    float3 toEye = cameraPosition(params.uniforms().world_to_view()) - w;
    float eyeDistance = length(toEye);
    toEye /= max(eyeDistance, 1e-3);
    float ndl = dot(n, l.direction);
    // The light/shadow line isn't a perfect curve: nudge it with static world-space noise.
    float wobble = (noise3(w * 2.5) - 0.5) * 0.25;
    float lit = smoothstep(-0.02, 0.02, ndl + 0.2 + wobble);
    half3 color = mix(albedo * l.shadow, albedo * l.key, half(lit));

    if (contour > 0.0) {
        // Inner contours (a snout in front of a face): the outline shells draw the silhouettes, so this
        // stays a thin rim. Wider, it floods flat faces seen at a grazing angle (a pool, a tabletop).
        // Its weight wanders a little along the contour, redrawn every boil frame.
        float wander = (noise3(w * 4.0 + frame * 3.7) - 0.5) * 0.04;
        float line = 1.0 - smoothstep(0.07, 0.11, abs(dot(n, toEye)) + wander);
        color = mix(color, l.ink, half(line * contour * (1.0 - smoothstep(30.0, 70.0, eyeDistance))));
    }
    return color;
}

/// A short marker stroke from `a` to `b`, `width` wide: 0...1 ink.
static float segment(float2 p, float2 a, float2 b, float width) {
    float2 pa = p - a, ba = b - a;
    float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return 1.0 - smoothstep(width * 0.6, width, length(pa - ba * t));
}

/// Doodles scattered over the ground, like the stars drawn on the café's sofa: four spiky strokes
/// around a small ring, here and there.
static float doodles(float2 xz, float frame) {
    constexpr float cell = 2.1;
    float2 id = floor(xz / cell);
    float pick = hash21(id);
    if (pick > 0.3) return 0.0;
    float2 base = (id + 0.25 + 0.5 * float2(hash21(id + 7.1), hash21(id + 3.3))) * cell;
    float size = 0.14 + 0.08 * hash21(id + 1.9);
    // Each stroke's ends wiggle a little every boil frame.
    float jiggle = (hash11(frame + pick * 40.0) - 0.5) * 0.06;
    float2 offset = xz - base;
    float r = length(offset);
    float ink = 1.0 - smoothstep(0.012, 0.022, abs(r - size * 0.22));
    for (int i = 0; i < 4; i++) {
        float a = float(i) * 1.5708 + hash21(id + float(i)) * 0.5 + pick * 20.0 + jiggle;
        float2 dir = float2(cos(a), sin(a));
        ink = max(ink, segment(xz, base + dir * size * 0.3, base + dir * size * (1.0 + 0.3 * hash21(id + float(i) * 3.1)), 0.026));
    }
    return ink;
}

} // namespace inkstyle

[[visible]]
void toonSurface(realitykit::surface_parameters params)
{
    inkstyle::Light l = inkstyle::light(params.textures().custom());
    float4 c = params.uniforms().custom_parameter();
    half3 albedo = half3(params.material_constants().base_color_tint());
    if (c.y > 0.0) albedo = inkstyle::paint(albedo);
    params.surface().set_emissive_color(inkstyle::shade(params, albedo, l));
    params.surface().set_opacity(half(c.w));
}

// Painted textures (the face): base color texture times tint, left in the colors it was painted in.
[[visible]]
void toonTextured(realitykit::surface_parameters params)
{
    constexpr sampler bilinear(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    inkstyle::Light l = inkstyle::light(params.textures().custom());
    half3 albedo = params.textures().base_color().sample(bilinear, uv).rgb * half3(params.material_constants().base_color_tint());
    float4 c = params.uniforms().custom_parameter();
    if (c.y > 0.0) albedo = inkstyle::paint(albedo);
    params.surface().set_emissive_color(inkstyle::shade(params, albedo, l));
    params.surface().set_opacity(1.0h);
}

// Batched scenery: one texel per color in the base atlas, glowing colors also in the emissive atlas.
[[visible]]
void toonAtlas(realitykit::surface_parameters params)
{
    constexpr sampler nearest(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 uv = params.geometry().uv0();
    auto textures = params.textures();
    inkstyle::Light l = inkstyle::light(textures.custom());
    half3 albedo = inkstyle::paint(textures.base_color().sample(nearest, uv).rgb);
    half3 glow = textures.emissive_color().sample(nearest, uv).rgb;
    params.surface().set_emissive_color(inkstyle::shade(params, albedo, l) + glow * 0.9h);
    params.surface().set_opacity(1.0h);
}

// The forest floor: the painted ground colored in flat, contact shadows as one crisp shadow tone,
// and on top a repeating PureBDCraft-style pattern: the painted tile for each spot's ground cover
// (InkPainter.groundDetail: grass, dirt, or sand, picked by the surface mask) laid over the world
// at a slant, so its repeats never line up with the roads or the camera into rows.
// Textures: base color = the painting; roughness slot = surface mask (r shadow, g dirt, b sand);
// emissive slot = the detail tile (r grass, g dirt, b sand; levels, see groundDetail).
namespace inkground {

constant float kTile = 2.4;        // meters per repeat of the detail tile
constant float kSlant = 0.41;      // radians the pattern is turned from the world's axes

/// One detail level (see groundDetail) turned into a tone of `albedo`.
static half3 tone(half3 albedo, half level, half3 ink) {
    half light = saturate((level - 0.5h) * 2.4h);
    half dark = saturate((0.5h - level) * 5.0h);
    half inked = saturate((0.2h - level) * 8.0h);
    // Lighter: brighter and a touch warmer, like a highlight marker; darker: deeper and more saturated.
    half3 lit = min(albedo * 1.4h + half3(0.1h, 0.1h, 0.05h), half3(1.0h));
    half3 deep = pow(albedo, half3(1.3h)) * 0.72h;
    half3 color = mix(albedo, lit, light);
    color = mix(color, deep, dark);
    return mix(color, ink, inked);
}

} // namespace inkground

[[visible]]
void inkGround(realitykit::surface_parameters params)
{
    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    constexpr sampler tiled(coord::normalized, address::repeat, filter::linear, mip_filter::linear, max_anisotropy(4));
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    auto textures = params.textures();
    inkstyle::Light l = inkstyle::light(textures.custom());
    // The floor is lifted further than objects, so things stand out against it like drawings on paper.
    half3 painted = inkstyle::paint(textures.base_color().sample(bilinear, uv).rgb);
    half luma = dot(painted, half3(0.2126h, 0.7152h, 0.0722h));
    half3 albedo = mix(max(mix(half3(luma), painted, 1.4h), half3(0.0h)), half3(0.97h, 0.95h, 0.86h), 0.1h);

    float3 w = params.geometry().world_position();
    float4x4 view = params.uniforms().world_to_view();
    float distance = length(inkstyle::cameraPosition(view) - w);
    half4 surface = textures.roughness().sample(bilinear, uv);

    float2 slant = float2(cos(inkground::kSlant), sin(inkground::kSlant));
    float2 tileCoord = float2(dot(w.xz, slant), dot(w.xz, float2(-slant.y, slant.x))) / inkground::kTile;
    half4 detail = textures.emissive_color().sample(tiled, tileCoord);

    // Grass unless the mask says dirt or sand; the edges between are kept fairly crisp.
    half dirt = half(smoothstep(0.35, 0.6, float(surface.g)));
    half sand = half(smoothstep(0.35, 0.6, float(surface.b)));
    half level = mix(mix(detail.r, detail.g, dirt), detail.b, sand);
    // Stronger in some patches than others, so the repeats don't all look alike; gone far off,
    // where it would only shimmer.
    float patches = 0.55 + 0.45 * smoothstep(0.25, 0.65, inkstyle::noise3(float3(w.xz * 0.09, 0.5)));
    level = mix(0.5h, level, half(patches * (1.0 - smoothstep(30.0, 70.0, distance))));

    albedo = inkground::tone(albedo, level, l.ink);
    half3 color = inkstyle::shade(params, albedo, l, 0.0);
    color = mix(color, albedo * l.shadow * 0.86h, half(smoothstep(0.3, 0.36, float(surface.r))));

    float frame = inkstyle::boilFrame(params.uniforms().time());
    float doodles = inkstyle::doodles(w.xz, frame) * (1.0 - smoothstep(16.0, 30.0, distance));
    color = mix(color, l.ink, half(doodles * 0.85));
    params.surface().set_emissive_color(color);
    params.surface().set_opacity(1.0h);
}

[[visible]]
void grassInk(realitykit::surface_parameters params)
{
    float h = saturate(params.geometry().uv0().y);
    float3 w = params.geometry().world_position();
    float patch = sin(w.x * 0.21) * sin(w.z * 0.17) * 0.5 + 0.5;
    inkstyle::Light l = inkstyle::light(params.textures().custom());

    half3 blade = mix(half3(0.3, 0.62, 0.16), half3(0.52, 0.66, 0.18), half(patch));
    // Flat blades: a shadow tone at the root, and an ink tick at the tip, like a pen flick.
    half3 color = h < 0.3 ? blade * l.shadow : blade * l.key;
    color = mix(color, l.ink, half(smoothstep(0.8, 0.86, h)));
    params.surface().set_emissive_color(color);
    params.surface().set_opacity(1.0h);
}

// Lake water in flat pastel bands, with drawn ripple dashes, a pale foam band, and an ink shoreline.
[[visible]]
void waterInk(realitykit::surface_parameters params)
{
    float depth = saturate(params.geometry().uv0().x);
    float3 w = params.geometry().world_position();
    float frame = inkstyle::boilFrame(params.uniforms().time());
    inkstyle::Light l = inkstyle::light(params.textures().custom());

    half3 color = depth < 0.3 ? half3(0.62, 0.86, 0.88) : half3(0.44, 0.72, 0.86);
    // Ripples: short dashes along gently wavy rows, redrawn (not slid) every few boil frames.
    float slow = floor(frame * 0.5);
    float row = w.z * 0.9 + sin(w.x * 0.35 + slow * 0.2) * 0.6;
    float rowID = floor(row);
    float along = fract(w.x * 0.22 + inkstyle::hash11(rowID + slow * 1.7) * 4.0);
    float glint = (1.0 - smoothstep(0.05, 0.1, abs(fract(row) - 0.5))) * step(0.72, along) * step(0.3, depth);
    float foam = 1.0 - smoothstep(0.07, 0.1, depth);
    float shore = 1.0 - smoothstep(0.02, 0.04, depth);
    color = mix(color, half3(0.98, 0.99, 0.97), half(max(glint, foam)));
    color = mix(color, l.ink, half(shore));

    params.surface().set_emissive_color(color * l.key);
    params.surface().set_opacity(half(mix(0.8, 0.95, smoothstep(0.0, 0.5, depth))));
}

// The sky, drawn: pale paper at the horizon rising into the giant tree's leafy canopy, whose edge is
// one scalloped ink line with a few leaf veins drawn inside it; drawn stars at night.
// custom_parameter = (day, dusk, night, 0) weights.
[[visible]]
void inkSky(realitykit::surface_parameters params)
{
    float3 dir = normalize(params.geometry().model_position());
    float up = dir.y;
    float4 weights = params.uniforms().custom_parameter();
    weights /= max(weights.x + weights.y + weights.z, 1e-3);
    half dayW = half(weights.x), duskW = half(weights.y), nightW = half(weights.z);

    half3 paper = half3(0.97, 0.96, 0.9) * dayW + half3(1.0, 0.84, 0.7) * duskW + half3(0.2, 0.24, 0.38) * nightW;
    half3 canopy = half3(0.66, 0.84, 0.6) * dayW + half3(0.84, 0.66, 0.66) * duskW + half3(0.11, 0.15, 0.25) * nightW;
    half3 inner = half3(0.56, 0.76, 0.52) * dayW + half3(0.74, 0.56, 0.6) * duskW + half3(0.08, 0.11, 0.2) * nightW;
    half3 ink = half3(0.008, 0.007, 0.007) * (dayW + duskW) + half3(0.005, 0.006, 0.014) * nightW;

    float azimuth = atan2(dir.x, dir.z);
    // The canopy's edge: a row of leafy bumps, each bump an arc.
    float bumps = 22.0;
    float cellAngle = azimuth / (2.0 * M_PI_F) * bumps;
    float cellID = floor(cellAngle);
    float local = fract(cellAngle) * 2.0 - 1.0;
    float size = 0.06 + 0.04 * inkstyle::hash11(cellID + 0.5);
    float edge = 0.42 + 0.05 * (inkstyle::hash11(cellID + 11.0) - 0.5) - size * sqrt(saturate(1.0 - local * local));
    float d = up - edge;
    half3 color = d < 0.0 ? paper : (d < 0.12 ? canopy : inner);
    float width = 0.006;
    color = mix(color, ink, half(1.0 - smoothstep(width, width * 1.8, abs(d))));
    // A second, fainter line where the canopy deepens.
    color = mix(color, ink, half((1.0 - smoothstep(0.003, 0.006, abs(d - 0.12))) * 0.6));

    // A few leaf veins: short ticks inside the canopy.
    float2 grid = float2(azimuth * 9.0, up * 30.0);
    float2 id = floor(grid);
    if (d > 0.03 && inkstyle::hash21(id) < 0.18) {
        float2 f = fract(grid) - 0.5;
        float tick = 1.0 - smoothstep(0.05, 0.1, abs(f.y - f.x * 0.6));
        color = mix(color, ink, half(tick * step(abs(f.x), 0.3) * 0.7));
    }

    // Drawn stars at night: little four-point crosses below the canopy.
    float2 starGrid = float2(azimuth * 16.0, up * 40.0);
    float2 starID = floor(starGrid);
    float2 sf = fract(starGrid) - 0.5;
    float star = step(inkstyle::hash21(starID + 3.0), 0.06) * step(d, -0.02) * step(0.05, up);
    float cross = max(1.0 - smoothstep(0.03, 0.06, abs(sf.x)) , 1.0 - smoothstep(0.03, 0.06, abs(sf.y)))
                * (1.0 - smoothstep(0.15, 0.25, length(sf)));
    color = mix(color, half3(1.0, 0.97, 0.8), half(star * cross * float(nightW)));

    params.surface().set_emissive_color(color);
}

// Inverted hull: a copy of the part, pushed out along its smoothed normal and drawn back faces
// only, so it shows as an outline. The push swells a touch with noise, redrawn each boil frame.
// custom_parameter.x = width in meters as seen from 8 m away (kept about the same on screen);
// y = 1: scale it by uv0.x (batched scenery gives thin parts thinner lines).
[[visible]]
void inkHullPush(realitykit::geometry_parameters params)
{
    auto uniforms = params.uniforms();
    float3 m = params.geometry().model_position();
    float3 normal = normalize(uniforms.normal_to_world() * params.geometry().normal());
    float distance = length((uniforms.model_to_view() * float4(m, 1)).xyz);
    float frame = inkstyle::boilFrame(uniforms.time());
    // Noise of the model position, so the swelling rides along with the part as it moves.
    float boil = 0.8 + 0.4 * inkstyle::noise3(m * 3.0 + frame * 7.31);
    float4 c = uniforms.custom_parameter();
    float weight = c.y > 0.0 ? params.geometry().uv0().x : 1.0;
    float width = c.x * weight * clamp(distance / 8.0, 0.4, 2.4) * boil;
    params.geometry().set_world_position_offset(normal * width);
}

[[visible]]
void inkHullSurface(realitykit::surface_parameters params)
{
    params.surface().set_emissive_color(inkstyle::light(params.textures().custom()).ink);
    params.surface().set_opacity(1.0h);
}

// Flat blob shadow under an actor: the painted texture's alpha, in a cool shadow tone.
[[visible]]
void inkBlobShadow(realitykit::surface_parameters params)
{
    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    half4 sample = params.textures().base_color().sample(bilinear, uv);
    params.surface().set_emissive_color(sample.rgb);
    params.surface().set_opacity(sample.a * half(params.uniforms().custom_parameter().w));
}
