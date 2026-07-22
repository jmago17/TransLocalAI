import SwiftUI
#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels
#endif

struct LocalSettingsView: View {
    @AppStorage(MeetingNotesService.privateCloudComputePreferenceKey)
    private var privateCloudComputeEnabled = true
    @State private var vocabularyText = TranscriptionVocabulary.terms.joined(separator: "\n")
    @State private var whisperProfile = WhisperDecodingSupport.Profile.current
    @FocusState private var vocabularyFocused: Bool
    @State private var cloudSync = CloudSyncStatus()

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Label("Audio, transcripts, and notes are stored on this device", systemImage: "lock.shield.fill")
                    Text("Transcription stays on device. When enhanced notes are enabled, transcript text is processed by Apple's Private Cloud Compute and is not stored by Apple.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Label(cloudSync.state.title, systemImage: cloudSync.state.systemImage)
                        Spacer()
                        if cloudSync.state == .checking {
                            ProgressView()
                        } else if cloudSync.state.isHealthy {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    if case .signedOut = cloudSync.state {
                        Text("Sign in to iCloud in the Settings app to sync transcripts across your devices.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if case .localOnly(let reason) = cloudSync.state {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    if case .unavailable(let reason) = cloudSync.state {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    Text("Transcripts and meeting notes sync through your private iCloud. Audio recordings stay on this device.")
                }

                Section {
                    Toggle(isOn: $privateCloudComputeEnabled) {
                        Label("Enhanced meeting notes", systemImage: "cloud.fill")
                    }

                    if privateCloudComputeEnabled {
                        PrivateCloudComputeStatusView()
                    }
                } header: {
                    Text("Private Cloud Compute")
                } footer: {
                    Text("Uses Apple's large-context Private Cloud Compute model with reasoning on iOS 27 — ideal for notes on long recordings. If it is unavailable or its daily limit is reached, Transcriber automatically uses the on-device model.")
                }

                Section {
                    LabeledContent("Automatic engine", value: "Apple Speech")
                    LabeledContent("Euskara / multilingual", value: "Whisper Large v3")
                    LabeledContent("Whisper download", value: "About 626 MB")
                    Picker("Whisper coverage", selection: $whisperProfile) {
                        ForEach(WhisperDecodingSupport.Profile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .onChange(of: whisperProfile) { _, value in
                        WhisperDecodingSupport.Profile.current = value
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Balanced re-checks long silent stretches once. Maximum coverage keeps borderline speech and retries more aggressively — slower, but misses the least. Fast skips retries.")
                }

                Section {
                    NavigationLink {
                        TerminologySettingsView()
                    } label: {
                        Label("Terminology manager", systemImage: "character.book.closed")
                    }
                    TextEditor(text: $vocabularyText)
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($vocabularyFocused)
                        .onChange(of: vocabularyText) { _, value in
                            TranscriptionVocabulary.updateIfChanged(value.components(separatedBy: .newlines))
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .transcriptionVocabularyDidChange)) { _ in
                            let syncedText = TranscriptionVocabulary.terms.joined(separator: "\n")
                            if vocabularyText != syncedText {
                                vocabularyText = syncedText
                            }
                        }
                } header: {
                    Text("Names and companies")
                } footer: {
                    Text("One name or phrase per line, up to 100. To fix a word the transcriber keeps getting wrong, write the correct spelling, =, then what it hears: Iñaki = Yankee, Ianki. Synced with iCloud and used by Apple Speech and WhisperKit.")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .liquidCrystalScreen()
            .navigationTitle("Settings")
            .task { await cloudSync.refresh() }
            .toolbar {
                if vocabularyFocused {
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("Done") { vocabularyFocused = false }
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }
}

private struct PrivateCloudComputeStatusView: View {
    var body: some View {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27, macOS 27, *) {
            PrivateCloudComputeAvailabilityView()
        } else {
            unavailableLabel
        }
        #else
        unavailableLabel
        #endif
    }

    private var unavailableLabel: some View {
        Label("Requires iOS 27 or later", systemImage: "info.circle")
            .foregroundStyle(.secondary)
    }
}

#if canImport(FoundationModels) && compiler(>=6.4)
@available(iOS 27, macOS 27, *)
private struct PrivateCloudComputeAvailabilityView: View {
    private let model = PrivateCloudComputeLanguageModel()

    var body: some View {
        if !MeetingNotesService.hasPrivateCloudComputeEntitlement {
            Label("Not enabled for this build — using on-device model", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
        switch model.availability {
        case .available where !MeetingNotesService.hasPrivateCloudComputeEntitlement:
            EmptyView()
        case .available:
            quotaStatus
        case .unavailable(.deviceNotEligible):
            Label("This device is not eligible", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .unavailable(.systemNotReady):
            Label("Temporarily unavailable — using on-device model", systemImage: "clock")
                .foregroundStyle(.secondary)
        @unknown default:
            Label("Unavailable — using on-device model", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }

        if let suggestion = model.quotaUsage.limitIncreaseSuggestion {
            Button("Show usage options") {
                suggestion.show()
            }
        }
    }

    @ViewBuilder
    private var quotaStatus: some View {
        if model.quotaUsage.isLimitReached {
            Label("Daily limit reached — using on-device model", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        } else if case .belowLimit(let info) = model.quotaUsage.status, info.isApproachingLimit {
            Label("Approaching daily limit", systemImage: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.orange)
        } else {
            Label("Available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
#endif
