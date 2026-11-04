import SwiftUI

struct VozInformationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var downloaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Voz model", value: downloaded ? "Downloaded · ready to load" : "Not downloaded · about 337 MB")
            Text("Downloaded only when you transcribe with Voz. Initial loading can take 10–30 seconds. Select one supported language; Voz does not detect languages. Use WhisperKit for Euskara or mixed-language audio. Voz is unavailable in the Share extension.")
            Link("Powered by Desert Ant Labs", destination: URL(string: "https://desertant.com")!)
            Text("Voz's mandatory license check sends a random installation ID, app ID, SDK/model versions and platform. No audio or transcript is sent. Inference stays on device and works offline after download if the check fails.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task { downloaded = VozTranscriptionEngine.isDownloaded }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { downloaded = VozTranscriptionEngine.isDownloaded }
        }
    }
}
