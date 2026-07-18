import SwiftUI

/// Capsule with a Metal "liquid glow waveform" (see TranscriptionShaders.metal)
/// shown wherever a transcription is in progress.
struct TranscribingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size = CGSize(width: 190, height: 84)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            // A fixed timestamp yields a pleasant static frame under Reduce Motion.
            let time = reduceMotion ? 1.6 : timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(
                        ShaderLibrary.transcriptionFlow(
                            .float2(size),
                            .float(Float(time.truncatingRemainder(dividingBy: 1_000))),
                            .color(.red),
                            .color(.purple)
                        )
                    )
                    .padding(6)
                    .blendMode(.plusLighter)

                Capsule()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.45),
                                .purple.opacity(0.25),
                                .white.opacity(0.10),
                                .red.opacity(0.25),
                                .white.opacity(0.45)
                            ],
                            center: .center,
                            angle: .degrees(reduceMotion ? 0 : time.truncatingRemainder(dividingBy: 8) * 45)
                        ),
                        lineWidth: 1
                    )
            }
            .frame(width: size.width, height: size.height)
            .compositingGroup()
            .shadow(color: .purple.opacity(0.25), radius: 18)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    TranscribingAnimation()
        .padding(40)
        .background(Color(.systemGroupedBackground))
}
