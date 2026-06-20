//
//  MacSettingsView.swift
//  TranscriberMac
//
//  Settings: transcription + redaction engines, API keys (Keychain), external
//  tool paths, and launch-at-login.
//

import SwiftUI

struct MacSettingsView: View {
    @State private var settings = MacSettings.shared
    @State private var openAIKey: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Transcripción") {
                Picker("Motor", selection: $settings.transcribe) {
                    ForEach(TranscribeBackend.allCases) { Text($0.label).tag($0) }
                }
                if settings.transcribe == .whisperCpp {
                    TextField("Binario whisper-cli", text: $settings.whisperCppBin)
                    TextField("Modelo ggml", text: $settings.whisperCppModel)
                }
            }

            Section("Redacción del acta") {
                Picker("Motor", selection: $settings.redact) {
                    ForEach(RedactBackend.allCases) { Text($0.label).tag($0) }
                }
                switch settings.redact {
                case .openAI:
                    SecureField("Clave API OpenAI", text: $openAIKey)
                        .onChange(of: openAIKey) { _, v in settings.setOpenAIKey(v) }
                    TextField("Modelo", text: $settings.openAIModel)
                case .openAICLI, .claudeCLI:
                    TextField("Ruta del CLI", text: $settings.redactCliPath)
                case .appleFoundation:
                    Text("Modelos en el dispositivo (Apple Foundation). Sin clave ni red.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Arrancar al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.setEnabled(v) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
        .onAppear { openAIKey = settings.openAIKey() ?? "" }
    }
}
