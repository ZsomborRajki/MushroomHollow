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
// The hand-drawn look (Rendering/InkStyle.swift): unlit two-tone fills with cool shadows, hatching
// in the shade, cartoon shine, inverted-hull outlines, all boiling (redrawn) about 8 times a second.
// Every ink material carries the shared 4×1 lighting texture (ToonLighting) in its custom slot:
//   texel 0: rgb = lit multiplier
//   texel 1: rgb = shadow multiplier, a = hatching strength
//   texel 2: rgb = ink color (day ink, night chalk)
//   texel 3: xyz = key light direction, a = rim strength
// custom_parameter: x = wobble (m), y = shine, z = hatching, w = opacity (surfaces); x = width (hulls).

namespace inkstyle {

static float hash11(float x) {
    return fract(sin(x * 91.3458) * 47453.5453);
}

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float hash31(float3 p) {
    return fract(sin(dot(p, float3(12.9898, 78.233, 37.719))) * 43758.5453);
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
static float boilFrame(float time) {
    return floor(time * 8.0);
}

struct Light {
    half3 key;
    half3 shadow;
    half hatch;
    half3 ink;
    float3 direction;
    half rim;
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
    l.hatch = b.a;
    l.ink = c.rgb;
    l.direction = normalize(float3(d.xyz) + float3(0, 1e-3, 0));
    l.rim = d.a;
    return l;
}

static float3 cameraPosition(float4x4 worldToView) {
    float3x3 r = float3x3(worldToView[0].xyz, worldToView[1].xyz, worldToView[2].xyz);
    return -(transpose(r) * worldToView[3].xyz);
}

/// Short hatch strokes laid in screen space (units of view-angle tangent, so spacing is the same
/// on every screen) at `angle`, jittered per row and redrawn every boil frame. 0...1 ink.
static float hatch(float3 world, float4x4 worldToView, float frame, float angle) {
    float4 v = worldToView * float4(world, 1);
    float2 s = v.xy / max(-v.z, 0.05);
    float2 along = float2(cos(angle), sin(angle));
    float across = dot(s, float2(-along.y, along.x)) * 150.0;
    float row = floor(across);
    float d = abs(fract(across + (hash11(row * 1.37 + frame * 5.1) - 0.5) * 0.3) - 0.5);
    float stroke = 1.0 - smoothstep(0.08, 0.22, d);
    // Dashes of uneven length, each row starting somewhere else.
    float dash = fract(dot(s, along) * 20.0 + hash11(row + frame * 2.3));
    return stroke * step(0.22, dash);
}

/// Two-tone toon shading with a wobbly terminator, hatching in the shade, optional shine, and
/// (with `contour`) ink where the surface turns edge-on to the eye, like a pen tracing its outline.
static half3 shade(thread realitykit::surface_parameters &params, half3 albedo, Light l, float4 c, float contour = 1.0) {
    float3 n = normalize(params.geometry().normal());
    float3 w = params.geometry().world_position();
    float frame = boilFrame(params.uniforms().time());
    float3 toEye = cameraPosition(params.uniforms().world_to_view()) - w;
    float eyeDistance = length(toEye);
    toEye /= max(eyeDistance, 1e-3);
    float ndl = dot(n, l.direction);
    // The light/shadow line isn't a perfect curve: nudge it with static world-space noise.
    float wobble = (noise3(w * 3.0) - 0.5) * 0.3;
    float lit = smoothstep(-0.03, 0.03, ndl + 0.12 + wobble);
    half3 color = mix(albedo * l.shadow, albedo * l.key, half(lit));

    if (c.z > 0.0 && l.hatch > 0.0h) {
        float4x4 view = params.uniforms().world_to_view();
        float amount = (1.0 - lit) * c.z * float(l.hatch);
        float deep = smoothstep(-0.25, -0.6, ndl + wobble) * amount;
        float strokes = hatch(w, view, frame, 0.95) * amount + hatch(w, view, frame, -0.6) * deep;
        color = mix(color, l.ink, half(saturate(strokes) * 0.32));
    }
    if (c.y > 0.0) {
        // Cartoon shine: a hard-edged highlight blob and a thin rim on the lit side.
        float3 halfway = normalize(toEye + l.direction);
        float blob = smoothstep(0.955, 0.968, dot(n, halfway) + wobble * 0.04);
        float rim = smoothstep(0.66, 0.72, 1.0 - saturate(dot(n, toEye))) * lit * float(l.rim);
        color = mix(color, half3(1.0h, 0.98h, 0.92h) * l.key, half(blob * 0.8 * c.y));
        color += albedo * l.key * half(rim * 0.3 * c.y);
    }
    if (contour > 0.0) {
        // The line's weight wanders along the contour and is redrawn every boil frame.
        float wobble = (noise3(w * 5.0 + frame * 3.7) - 0.5) * 0.14;
        float line = 1.0 - smoothstep(0.14, 0.22, abs(dot(n, toEye)) + wobble);
        color = mix(color, l.ink, half(line * contour * (1.0 - smoothstep(35.0, 80.0, eyeDistance))));
    }
    return color;
}

/// Doodled asterisk "tufts" scattered over the ground (like the stars on the café sofa).
static float tufts(float2 xz, float frame) {
    constexpr float cell = 1.7;
    float2 id = floor(xz / cell);
    float pick = hash21(id);
    if (pick > 0.4) return 0.0;
    float2 base = (id + 0.3 + 0.4 * float2(hash21(id + 7.1), hash21(id + 3.3))) * cell;
    float size = 0.12 + 0.1 * hash21(id + 1.9);
    float ink = 0.0;
    for (int i = 0; i < 3; i++) {
        // Each stroke's ends wiggle a little every boil frame.
        float a = float(i) * 1.047 + hash21(id + float(i)) * 0.5 + (hash11(frame + float(i) * 3.1 + pick * 40.0) - 0.5) * 0.12;
        float2 dir = float2(cos(a), sin(a)) * size;
        float2 pa = xz - (base - dir), ba = 2.0 * dir;
        float t = saturate(dot(pa, ba) / dot(ba, ba));
        float d = length(pa - ba * t);
        ink = max(ink, 1.0 - smoothstep(0.012, 0.03, d));
    }
    return ink;
}

} // namespace inkstyle

[[visible]]
void toonSurface(realitykit::surface_parameters params)
{
    inkstyle::Light l = inkstyle::light(params.textures().custom());
    half3 albedo = half3(params.material_constants().base_color_tint());
    float4 c = params.uniforms().custom_parameter();
    params.surface().set_emissive_color(inkstyle::shade(params, albedo, l, c));
    params.surface().set_opacity(half(c.w));
}

// Painted textures (the face): base color texture times tint, toon shaded.
[[visible]]
void toonTextured(realitykit::surface_parameters params)
{
    constexpr sampler bilinear(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    inkstyle::Light l = inkstyle::light(params.textures().custom());
    half3 albedo = params.textures().base_color().sample(bilinear, uv).rgb * half3(params.material_constants().base_color_tint());
    float4 c = params.uniforms().custom_parameter();
    params.surface().set_emissive_color(inkstyle::shade(params, albedo, l, c));
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
    half3 albedo = textures.base_color().sample(nearest, uv).rgb;
    half3 glow = textures.emissive_color().sample(nearest, uv).rgb;
    float4 c = params.uniforms().custom_parameter();
    params.surface().set_emissive_color(inkstyle::shade(params, albedo, l, c) + glow * 1.2h);
    params.surface().set_opacity(1.0h);
}

// Nothing drawn by hand is perfectly round: nudge vertices by smooth noise of their model position
// (the same for every vertex at one spot, so hard edges don't split). custom_parameter.x = meters.
[[visible]]
void toonWobble(realitykit::geometry_parameters params)
{
    float amount = params.uniforms().custom_parameter().x;
    if (amount <= 0.0) return;
    float3 m = params.geometry().model_position() * (0.08 / amount);
    float3 offset = float3(inkstyle::noise3(m), inkstyle::noise3(m + 17.3), inkstyle::noise3(m + 41.7)) - 0.5;
    params.geometry().set_world_position_offset(offset * 2.0 * amount);
}

// The forest floor: painted texture, contact shadows (roughness slot, 1 = shadow) filled with
// hatching, and doodled tufts near the camera.
[[visible]]
void inkGround(realitykit::surface_parameters params)
{
    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    auto textures = params.textures();
    inkstyle::Light l = inkstyle::light(textures.custom());
    half3 albedo = textures.base_color().sample(bilinear, uv).rgb;
    float shadow = float(textures.roughness().sample(bilinear, uv).r);
    float4 c = params.uniforms().custom_parameter();
    half3 color = inkstyle::shade(params, albedo, l, c, 0.0);

    float3 w = params.geometry().world_position();
    float4x4 view = params.uniforms().world_to_view();
    float frame = inkstyle::boilFrame(params.uniforms().time());
    float hatching = inkstyle::hatch(w, view, frame, 0.95) * smoothstep(0.12, 0.45, shadow)
                   + inkstyle::hatch(w, view, frame, -0.6) * smoothstep(0.45, 0.8, shadow);
    color = mix(color, albedo * l.shadow * 0.55h, half(saturate(hatching) * 0.6 * float(l.hatch)));

    float distance = length(inkstyle::cameraPosition(view) - w);
    float doodles = inkstyle::tufts(w.xz, frame) * (1.0 - smoothstep(14.0, 26.0, distance));
    color = mix(color, albedo * 0.38h, half(doodles * 0.85));
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

    half3 root = half3(0.2, 0.33, 0.12);
    half3 tip = mix(half3(0.42, 0.62, 0.2), half3(0.66, 0.68, 0.26), half(patch));
    // Flat two-tone blades: the lower half in shadow, a darker ink tick at the very tip.
    half3 color = h < 0.45 ? root * l.shadow : tip * l.key;
    color = mix(color, root * 0.5h, half(smoothstep(0.86, 0.92, h)));
    params.surface().set_emissive_color(color);
    params.surface().set_opacity(1.0h);
}

// Lake water in flat bands, with scribbled glints and a pale shore line.
[[visible]]
void waterInk(realitykit::surface_parameters params)
{
    float depth = saturate(params.geometry().uv0().x);
    float3 w = params.geometry().world_position();
    float t = params.uniforms().time();
    float frame = inkstyle::boilFrame(t);
    inkstyle::Light l = inkstyle::light(params.textures().custom());

    half3 color = depth < 0.18 ? half3(0.5, 0.74, 0.64) : (depth < 0.5 ? half3(0.3, 0.55, 0.6) : half3(0.16, 0.34, 0.46));
    float ripple = sin(w.x * 1.1 + w.z * 0.4 + frame * 0.35) * sin(w.z * 0.9 - w.x * 0.3 - frame * 0.3);
    float glint = step(0.82, ripple) * step(0.35, depth);
    float shore = 1.0 - smoothstep(0.03, 0.06, depth);
    color = mix(color, half3(0.95, 0.97, 0.92), half(max(glint * 0.8, shore * 0.85)));

    params.surface().set_emissive_color(color * l.key);
    params.surface().set_opacity(half(mix(0.55, 0.92, smoothstep(0.0, 0.6, depth))));
}

// Inverted hull: a copy of the part, pushed out along the (world) normal and drawn back faces
// only, so it shows as an outline. The push swells and thins with noise, redrawn each boil frame.
// custom_parameter.x = width in meters as seen from 8 m away (kept about the same on screen).
[[visible]]
void inkHullPush(realitykit::geometry_parameters params)
{
    auto uniforms = params.uniforms();
    float3 m = params.geometry().model_position();
    float3 normal = normalize(uniforms.normal_to_world() * params.geometry().normal());
    float distance = length((uniforms.model_to_view() * float4(m, 1)).xyz);
    float frame = inkstyle::boilFrame(uniforms.time());
    // Noise of the model position, so the swelling rides along with the part as it moves.
    float boil = 0.6 + 0.8 * inkstyle::noise3(m * 3.0 + frame * 7.31);
    float width = uniforms.custom_parameter().x * clamp(distance / 8.0, 0.4, 2.6) * boil;
    params.geometry().set_world_position_offset(normal * width);
}

[[visible]]
void inkHullSurface(realitykit::surface_parameters params)
{
    params.surface().set_emissive_color(inkstyle::light(params.textures().custom()).ink);
    params.surface().set_opacity(1.0h);
}

// Hatched blob shadow under an actor: the painted texture's alpha, in a cool dark ink.
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
