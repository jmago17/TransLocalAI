# TransLocalAI — Icon Composer layers

All artwork uses the same 1024 × 1024 canvas, so the layers remain aligned when imported together.

Import from back to front:

1. `00-background.svg`
2. `10-waveform.svg`
3. `20-stand.svg`
4. `30-microphone.svg`

Suggested Icon Composer setup:

- Keep the background full-bleed; don't add a rounded-square mask because the system supplies it.
- Put waveform and stand in one group using Combined glass with subtle refraction.
- Put the microphone in the front group with stronger specular highlights and a small z-offset.
- Preserve the coral-to-amber palette for Default, use deeper orange over near-black purple for Dark, and map the microphone to white with the waveform at roughly 65% gray for Mono.
- Start with restrained shadows. Icon Composer generates the dynamic depth and lighting, so no shadow is baked into these layers.

The SVG files are the preferred source. The sibling PNG files are transparent 1024 × 1024 fallbacks for any SVG feature Icon Composer doesn't accept.

The `Light` directory contains the matching light appearance with the palette inverted: an orange full-bleed background and deep-purple artwork. Import its four layers in the same numeric order. The files in this directory remain the dark appearance.
