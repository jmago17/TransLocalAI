import ActivityKit
import SwiftUI
import WidgetKit

struct TranscriptionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranscriptionActivityAttributes.self) { context in
            // Lock Screen / banner view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.fileName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.progress)
                            .tint(.blue)
                        HStack {
                            Text(context.state.phase)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formattedTime(context.state.elapsedSeconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TranscriptionActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                Text("Transcribing")
                    .font(.headline)
                Spacer()
                Text(context.attributes.engine)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(context.attributes.fileName)
                .font(.subheadline)
                .lineLimit(1)

            ProgressView(value: context.state.progress)
                .tint(.blue)

            HStack {
                Text(context.state.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedTime(context.state.elapsedSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
