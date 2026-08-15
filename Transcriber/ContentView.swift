//
//  ContentView.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Transcription.timestamp, order: .reverse) private var transcriptions: [Transcription]

    @State private var showImportView = false
    @State private var showTranscriptImport = false
    @State private var showRecordView = false
    @State private var searchText = ""
    @State private var selection: Set<UUID> = []
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#endif

    private var recorder: AudioRecorderManager { AudioRecorderManager.shared }

    var body: some View {
#if os(iOS)
        // A split view inside a tab is an iPad/Mac shape. On iPhone the tab
        // already owns the top level, so the library is a plain stack.
        if horizontalSizeClass == .compact {
            NavigationStack { library }
        } else {
            splitLayout
        }
#else
        splitLayout
#endif
    }

    private var splitLayout: some View {
        NavigationSplitView {
            library
        } detail: {
            ContentUnavailableView(
                "Select a Transcription",
                systemImage: "text.bubble",
                description: Text("Choose a transcription from the list to view its details")
            )
            .liquidCrystalScreen()
        }
    }

    // MARK: - Library

    private var library: some View {
        Group {
            if filteredTranscriptions.isEmpty {
                emptyStateView
            } else {
                transcriptionsList
            }
        }
        .liquidCrystalScreen()
        .navigationTitle("Transcriptions")
        .searchable(text: $searchText, prompt: "Search transcriptions")
#if os(iOS)
        .environment(\.editMode, $editMode)
        .onChange(of: editMode) { _, mode in
            if !mode.isEditing { selection.removeAll() }
        }
#endif
        .toolbar { libraryToolbar }
        .sheet(isPresented: $showImportView) {
            ImportAudioView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptImportView()
        }
        .sheet(isPresented: $showRecordView) {
            RecordingView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) {
            if recorder.isRecording {
                recordingIndicatorBar
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            EditButton()
                .disabled(filteredTranscriptions.isEmpty)
        }
#endif
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showImportView = true
                } label: {
                    Label("Import Audio", systemImage: "waveform.badge.plus")
                }
                Button {
                    showTranscriptImport = true
                } label: {
                    Label("Import Transcript", systemImage: "doc.text")
                }
            } label: {
                Label("Import", systemImage: "plus")
            }
        }
#if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            if editMode.isEditing {
                Button(role: .destructive, action: deleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)

                Spacer()

                Text(selectionSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                ShareLink(items: selectedTranscriptions.map(shareText)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
            }
        }
#endif
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(searchText.isEmpty ? "No Transcriptions" : "No Matches", systemImage: "waveform")
        } description: {
            Text(searchText.isEmpty
                 ? "Import audio files to create transcriptions"
                 : "No transcription matches “\(searchText)”")
        } actions: {
            if searchText.isEmpty {
                Button {
                    showImportView = true
                } label: {
                    Label("Import Audio File", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var transcriptionsList: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.transcriptions, id: \.id) { transcription in
                        NavigationLink {
                            TranscriptionDetailView(transcription: transcription)
                        } label: {
                            TranscriptionRowView(transcription: transcription, period: group.period)
                        }
                        .liquidCrystalRow()
                    }
                    .onDelete { offsets in
                        delete(offsets, in: group.transcriptions)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.period.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(group.transcriptions.count, format: .number)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .liquidCrystalSectionHeader()
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
    }

    private var recordingIndicatorBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LiquidCrystal.recordingAccent)
                .frame(width: 10, height: 10)

            Text("Recording")
                .font(.subheadline.weight(.semibold))

            Text(recorder.formattedElapsedTime)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("Open") { showRecordView = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(LiquidCrystal.recordingAccent)
        }
        .padding(.horizontal, LiquidCrystal.Layout.cardPadding)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(LiquidCrystal.recordingAccent.opacity(LiquidCrystal.toneFillOpacity)),
            in: .capsule
        )
        .padding(.horizontal, LiquidCrystal.Layout.cardInset)
        .padding(.bottom, 6)
    }

    // MARK: - Data

    private var filteredTranscriptions: [Transcription] {
        guard !searchText.isEmpty else { return transcriptions }
        return transcriptions.filter { transcription in
            transcription.title.localizedCaseInsensitiveContains(searchText) ||
            transcription.transcriptionText.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The list arrives newest-first, so a single pass keeps every period in
    /// order without sorting again.
    private var groups: [LibraryGroup] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [LibraryGroup] = []

        for transcription in filteredTranscriptions {
            let period = LibraryPeriod(for: transcription.timestamp, calendar: calendar, now: now)
            if groups.last?.period == period {
                groups[groups.count - 1].transcriptions.append(transcription)
            } else {
                groups.append(LibraryGroup(period: period, transcriptions: [transcription]))
            }
        }
        return groups
    }

    private var selectedTranscriptions: [Transcription] {
        transcriptions.filter { selection.contains($0.id) }
    }

    private var selectionSummary: String {
        selection.isEmpty
            ? "Select transcriptions"
            : "\(selection.count) selected"
    }

    private func shareText(for transcription: Transcription) -> String {
        "\(transcription.title)\n\n\(transcription.transcriptionText)"
    }

    private func delete(_ offsets: IndexSet, in group: [Transcription]) {
        withAnimation {
            for index in offsets {
                delete(group[index])
            }
        }
    }

    private func deleteSelected() {
        withAnimation {
            selectedTranscriptions.forEach(delete)
            selection.removeAll()
        }
    }

    private func delete(_ transcription: Transcription) {
        // Delete associated audio file if it exists
        if let audioFileName = transcription.audioFileURL {
            AudioFileManager.shared.deleteAudio(filename: audioFileName)
        }
        modelContext.delete(transcription)
    }
}

