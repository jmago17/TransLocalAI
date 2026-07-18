#include <metal_stdlib>
using namespace metal;

// Equalizer shown while a transcription is running: rounded bars mirrored
// around the center line, animated like live speech (layered sines with
// per-bar phase), tinted with a red→purple sweep and a soft glow.
// Output is premultiplied alpha so it composites cleanly over materials.
[[ stitchable ]] half4 transcriptionEqualizer(
    float2 position,
    float2 size,
    float time,
    half4 leadingColor,
    half4 trailingColor
) {
    constexpr float barCount = 21.0;
    float2 safeSize = max(size, float2(1.0));
    float cellWidth = safeSize.x / barCount;
    float barIndex = clamp(floor(position.x / cellWidth), 0.0, barCount - 1.0);
    float barCenterX = (barIndex + 0.5) * cellWidth;
    float barHalfWidth = cellWidth * 0.28;

    // Speech-like level: layered sines with irrational per-bar phases, plus a
    // slow "sentence" envelope, biased louder toward the middle of the capsule.
    float phase = barIndex * 2.399;   // golden-angle spread avoids visible waves
    float level = 0.34
        + 0.30 * sin(time * 4.1 + phase)
        + 0.22 * sin(time * 6.7 + phase * 1.73 + 1.4)
        + 0.14 * sin(time * 2.3 + phase * 0.51 + 4.0);
    float sentence = 0.72 + 0.28 * sin(time * 0.9 + barIndex * 0.13);
    float centered = float(barIndex) / (barCount - 1.0) - 0.5;
    float middleBias = 1.0 - 0.55 * centered * centered * 4.0;
    level = clamp(level * sentence * middleBias, 0.06, 0.94);

    // Capsule-shaped bar SDF in pixel space, mirrored around the center line.
    float maxHalfHeight = safeSize.y * 0.5 - barHalfWidth - 2.0;
    float barHalfHeight = max(level * maxHalfHeight, barHalfWidth);
    float2 delta = float2(position.x - barCenterX, position.y - safeSize.y * 0.5);
    float2 outside = abs(delta) - float2(barHalfWidth, barHalfHeight - barHalfWidth);
    float distance = length(max(outside, float2(0.0))) - barHalfWidth
        + min(max(outside.x, outside.y), 0.0);

    float core = 1.0 - smoothstep(-0.8, 0.8, distance);
    float glow = exp(-max(distance, 0.0) * 0.30);

    // Red→purple across the capsule with a slow moving shimmer; taller bars
    // burn slightly hotter toward white at the core.
    float hue = clamp(position.x / safeSize.x + 0.10 * sin(time * 0.8 + barIndex * 0.45), 0.0, 1.0);
    half3 tint = mix(leadingColor.rgb, trailingColor.rgb, half(hue));
    half3 color = mix(tint, half3(1.0), half(core * level * 0.30));

    float alpha = clamp(core + glow * 0.22, 0.0, 1.0);
    return half4(color * half(core * 0.95 + glow * 0.22), half(alpha));
}
