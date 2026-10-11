#include <metal_stdlib>
using namespace metal;

// Photographic finish for the demo room. Everything a real camera does to a scene and a
// renderer does not: highlight bloom, a filmic response curve, a warm/cool split, corner
// falloff, sensor grain and a trace of lateral chromatic aberration.

struct PostUniforms {
    float2 texelSize;
    float2 bloomTexelSize;
    float time;
    float bloomThreshold;
    float bloomSoftKnee;
    float bloomStrength;
    float filmicExposure;
    float filmicStrength;
    float contrast;
    float saturation;
    float shadowWarmth;
    float highlightCool;
    float vignetteStrength;
    float vignetteRadius;
    float grainStrength;
    float aberration;
    uint decodeSRGB;
    uint encodeSRGB;
};

constexpr sampler linearSampler(filter::linear, address::clamp_to_edge, coord::normalized);

static inline float luma(float3 c) {
    return dot(c, float3(0.2126f, 0.7152f, 0.0722f));
}

static inline float3 srgbToLinear(float3 c) {
    return select(c / 12.92f, pow((c + 0.055f) / 1.055f, float3(2.4f)), c > 0.04045f);
}

static inline float3 linearToSRGB(float3 c) {
    c = max(c, 0.0f);
    return select(c * 12.92f, 1.055f * pow(c, float3(1.0f / 2.4f)) - 0.055f, c > 0.0031308f);
}

/// RealityKit hands us whatever format the drawable uses, which on some devices is an
/// 8-bit non-sRGB texture whose samples are still gamma encoded. Grading gamma-encoded
/// values pushes the mids around in a way that reads as a colour cast, so the pass always
/// works in linear light and converts on the way in and out only when it has to.
static inline float3 decode(float3 c, constant PostUniforms &u) {
    return u.decodeSRGB != 0 ? srgbToLinear(c) : c;
}

static inline float3 encode(float3 c, constant PostUniforms &u) {
    return u.encodeSRGB != 0 ? linearToSRGB(c) : c;
}

// MARK: - Bright pass

kernel void pfxBrightPass(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant PostUniforms &u [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }

    float2 uv = (float2(gid) + 0.5f) * u.bloomTexelSize;
    // Quarter of a destination texel, so the four bilinear taps tile the block being
    // reduced whatever the downsample ratio is.
    float2 o = u.bloomTexelSize * 0.25f;

    float3 c = src.sample(linearSampler, uv + float2(-o.x, -o.y)).rgb;
    c += src.sample(linearSampler, uv + float2(o.x, -o.y)).rgb;
    c += src.sample(linearSampler, uv + float2(-o.x, o.y)).rgb;
    c += src.sample(linearSampler, uv + float2(o.x, o.y)).rgb;
    c = decode(c * 0.25f, u);

    // Soft knee, so a lamp shade that sits just under the threshold fades in rather than
    // switching on as the camera drifts.
    float l = luma(c);
    float knee = max(u.bloomSoftKnee, 1e-4f);
    float weight = clamp((l - u.bloomThreshold + knee) / (2.0f * knee), 0.0f, 1.0f);
    weight = weight * weight * max(l - u.bloomThreshold, 0.0f) / max(l, 1e-4f);

    dst.write(float4(c * weight, 1.0f), gid);
}

// MARK: - Separable blur

kernel void pfxBlur(texture2d<float, access::sample> src [[texture(0)]],
                    texture2d<float, access::write> dst [[texture(1)]],
                    constant PostUniforms &u [[buffer(0)]],
                    constant float2 &direction [[buffer(1)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }

    float2 uv = (float2(gid) + 0.5f) * u.bloomTexelSize;
    float2 step = direction * u.bloomTexelSize;

    // Five bilinear taps standing in for a nine-tap Gaussian: the sample points sit
    // between texels so the hardware filter supplies the two outer weights for free.
    float3 c = src.sample(linearSampler, uv).rgb * 0.2270270f;
    c += src.sample(linearSampler, uv + step * 1.3846154f).rgb * 0.3162162f;
    c += src.sample(linearSampler, uv - step * 1.3846154f).rgb * 0.3162162f;
    c += src.sample(linearSampler, uv + step * 3.2307692f).rgb * 0.0702703f;
    c += src.sample(linearSampler, uv - step * 3.2307692f).rgb * 0.0702703f;

    dst.write(float4(c, 1.0f), gid);
}

// MARK: - Composite

static inline float3 aces(float3 x) {
    const float a = 2.51f, b = 0.03f, c = 2.43f, d = 0.59f, e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0f, 1.0f);
}

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34f, 456.21f));
    p += dot(p, p + 45.32f);
    return fract(p.x * p.y);
}

kernel void pfxComposite(texture2d<float, access::sample> src [[texture(0)]],
                         texture2d<float, access::sample> bloom [[texture(1)]],
                         texture2d<float, access::write> dst [[texture(2)]],
                         constant PostUniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }

    float2 uv = (float2(gid) + 0.5f) * u.texelSize;
    float2 centred = uv - 0.5f;
    float radius2 = dot(centred, centred);

    float4 centre = src.sample(linearSampler, uv);
    float3 c = decode(centre.rgb, u);

    // Lateral aberration only: the split grows with the square of the distance from the
    // optical axis, so the middle of the frame stays perfectly registered.
    if (u.aberration > 0.0f) {
        float2 offset = centred * radius2 * u.aberration;
        c.r = decode(src.sample(linearSampler, uv + offset).rgb, u).r;
        c.b = decode(src.sample(linearSampler, uv - offset).rgb, u).b;
    }

    c += bloom.sample(linearSampler, uv).rgb * u.bloomStrength;

    // RealityKit already hands us a display-referred image, so the curve is renormalised
    // to keep white at white. What survives is the part we actually want — a toe under the
    // mid-tones and a shoulder over them — instead of a second exposure change on top of
    // the renderer's own.
    float3 toned = aces(c * u.filmicExposure) / aces(float3(u.filmicExposure));
    c = mix(c, toned, u.filmicStrength);

    c = clamp((c - 0.5f) * u.contrast + 0.5f, 0.0f, 1.0f);

    // The reference footage is warm tungsten interior against cool daylight through the
    // glass. Splitting the toe warm and the shoulder cool is what reproduces that read.
    float l = luma(c);
    float shadowMask = 1.0f - smoothstep(0.0f, 0.42f, l);
    float highlightMask = smoothstep(0.55f, 1.0f, l);
    c += shadowMask * u.shadowWarmth * float3(1.0f, 0.44f, -0.14f);
    c += highlightMask * u.highlightCool * float3(-0.30f, 0.0f, 0.50f);

    c = mix(float3(luma(c)), c, u.saturation);

    float vignette = 1.0f - u.vignetteStrength *
        smoothstep(u.vignetteRadius, 0.85f, length(centred * float2(1.0f, 0.62f)) * 1.6f);
    c *= vignette;

    // Grain is applied after the curve, in display space, because that is where a sensor
    // puts it — grading it would make the noise track exposure and stop reading as grain.
    float grain = hash21(float2(gid) + fract(u.time) * float2(37.0f, 17.0f)) - 0.5f;
    c += grain * u.grainStrength * (0.35f + 0.65f * (1.0f - abs(l * 2.0f - 1.0f)));

    dst.write(float4(encode(max(c, 0.0f), u), centre.a), gid);
}
