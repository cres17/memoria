#version 100
precision mediump float;

varying vec2 vTexCoord;
uniform sampler2D uInputTex;
uniform sampler2D uLutTex;   // 2D unrolled LUT, width=1089 height=33
uniform float uIntensity;

// LUT dimensions
const float LUT_DIM  = 33.0;
const float LUT_W    = 1089.0; // 33*33
const float LUT_H    = 33.0;

// Sample the unrolled 2D LUT with trilinear interpolation.
// Indexing: slice=b, x=r+g*33, y=slice
vec3 sampleLut(vec3 rgb) {
    // Map to [0, 32] space
    vec3 scaled = clamp(rgb, 0.0, 1.0) * (LUT_DIM - 1.0);

    float r0 = floor(scaled.r);
    float g0 = floor(scaled.g);
    float b0 = floor(scaled.b);
    float r1 = min(r0 + 1.0, LUT_DIM - 1.0);
    float g1 = min(g0 + 1.0, LUT_DIM - 1.0);
    float b1 = min(b0 + 1.0, LUT_DIM - 1.0);

    float rf = scaled.r - r0;
    float gf = scaled.g - g0;
    float bf = scaled.b - b0;

    // Centre-sample texture coordinates: (x+0.5)/W, (y+0.5)/H
    vec2 uv000 = vec2((r0 + g0 * LUT_DIM + 0.5) / LUT_W, (b0 + 0.5) / LUT_H);
    vec2 uv100 = vec2((r1 + g0 * LUT_DIM + 0.5) / LUT_W, (b0 + 0.5) / LUT_H);
    vec2 uv010 = vec2((r0 + g1 * LUT_DIM + 0.5) / LUT_W, (b0 + 0.5) / LUT_H);
    vec2 uv110 = vec2((r1 + g1 * LUT_DIM + 0.5) / LUT_W, (b0 + 0.5) / LUT_H);
    vec2 uv001 = vec2((r0 + g0 * LUT_DIM + 0.5) / LUT_W, (b1 + 0.5) / LUT_H);
    vec2 uv101 = vec2((r1 + g0 * LUT_DIM + 0.5) / LUT_W, (b1 + 0.5) / LUT_H);
    vec2 uv011 = vec2((r0 + g1 * LUT_DIM + 0.5) / LUT_W, (b1 + 0.5) / LUT_H);
    vec2 uv111 = vec2((r1 + g1 * LUT_DIM + 0.5) / LUT_W, (b1 + 0.5) / LUT_H);

    vec3 c000 = texture2D(uLutTex, uv000).rgb;
    vec3 c100 = texture2D(uLutTex, uv100).rgb;
    vec3 c010 = texture2D(uLutTex, uv010).rgb;
    vec3 c110 = texture2D(uLutTex, uv110).rgb;
    vec3 c001 = texture2D(uLutTex, uv001).rgb;
    vec3 c101 = texture2D(uLutTex, uv101).rgb;
    vec3 c011 = texture2D(uLutTex, uv011).rgb;
    vec3 c111 = texture2D(uLutTex, uv111).rgb;

    // Trilinear interpolation
    vec3 c00 = mix(c000, c100, rf);
    vec3 c10 = mix(c010, c110, rf);
    vec3 c01 = mix(c001, c101, rf);
    vec3 c11 = mix(c011, c111, rf);
    vec3 c0  = mix(c00, c10, gf);
    vec3 c1  = mix(c01, c11, gf);
    return mix(c0, c1, bf);
}

void main() {
    vec4 original = texture2D(uInputTex, vTexCoord);
    vec3 filtered = sampleLut(original.rgb);
    // Intensity mix: final = original*(1-intensity) + filtered*intensity
    vec3 result = mix(original.rgb, filtered, uIntensity);
    gl_FragColor = vec4(result, original.a);
}
