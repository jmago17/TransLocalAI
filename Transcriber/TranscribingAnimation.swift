import SwiftUI

struct TranscribingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size = CGSize(width: 190, height: 84)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(
                        ShaderLibrary.transcriptionPulse(
                            .float2(size),
                            .float(Float(time.truncatingRemainder(dividingBy: 1_000))),
                            .color(.red),
                            .color(.purple)
                        )
                    )
                    .padding(7)

                Capsule()
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }
}
