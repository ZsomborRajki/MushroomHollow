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
