import SwiftUI

/// Metal equalizer (see TranscriptionShaders.metal) shown wherever a
/// transcription is in progress — bare bars, no container.
/// Pass `progress` (0...1) to fill the bars from the left as work advances;
/// leave it nil for the indeterminate, fully-lit state.
struct TranscribingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size = CGSize(width: 190, height: 84)
    var progress: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            // A fixed timestamp yields a pleasant static frame under Reduce Motion.
            let time = reduceMotion ? 1.6 : timeline.date.timeIntervalSinceReferenceDate

            Rectangle()
                .fill(
                    ShaderLibrary.transcriptionEqualizer(
                        .float2(size),
                        .float(Float(time.truncatingRemainder(dividingBy: 1_000))),
                        .float(Float(progress ?? -1)),
                        .color(.yellow),
                        .color(.red)
                    )
                )
                .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 30) {
        TranscribingAnimation()
        TranscribingAnimation(progress: 0.55)
    }
    .padding(40)
    .background(Color(.systemGroupedBackground))
}
