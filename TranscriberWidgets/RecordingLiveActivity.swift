import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text("Recording")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startDate, style: .timer)
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 50)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.recordingTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label("Recording in TransLocalAI", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(context.attributes.startDate, style: .timer)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
                    .frame(minWidth: 40)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Recording")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer()
                    Text(context.attributes.startDate, style: .timer)
                        .font(.headline.monospacedDigit())
                }
                Text(context.attributes.recordingTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "stop.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.red)
                .clipShape(Circle())
        }
        .padding()
        // Without a tint the lock-screen activity renders on flat black.
        // A red tint was the other candidate, but on a light wallpaper it
        // turns the panel pink and the red "Recording" label stops reading;
        // `.clear` hands the background to the system material, which keeps
        // the red accent legible over both light and dark wallpapers.
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(Color.primary)
    }
}
