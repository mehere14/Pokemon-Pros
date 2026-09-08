#include <metal_stdlib>
using namespace metal;

// Pointer-driven optical response combined with reusable finish textures.
float finishHash(float2 p) {
    return fract(sin(dot(p, float2(91.73, 217.19))) * 43758.31);
}
float3 finishSpectrum(float phase) {
    return 0.5 + 0.5 * cos(6.2831853 * (phase + float3(0.0, 0.33, 0.67)));
}
float finishBand(float phase, float sharpness) {
    return pow(0.5 + 0.5 * sin(phase * 6.2831853), sharpness);
}
[[ stitchable ]] half4 cardFinish(
    float2 position, half4 input, float2 size, float2 light, float familyValue, float enabled
) {
    if (enabled < 0.5 || input.a < 0.001h) return input;
    float2 uv = position / max(size, float2(1.0));
    int family = int(familyValue);
    float2 tilt = light - 0.5;
    float3 base = float3(input.rgb) / float(input.a);
    float2 d = uv - light;
    float glare = exp(-dot(d * float2(1.0, 1.4), d * float2(1.0, 1.4)) * 28.0);
    float art = smoothstep(0.08, 0.087, uv.x) * (1.0 - smoothstep(0.913, 0.92, uv.x))
              * smoothstep(0.095, 0.102, uv.y) * (1.0 - smoothstep(0.52, 0.527, uv.y));
    float mask = 1.0;
    if (family == 1) mask = 1.0 - art;
    if (family == 2 || family == 3) mask = art;
    if (family == 4) {
        float2 q = (uv - float2(0.5, 0.32)) / float2(0.48, 0.30);
        mask = 1.0 - smoothstep(0.85, 1.0, length(q));
    }
    if (family >= 6) mask *= 1.0 - 0.5 * smoothstep(0.60, 0.92, uv.y);
    float2 fineMotion = tilt * float2(0.34, -0.27);
    float2 reverseMotion = tilt * float2(-0.24, 0.31);
    float grainMap = finishHash(floor((uv + fineMotion) * float2(620, 860)));
    float glitterMap = pow(finishHash(floor((uv + reverseMotion) * float2(95, 132))), 5.0);
    float etchedMap = 0.5 + 0.5 * sin((uv.x * 84.0 + uv.y * 31.0 + fineMotion.x * 22.0) * 6.2831853);
    float geometricMap = finishBand((uv.x + uv.y) * 18.0 + reverseMotion.y * 4.0, 5.0);
    float vmaxMap = 0.5 + 0.5 * sin(uv.x * 21.0 + sin(uv.y * 17.0 + fineMotion.y * 9.0));
    float cosmosMap = glitterMap;
    float trainerMap = finishBand((uv.x - uv.y) * 13.0 + fineMotion.x * 3.0, 4.0);
    float grain = grainMap;
    float angle = tilt.x * 1.9 + tilt.y * 1.3;
    float spectralPhase = uv.y * 1.8 + uv.x * 0.4 + angle;
    float foil = 0.0;
    float3 tint = finishSpectrum(spectralPhase);
    float sparkle = 0.0;
    // Broad optical lobes travel opposite to the fine diffraction layer.
    float lobe = finishBand(uv.x * 1.4 + uv.y * 0.7 - angle, 6.0);
    float etched = finishBand(uv.x * 86.0 + sin(uv.y * 29.0) * 1.8, 12.0);
    float2 sweepAxis = normalize(float2(0.78 + tilt.y * 0.25, -0.62 + tilt.x * 0.25));
    float sweepDistance = dot(uv - light, sweepAxis);
    float sweep = exp(-sweepDistance * sweepDistance * 72.0);
    switch (family) {
        case 0: break;
        case 1:
            foil = 0.13 * lobe + 0.20 * etchedMap * finishBand((uv.x + uv.y) * 4.0 + angle, 6.0);
            tint = mix(float3(0.65, 0.8, 0.9), tint, 0.45); break;
        case 2:
            foil = (0.08 + 0.34 * finishBand(uv.x * 6.0 - angle, 14.0))
                 * (0.30 + 0.70 * etchedMap); break;
        case 3: {
            foil = 0.10 * lobe + 0.28 * cosmosMap * finishBand(cosmosMap * 4.0 - angle, 5.0);
            for (int layer = 0; layer < 3; ++layer) {
                float scale = 24.0 + float(layer) * 17.0;
                float2 p = uv * float2(scale, scale * 1.4) + tilt * float(layer + 1) * 0.7;
                float2 cell = floor(p);
                float seed = finishHash(cell + float(layer) * 19.0);
                float dotShape = exp(-dot(fract(p) - 0.5, fract(p) - 0.5) * (60.0 + seed * 140.0));
                sparkle += dotShape * step(0.88, seed) * finishBand(seed * 5.0 + angle, 3.0);
            }
            break;
        }
        case 4:
            foil = 0.13 * lobe + 0.14 * etchedMap;
            sparkle = pow(max(grain, glitterMap), 8.0) * finishBand(glitterMap * 7.0 + angle * 2.0, 4.0); break;
        case 5:
            foil = 0.34 * finishBand((uv.x + uv.y) * 12.0 + angle, 9.0)
                 + 0.24 * finishBand((uv.x - uv.y) * 12.0 - angle, 9.0); break;
        case 6:
            foil = 0.22 * finishBand(uv.y * 2.6 + angle, 4.0) + 0.13 * trainerMap * lobe; break;
        case 7:
            foil = 0.30 * finishBand(uv.x * 3.0 - uv.y * 0.3 + angle, 7.0); break;
        case 8: case 9: case 16:
            foil = (0.12 + 0.28 * lobe) * (0.18 + 0.48 * etchedMap + 0.34 * grainMap)
                 + 0.14 * finishBand(uv.x * 5.0 - uv.y * 3.0 - angle, 12.0);
            if (family == 9) foil *= 0.7;
            if (family == 16) tint = finishSpectrum(uv.y * 3.0 - angle);
            break;
        case 10: case 11: {
            float contour = sin(uv.x * 21.0 + sin(uv.y * 17.0)) + cos(uv.y * 24.0 + sin(uv.x * 15.0));
            foil = (0.10 + 0.27 * lobe) * (0.32 + 0.68 * vmaxMap)
                 * finishBand(contour * 4.0 + angle, 4.0);
            if (family == 11) { sparkle = pow(grain, 28.0) * lobe; tint = finishSpectrum(uv.y * 2.8 + angle); }
            break;
        }
        case 12:
            foil = 0.32 * lobe * (0.4 + 0.6 * etched);
            tint = mix(tint, float3(0.9, 0.93, 1.0), 0.55); break;
        case 13:
            foil = 0.21 * lobe * (0.35 + 0.65 * trainerMap); break;
        case 14:
            foil = 0.20 * lobe;
            sparkle = pow(max(grainMap, glitterMap), 7.0) * finishBand(glitterMap * 7.0 - angle, 5.0); break;
        case 15:
            tint = float3(1.0, 0.66 + 0.22 * lobe, 0.16 + 0.22 * lobe);
            foil = 0.16 * lobe + 0.22 * geometricMap * lobe;
            sparkle = pow(max(grainMap, glitterMap), 7.0) * finishBand(grain * 6.0 + angle, 5.0); break;
        case 17:
            foil = 0.20 * lobe * (0.20 + 0.80 * etchedMap);
            sparkle = pow(max(grainMap, glitterMap), 9.0) * finishBand(angle + grain * 4.0, 8.0); break;
    }
    float selectedTexture = grainMap;
    if (family == 3) selectedTexture = cosmosMap;
    else if (family == 4 || family == 14 || family == 17) selectedTexture = glitterMap;
    else if (family == 6 || family == 13) selectedTexture = trainerMap;
    else if (family == 10 || family == 11) selectedTexture = vmaxMap;
    else if (family == 15) selectedTexture = geometricMap;
    else if (family == 1 || family == 2 || family == 8 || family == 9 || family == 12 || family == 16) selectedTexture = etchedMap;
    float textureRelief = smoothstep(0.28, 0.72, selectedTexture);
    if (family > 0) {
        foil = min(1.0, foil * 1.65 + sweep * (0.24 + textureRelief * 0.20));
        sparkle += pow(textureRelief, 5.0) * sweep * 0.32;
    }
    // Screen reflection adds light locally without subtracting artwork colour.
    float3 reflection = clamp(mask * (tint * foil + mix(tint, float3(1.0), 0.62) * sparkle)
                             + glare * (family == 0 ? 0.36 : 0.18), 0.0, 0.82);
    float3 result = 1.0 - (1.0 - base) * (1.0 - reflection);
    return half4(half3(result) * input.a, input.a);
}
