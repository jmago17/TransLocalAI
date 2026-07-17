#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 transcriptionPulse(
    float2 position,
    float2 size,
    float time,
    half4 leadingColor,
    half4 trailingColor
) {
    float2 uv = position / max(size, float2(1.0));
    constexpr float barCount = 11.0;
    float barIndex = floor(uv.x * barCount);
    float barCenter = (barIndex + 0.5) / barCount;
    float distanceFromBar = abs(uv.x - barCenter);

    float phase = time * 3.2 + barIndex * 0.72;
    float envelope = 0.15 + 0.25 * (0.5 + 0.5 * sin(phase));
    envelope *= 0.72 + 0.28 * sin((uv.x + time * 0.12) * M_PI_F);

    float bar = 1.0 - smoothstep(0.020, 0.034, distanceFromBar);
    float verticalDistance = abs(uv.y - 0.5);
    float body = 1.0 - smoothstep(envelope, envelope + 0.025, verticalDistance);
    float glow = exp(-34.0 * max(verticalDistance - envelope, 0.0));

    float sweep = 0.5 + 0.5 * sin(time * 1.35 + uv.x * 4.8);
    half3 tint = mix(leadingColor.rgb, trailingColor.rgb, half(sweep));
    float pulse = bar * body;
    float halo = bar * glow * 0.38;
    float background = 0.10 + 0.05 * sin(time + uv.x * 5.0);
    float alpha = clamp(background + halo + pulse * 0.88, 0.0, 1.0);
    half3 color = tint * half(0.55 + pulse * 0.7 + halo);
    return half4(color * half(alpha), half(alpha));
}
