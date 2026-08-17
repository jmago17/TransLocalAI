import SwiftUI
#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels
#endif

struct LocalSettingsView: View {
    @AppStorage(MeetingNotesService.privateCloudComputePreferenceKey)
    private var privateCloudComputeEnabled = true
    @State private var whisperProfile = WhisperDecodingSupport.Profile.current
    @State private var showBulkEditor = false
    @State private var termCount = TranscriptionVocabulary.terms.count
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
                        HStack {
                            Label("Terminology manager", systemImage: "character.book.closed")
                            Spacer()
                            if termCount > 0 {
                                Text("\(termCount)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showBulkEditor = true
                    } label: {
                        Label("Edit as text", systemImage: "text.alignleft")
                    }
                } header: {
                    Text("Names and companies")
                } footer: {
                    Text("Names, companies, and terms your transcriptions should spell correctly. Manage them one by one, or paste a whole list with Edit as text. Synced with iCloud and used by Apple Speech and WhisperKit.")
                }
                .onReceive(NotificationCenter.default.publisher(for: .transcriptionVocabularyDidChange)) { _ in
                    termCount = TranscriptionVocabulary.terms.count
                }

                Section {
                    NavigationLink {
                        ShortcutsGuideView()
                    } label: {
                        Label("Shortcuts guide", systemImage: "shortcuts")
                    }
                } header: {
                    Text("Shortcuts and automation")
                } footer: {
                    Text("Record, transcribe, and search from Shortcuts, Siri, or an Action button.")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .liquidCrystalScreen()
            .navigationTitle("Settings")
            .task { await cloudSync.refresh() }
            .sheet(isPresented: $showBulkEditor) {
                VocabularyBulkEditView()
            }
        }
    }
}

/// Bulk paste/edit of the vocabulary as plain text — the fast path when
/// migrating a list from Notes or another device. One term per line;
/// `Correct = heard1, heard2` teaches replacements.
private struct VocabularyBulkEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = TranscriptionVocabulary.terms.joined(separator: "\n")
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("One name or phrase per line. To teach a mishearing, write the correct spelling, then what it hears after a colon: Iñaki: Yankee, Ianki")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .liquidCrystalScreen()
            .navigationTitle("Edit terms as text")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        TranscriptionVocabulary.updateIfChanged(text.components(separatedBy: .newlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
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
