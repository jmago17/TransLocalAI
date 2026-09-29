import SwiftUI

/// Settings for a single transcription request. The model only applies when WhisperKit runs.
struct TranscriptionModelPicker: View {
    @Binding var engine: EnginePreference
    @Binding var modelIdentifier: String
    let language: String

    private var isMultilingual: Bool { language == "multilingual" }
    private var whisperMayRun: Bool {
        isMultilingual || engine == .whisper || engine == .auto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Engine", selection: $engine) {
                Text("Auto").tag(EnginePreference.auto)
                Text("Apple").tag(EnginePreference.apple)
                Text("WhisperKit").tag(EnginePreference.whisper)
            }
            .pickerStyle(.segmented)
            .disabled(isMultilingual)

            if isMultilingual {
                Text("Multilingual mode requires WhisperKit for per-segment language detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if engine == .auto {
                Text("Auto uses Apple for supported languages and WhisperKit for Euskara or unsupported languages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if whisperMayRun {
                Picker("WhisperKit model", selection: $modelIdentifier) {
                    ForEach(WhisperModelCatalog.defaultModels, id: \.identifier) { model in
                        Text("\(model.displayName) · ~\(model.estimatedSizeMB) MB")
                            .tag(model.identifier)
                    }
                }
                .pickerStyle(.menu)
                Text("Downloaded on first use. Size is approximate; speed and language accuracy vary by device and recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
