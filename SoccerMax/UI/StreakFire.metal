// The streak fire (notes/19 "Stats tab" ? STREAK FIRE): a raymarched 3D flame volume. Noise scrolls up through a
// teardrop so tongues lick off the top; temperature drives the colour (deep orange rim ? gold ? creme-white core).
// Swift drives: heat (how much streak is left), flare (a tap), lean (drag), spin (twist the volume round), dead.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash3(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static float noise3(float3 x) {
    float3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(i + float3(0, 0, 0)), hash3(i + float3(1, 0, 0)), f.x),
                   mix(hash3(i + float3(0, 1, 0)), hash3(i + float3(1, 1, 0)), f.x), f.y),
               mix(mix(hash3(i + float3(0, 0, 1)), hash3(i + float3(1, 0, 1)), f.x),
                   mix(hash3(i + float3(0, 1, 1)), hash3(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

static float fbm(float3 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * noise3(p);
        p = p * 2.07 + float3(1.7, 9.2, 3.1);
        a *= 0.5;
    }
    return s;
}

/// Fire colour by temperature 0?1: ember red ? orange ? gold ? creme-white.
static float3 ramp(float t) {
    t = clamp(t, 0.0, 1.0);
    float3 c0 = float3(0.45, 0.04, 0.0);
    float3 c1 = float3(1.0, 0.30, 0.02);
    float3 c2 = float3(1.0, 0.68, 0.12);
    float3 c3 = float3(1.0, 0.95, 0.78);
    if (t < 0.35) return mix(c0, c1, t / 0.35);
    if (t < 0.7) return mix(c1, c2, (t - 0.35) / 0.35);
    return mix(c2, c3, (t - 0.7) / 0.3);
}

/// Density + temperature of the flame at p.
static float2 flame(float3 p, float time, float scale, float lean, float spin, float dead) {
    float H = 1.42 * scale;
    // lean the tip (drag), bend more the higher you go
    p.x -= lean * p.y * p.y * 0.42;
    // twist round the axis (drag spin + a slow live twist)
    float a = spin + p.y * (0.9 + 0.4 * sin(time * 0.6));
    float ca = cos(a), sa = sin(a);
    p.xz = float2(ca * p.x - sa * p.z, sa * p.x + ca * p.z);

    float h = p.y / H;
    if (h < -0.2 || h > 1.5) return float2(0);
    float hh = clamp(h, 0.0, 1.0);

    // fire rises: sample noise scrolling up, stretched tall
    float speed = dead > 0.5 ? 0.7 : 2.4;
    float3 q = float3(p.x * 3.2, p.y * 2.3 - time * speed, p.z * 3.2);
    float n = fbm(q + float3(0, 0, time * 0.3));
    float n2 = noise3(q * 2.3 + float3(0, -time * 1.3, 0));

    // teardrop: a round bulb low down, tapering to a point
    float R = scale * 0.42 * pow(1.0 - hh, 0.75) * smoothstep(-0.18, 0.2, h) * (dead > 0.5 ? 0.6 : 1.0);
    float r = length(p.xz);
    float disp = (n - 0.5) * (0.3 + 0.75 * hh) * scale + (n2 - 0.5) * 0.12 * scale;
    float d = r + disp - R;

    float dens = smoothstep(0.025 * scale, -0.06 * scale, d);
    // tongues: the top breaks up where the noise is thin
    dens *= smoothstep(1.2, 0.6, h + (0.55 - n) * 1.5);
    dens *= smoothstep(-0.2, -0.02, h);

    float core = 1.0 - clamp(r / max(R, 0.001), 0.0, 1.0);
    float temp = pow(dens, 0.6) * (1.12 - 0.72 * hh) * (0.5 + 0.95 * core) + 0.1 * n2;
    return float2(dens, temp);
}

[[ stitchable ]] half4 streakFire(float2 pos, half4 color, float2 size, float time, float heat, float flare,
                                   float lean, float spin, float dead) {
    // screen ? camera ray; base of the flame sits low in the frame
    float2 uv = (pos - size * 0.5) / size.y;
    uv.y = -uv.y;
    float3 ro = float3(0.0, 0.74, -3.0);
    float3 rd = normalize(float3(uv.x, uv.y, 1.5));

    float scale = dead > 0.5 ? 0.55 : (0.55 + 0.45 * heat) * (1.0 + 0.6 * flare);
    float3 col = float3(0);
    float alpha = 0.0;
    float dt = 0.05;
    float t = 2.15 + dt * hash3(float3(pos, time));     // jitter = no banding
    for (int i = 0; i < 34; i++) {
        float3 p = ro + rd * t;
        float2 f = flame(p, time, scale, lean, spin, dead);
        if (f.x > 0.002) {
            float w = f.x * dt * 7.0;
            float3 e;
            if (dead > 0.5) {
                e = float3(0.42, 0.40, 0.38) * (0.4 + f.y) * 0.5;          // cold grey smoke
                w *= 0.6;
            } else {
                e = ramp(f.y * (1.0 + 0.35 * flare)) * (1.4 + 1.2 * flare);
            }
            col += (1.0 - alpha) * e * w;
            alpha += (1.0 - alpha) * w * 0.85;
            if (alpha > 0.985) break;
        }
        t += dt;
    }
    // a soft hot glow round the flame
    if (dead < 0.5) {
        float2 g = float2(uv.x, uv.y + 0.12) / float2(0.5, 0.75);
        float glow = exp(-dot(g, g) * 3.2) * (0.18 + 0.25 * flare) * (0.5 + 0.5 * heat);
        col += float3(1.0, 0.45, 0.08) * glow * (1.0 - alpha);
        alpha = max(alpha, glow * 0.8);
    }
    // fade everything to nothing before the square's edge, so the frame never shows as a line
    float edge = smoothstep(0.5, 0.36, abs(uv.x)) * smoothstep(0.5, 0.38, abs(uv.y));
    col *= edge;
    alpha *= edge;
    col = col / (1.0 + col * 0.35);        // gentle tone map so the core stays white, not clipped
    alpha = clamp(max(alpha, max(col.r, max(col.g, col.b)) * 0.9), 0.0, 1.0);
    return half4(half3(min(col, float3(alpha))), half(alpha));
}
