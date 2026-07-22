import SwiftUI
import UniformTypeIdentifiers

/// Global terminology manager: every term the engines are biased toward,
/// with the evidence behind it (fixes, appearances, state), plus add/edit/
/// disable/delete, search, sorting, and import/export.
struct TerminologySettingsView: View {

    enum SortOrder: String, CaseIterable, Identifiable {
        case relevance = "Relevance"
        case name = "Name"
        case corrections = "Fixes"
        case usage = "Appearances"
        var id: String { rawValue }
    }

    @State private var entries: [TranscriptionTerminology.Entry] = []
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .relevance
    @State private var editingEntry: TranscriptionTerminology.Entry?
    @State private var isAddingTerm = false
    @State private var newTermText = ""
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var exportURL: URL?

    var body: some View {
        List {
            if userEntries.isEmpty && builtInEntries.isEmpty {
                ContentUnavailableView(
                    "No terms",
                    systemImage: "character.book.closed",
                    description: Text("Add names, companies, and technical terms so transcriptions spell them correctly.")
                )
            }

            if !userEntries.isEmpty {
                Section {
                    ForEach(userEntries) { entry in
                        row(for: entry)
                    }
                } header: {
                    Text("Your terms")
                } footer: {
                    Text("Synced with iCloud. The most relevant terms are supplied to Apple Speech and Whisper before each transcription.")
                }
            }

            if !builtInEntries.isEmpty {
                Section {
                    ForEach(builtInEntries) { entry in
                        row(for: entry)
                    }
                } header: {
                    Text("Built-in suggestions")
                } footer: {
                    Text("Common technical vocabulary. It gains influence only when it actually appears in your transcripts, or when you confirm it.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .liquidCrystalScreen()
        .navigationTitle("Terminology")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search terms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newTermText = ""
                    isAddingTerm = true
                } label: {
                    Label("Add term", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export glossary", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .alert("Add term", isPresented: $isAddingTerm) {
            TextField("Correct spelling", text: $newTermText)
                .autocorrectionDisabled()
            Button("Add") {
                TranscriptionTerminology.addTerm(newTermText)
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The exact spelling transcriptions should use, e.g. a name, company, or acronym.")
        }
        .alert(
            "Import finished",
            isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })
        ) {
            Button("OK") { importResult = nil }
        } message: {
            Text(importResult ?? "")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .plainText, .commaSeparatedText]
        ) { result in
            handleImport(result)
        }
        .sheet(item: $editingEntry) { entry in
            TerminologyEditSheet(entry: entry) {
                reload()
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionVocabularyDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Rows

    private func row(for entry: TranscriptionTerminology.Entry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.canonical)
                        .font(.body.weight(.medium))
                        .foregroundStyle(entry.state == .disabled ? .secondary : .primary)
                        .strikethrough(entry.state == .disabled)
                    stateBadge(entry.state)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !entry.aliases.isEmpty {
                    Text("Replaces: \(entry.aliases.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(evidenceLine(for: entry))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if entry.source != .builtIn {
                Button(role: .destructive) {
                    TranscriptionTerminology.deleteTerm(canonical: entry.canonical)
                    reload()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                TranscriptionTerminology.setEnabled(entry.state == .disabled, canonical: entry.canonical)
                reload()
            } label: {
                Label(
                    entry.state == .disabled ? "Enable" : "Disable",
                    systemImage: entry.state == .disabled ? "checkmark.circle" : "nosign"
                )
            }
            .tint(entry.state == .disabled ? .green : .orange)
        }
    }

    @ViewBuilder
    private func stateBadge(_ state: TranscriptionTerminology.State) -> some View {
        switch state {
        case .trusted:
            Label("Trusted", systemImage: "checkmark.seal.fill")
                .font(.caption2).labelStyle(.iconOnly).foregroundStyle(.green)
        case .suggested:
            Label("Suggested", systemImage: "sparkles")
                .font(.caption2).labelStyle(.iconOnly).foregroundStyle(.orange)
        case .disabled:
            Label("Disabled", systemImage: "nosign")
                .font(.caption2).labelStyle(.iconOnly).foregroundStyle(.secondary)
        case .confirmed, .observed:
            EmptyView()
        }
    }

    /// "Why is this term here?" in one line.
    private func evidenceLine(for entry: TranscriptionTerminology.Entry) -> String {
        var parts: [String] = []
        switch entry.source {
        case .correction: parts.append("Learned from your fixes")
        case .user: parts.append("Added by you")
        case .builtIn: parts.append("Built-in")
        }
        if entry.correctionCount > 0 { parts.append("\(entry.correctionCount) fix\(entry.correctionCount == 1 ? "" : "es")") }
        if entry.usageCount > 0 { parts.append("heard \(entry.usageCount)×") }
        if let lastUsed = entry.lastUsedAt {
            parts.append("last \(lastUsed.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data

    private var filtered: [TranscriptionTerminology.Entry] {
        var result = entries
        if !searchText.isEmpty {
            let needle = TranscriptionTerminology.normalize(searchText)
            result = result.filter {
                $0.normalized.contains(needle)
                    || $0.aliases.contains { alias in TranscriptionTerminology.normalize(alias).contains(needle) }
            }
        }
        switch sortOrder {
        case .relevance:
            result.sort { $0.score != $1.score ? $0.score > $1.score : $0.canonical < $1.canonical }
        case .name:
            result.sort { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
        case .corrections:
            result.sort { $0.correctionCount != $1.correctionCount ? $0.correctionCount > $1.correctionCount : $0.canonical < $1.canonical }
        case .usage:
            result.sort { $0.usageCount != $1.usageCount ? $0.usageCount > $1.usageCount : $0.canonical < $1.canonical }
        }
        return result
    }

    private var userEntries: [TranscriptionTerminology.Entry] {
        filtered.filter { $0.source != .builtIn }
    }

    private var builtInEntries: [TranscriptionTerminology.Entry] {
        filtered.filter { $0.source == .builtIn }
    }

    private func reload() {
        entries = TranscriptionTerminology.entries
        prepareExport()
    }

    private func prepareExport() {
        guard let data = TranscriptionTerminology.exportJSON() else {
            exportURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Transcriber-Glossary.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importResult = "Could not read the file."
            return
        }
        let added = TranscriptionTerminology.importTerms(from: text)
        importResult = added == 0
            ? "No new terms found — everything was already in your glossary."
            : "Added \(added) new term\(added == 1 ? "" : "s")."
        reload()
    }
}

// MARK: - Edit sheet

private struct TerminologyEditSheet: View {
    let entry: TranscriptionTerminology.Entry
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canonicalText: String
    @State private var aliasesText: String
    @State private var isEnabled: Bool

    init(entry: TranscriptionTerminology.Entry, onSave: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        _canonicalText = State(initialValue: entry.canonical)
        _aliasesText = State(initialValue: entry.aliases.joined(separator: ", "))
        _isEnabled = State(initialValue: entry.state != .disabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Correct spelling", text: $canonicalText)
                        .autocorrectionDisabled()
                    TextField("Misheard as (comma-separated)", text: $aliasesText)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Every listed mishearing is replaced by the correct spelling in new transcriptions.")
                }

                Section {
                    Toggle("Use in transcriptions", isOn: $isEnabled)
                    if entry.source == .builtIn && entry.state != .confirmed && entry.state != .trusted {
                        Button("Confirm this term") {
                            TranscriptionTerminology.confirmTerm(canonical: entry.canonical)
                            onSave()
                            dismiss()
                        }
                    }
                }

                Section("Evidence") {
                    LabeledContent("Source", value: sourceDescription)
                    LabeledContent("State", value: entry.state.rawValue.capitalized)
                    LabeledContent("Fixes", value: "\(entry.correctionCount)")
                    LabeledContent("Appearances", value: "\(entry.usageCount)")
                    if let firstSeen = entry.firstSeenAt {
                        LabeledContent("First seen", value: firstSeen.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let lastUsed = entry.lastUsedAt {
                        LabeledContent("Last heard", value: lastUsed.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .liquidCrystalScreen()
            .navigationTitle("Edit term")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(canonicalText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var sourceDescription: String {
        switch entry.source {
        case .correction: return "Learned from your fixes"
        case .user: return "Added by you"
        case .builtIn: return "Built-in vocabulary"
        }
    }

    private func save() {
        let aliases = aliasesText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if canonicalText != entry.canonical || aliases != entry.aliases {
            TranscriptionTerminology.updateTerm(
                originalCanonical: entry.canonical,
                newCanonical: canonicalText,
                aliases: aliases
            )
        }
        if isEnabled != (entry.state != .disabled) {
            TranscriptionTerminology.setEnabled(isEnabled, canonical: canonicalText)
        }
        onSave()
        dismiss()
    }
}