// MARK: - Grouping

/// How far back a transcription is, in the terms a reader thinks in.
enum LibraryPeriod: Int, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case earlier

    init(for date: Date, calendar: Calendar, now: Date) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    /// The header already says which day it was, so the row only adds what the
    /// header leaves out.
    var timestampFormat: Date.FormatStyle {
        switch self {
        case .today, .yesterday:
            return .dateTime.hour().minute()
        case .thisWeek:
            return .dateTime.weekday(.abbreviated)
        case .thisMonth:
            return .dateTime.day().month(.abbreviated)
        case .earlier:
            return .dateTime.day().month(.abbreviated).year(.twoDigits)
        }
    }
}

struct LibraryGroup: Identifiable {
    let period: LibraryPeriod
    var transcriptions: [Transcription]

    var id: Int { period.rawValue }
}

// MARK: - Row

struct TranscriptionRowView: View {
    let transcription: Transcription
    var period: LibraryPeriod = .today

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidCrystal.Layout.lineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(transcription.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(transcription.timestamp, format: period.timestampFormat)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .layoutPriority(1)
            }

            if !transcription.transcriptionText.isEmpty {
                Text(transcription.transcriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: LiquidCrystal.Layout.badgeSpacing) {
                Label {
                    Text(formattedDuration)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

                if let language = languageBadge {
                    language
                }

                if let engine = engineBadge {
                    engine
                }
            }
            .padding(.top, 2)
        }
    }

    private var languageBadge: CrystalBadge? {
        switch transcription.language {
        case "multilingual":
            return CrystalBadge(text: "Multi", systemImage: "globe")
        case "unknown", "":
            return nil
        default:
            let code = transcription.language
                .split(separator: "-")
                .first
                .map(String.init)?
                .uppercased()
            guard let code else { return nil }
            return CrystalBadge(
                text: code,
                systemImage: transcription.languageWasAutoDetected ? "wand.and.sparkles" : nil
            )
        }
    }

    private var engineBadge: CrystalBadge? {
        switch transcription.engineUsed.lowercased() {
        case "apple":
            return CrystalBadge(text: "Apple", tone: .accent)
        case "whisper":
            return CrystalBadge(text: "Whisper", tone: .feature)
        case "whisper-device":
            return CrystalBadge(text: "Whisper (local)", tone: .feature)
        default:
            return nil
        }
    }

    private var formattedDuration: String {
        let minutes = Int(transcription.duration) / 60
        let seconds = Int(transcription.duration) % 60

        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
