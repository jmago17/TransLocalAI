#include <metal_stdlib>
using namespace metal;

// Liquid glow waveform shown while a transcription is running.
// Three ribbons of "speech energy" flow through the capsule, each with a
// bright core and a soft halo, tinted by a hue sweep between the two colors.
// Output is premultiplied alpha so it composites cleanly over materials.
[[ stitchable ]] half4 transcriptionFlow(
    float2 position,
    float2 size,
    float time,
    half4 leadingColor,
    half4 trailingColor
) {
    float2 uv = position / max(size, float2(1.0));
    float x = uv.x;
    float y = uv.y - 0.5;

    // Dissolve the ribbons before they touch the capsule's rounded ends.
    float edgeFade = smoothstep(0.0, 0.16, x) * smoothstep(1.0, 0.84, x);
    // Keep the glow inside the capsule vertically as well.
    float verticalFade = 1.0 - smoothstep(0.30, 0.5, fabs(y));

    half3 color = half3(0.0);
    float energy = 0.0;

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float speed = 1.15 + fi * 0.42;
        float freq = 5.2 + fi * 2.4;

        // Slow breathing so the ribbons feel like live speech, not a loop.
        float breathe = 0.55 + 0.45 * sin(time * (0.63 + fi * 0.29) + fi * 2.1);
        float amplitude = (0.17 - fi * 0.035) * breathe;

        float wave = sin(x * freq + time * speed * 2.1 + fi * 1.9)
                   + 0.55 * sin(x * freq * 1.83 - time * speed * 1.35 + fi * 4.0)
                   + 0.25 * sin(x * freq * 3.1 + time * (speed + 0.8) + fi * 0.7);
        float centerY = wave * amplitude * 0.45;

        float distance = fabs(y - centerY);
        float core = exp(-distance * distance * 2600.0);
        float halo = exp(-distance * 11.0);
        float intensity = (core * 0.9 + halo * 0.32) * edgeFade * verticalFade;

        float hue = 0.5 + 0.5 * sin(x * 2.6 + time * (0.45 + 0.2 * fi) + fi * 2.09);
        half3 ribbon = mix(leadingColor.rgb, trailingColor.rgb, half(hue));
        // Lift the core toward white for a hot, glassy center line.
        ribbon = mix(ribbon, half3(1.0), half(core * 0.35));

        color += ribbon * half(intensity);
        energy += intensity;
    }

    // Faint ambient wash so the capsule never looks empty between pulses.
    float ambient = (0.075 + 0.035 * sin(time * 0.7 + x * 3.2)) * edgeFade * verticalFade;
    color += mix(leadingColor.rgb, trailingColor.rgb, half(x)) * half(ambient);

    float alpha = clamp(energy * 0.85 + ambient, 0.0, 1.0);
    return half4(min(color, half3(1.0)) * half(alpha), half(alpha));
}
