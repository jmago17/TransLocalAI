#include <metal_stdlib>
using namespace metal;

// Equalizer shown while a transcription is running: rounded bars mirrored
// around the center line, animated like live speech (layered sines with
// per-bar phase). `progress` in 0...1 fills the bars from the left; pass a
// negative value for an indeterminate, fully-lit state.
// Output is premultiplied alpha so it composites cleanly over materials.
[[ stitchable ]] half4 transcriptionEqualizer(
    float2 position,
    float2 size,
    float time,
    float progress,
    half4 leadingColor,
    half4 trailingColor
) {
    constexpr float barCount = 27.0;
    float2 safeSize = max(size, float2(1.0));
    float cellWidth = safeSize.x / barCount;
    float barIndex = clamp(floor(position.x / cellWidth), 0.0, barCount - 1.0);
    float barCenterX = (barIndex + 0.5) * cellWidth;
    // Bars take ~38% of the cell; the rest is breathing room between them.
    float barHalfWidth = cellWidth * 0.19;

    // Speech-like level: layered sines with irrational per-bar phases and a
    // gentle "sentence" swell. The floor and envelope are tuned so the whole
    // row never collapses flat at once.
    float phase = barIndex * 2.399;   // golden-angle spread avoids visible waves
    float level = 0.42
        + 0.30 * sin(time * 4.1 + phase)
        + 0.22 * sin(time * 6.7 + phase * 1.73 + 1.4)
        + 0.14 * sin(time * 2.3 + phase * 0.51 + 4.0);
    float sentence = 0.85 + 0.15 * sin(time * 0.9 + barIndex * 0.13);
    float centered = float(barIndex) / (barCount - 1.0) - 0.5;
    float middleBias = 1.0 - 0.30 * centered * centered * 4.0;
    level = clamp(level * sentence * middleBias, 0.18, 0.96);

    // Capsule-shaped bar SDF in pixel space, mirrored around the center line.
    float maxHalfHeight = safeSize.y * 0.5 - barHalfWidth - 1.0;
    float barHalfHeight = max(level * maxHalfHeight, barHalfWidth);
    float2 delta = float2(position.x - barCenterX, position.y - safeSize.y * 0.5);
    float2 outside = abs(delta) - float2(barHalfWidth, barHalfHeight - barHalfWidth);
    float distance = length(max(outside, float2(0.0))) - barHalfWidth
        + min(max(outside.x, outside.y), 0.0);

    // Crisp ~1pt anti-aliased edge; no halo — glow reads as blur at this size.
    float core = 1.0 - smoothstep(-0.5, 0.5, distance);

    // Gradient across the row with a slow moving shimmer; taller bars warm up
    // slightly at the core.
    float x = position.x / safeSize.x;
    float hue = clamp(x + 0.10 * sin(time * 0.8 + barIndex * 0.45), 0.0, 1.0);
    half3 tint = mix(leadingColor.rgb, trailingColor.rgb, half(hue));
    half3 color = mix(tint, half3(1.0), half(core * level * 0.12));

    // Bars behind the progress point burn at full strength; the rest stay dim.
    // The fill sweeps through each bar pixel-by-pixel, so the boundary bar
    // fills horizontally as progress advances.
    float lit = progress < 0.0 ? 1.0 : 1.0 - smoothstep(progress - 0.005, progress + 0.005, x);
    float strength = mix(0.28, 1.0, lit);

    return half4(color * half(core * strength), half(core * strength));
}
