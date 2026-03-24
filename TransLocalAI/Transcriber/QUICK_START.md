# System Files Integration - Quick Start Guide

## ✅ Files Successfully Added to Project

All system files integration files are now in your Xcode project:

1. ✅ `FileExportManager.swift` - Export functionality
2. ✅ `FileExportView.swift` - Export UI
3. ✅ `FileImportManager.swift` - Import functionality (warnings fixed)
4. ✅ `FileImportView.swift` - Import UI (import added)
5. ✅ `TranscriptionDocument.swift` - Document support (warnings fixed)
6. ✅ `QuickLookTranscription.swift` - Preview support

## ⚠️ Next Steps to Complete Integration

### Step 1: Uncomment Code in ContentView.swift

Open `ContentView.swift` and uncomment the following sections:

**Line ~22:** Uncomment the FileExportManager
```swift
private let exportManager = FileExportManager()
```

**Lines ~45-55:** Uncomment the iOS menu items
```swift
Divider()

Button(action: { showFileImport = true }) {
    Label("Import File", systemImage: "arrow.down.doc")
}

Button(action: { exportBackup() }) {
    Label("Export Backup", systemImage: "square.and.arrow.up.on.square")
}
```

**Lines ~68-78:** Uncomment the macOS menu items
```swift
Divider()

Button(action: { showFileImport = true }) {
    Label("Import File", systemImage: "arrow.down.doc")
}

Button(action: { exportBackup() }) {
    Label("Export Backup", systemImage: "square.and.arrow.up.on.square")
}
```

**Lines ~105-118:** Uncomment the sheets
```swift
.sheet(isPresented: $showFileImport) {
    FileImportView()
}
.fileExporter(
    isPresented: $showBackupExport,
    document: backupFileURL.map { TranscriptionDocument(fileURL: $0) },
    contentType: .json,
    defaultFilename: "Transcriber-Backup-\(Date().formatted(date: .numeric, time: .omitted)).json"
) { result in
    handleBackupExport(result)
}
```

**Lines ~166-186:** Uncomment the backup functions
```swift
private func exportBackup() {
    Task {
        do {
            let fileURL = try await exportManager.createBackup(transcriptions: transcriptions)
            await MainActor.run {
                backupFileURL = fileURL
                showBackupExport = true
            }
        } catch {
            print("Failed to create backup: \(error)")
        }
    }
}

private func handleBackupExport(_ result: Result<URL, Error>) {
    switch result {
    case .success:
        print("Backup exported successfully")
    case .failure(let error):
        print("Backup export failed: \(error)")
    }
}
```

### Step 2: Update TranscriptionDetailView.swift

Open `TranscriptionDetailView.swift` and uncomment the file export functionality.

### Step 3: Build and Test

1. Press **⌘B** to build the project
2. Run the app (⌘R)
3. Test the new features:
   - Tap the menu (•••) and try "Import File"
   - Open a transcription and try "Export to File"
   - Try creating a backup with "Export Backup"

## 🎉 Features You'll Have

Once uncommented, your app will support:

### Export Features
- Export individual transcriptions as Plain Text, Markdown, or JSON
- Share files via system share sheet
- Save directly to Files app

### Import Features
- Import .txt, .md, or .json files
- Automatic format detection
- Metadata preservation

### Backup Features
- Create complete backups of all transcriptions
- Restore from backup files
- JSON-based backup format

## 📱 How to Use

### Export a Transcription
1. Open any transcription
2. Tap share button (↑)
3. Select "Export to File"
4. Choose format and destination

### Import a File
1. Tap menu (•••) in main list
2. Select "Import File"
3. Choose "Import Single File"
4. Select file from Files app

### Create/Restore Backup
1. Tap menu (•••) in main list
2. Select "Export Backup" to create
3. Select "Import File" → "Import Backup" to restore

## 🐛 Known Warnings (Non-Critical)

The following warnings in `SpeechTranscriptionManager.swift` are from existing code and don't affect the new features:
- Deprecated `exportAsynchronously` (iOS 18)
- Deprecated `status` property (iOS 18)
- Non-Sendable type capture

These relate to audio export functionality and can be fixed separately if needed.

## 🔧 Troubleshooting

**If you still see "Cannot find FileExportManager":**
1. Make sure all files are added to the Xcode project (not just the file system)
2. Check that files show in Project Navigator without red icons
3. Verify files are in the correct target (check File Inspector)
4. Clean build folder (⇧⌘K) and rebuild (⌘B)

**If imports fail:**
1. Make sure `UniformTypeIdentifiers` framework is available
2. Check deployment target is iOS 17.0+

## 📚 Additional Resources

- **SYSTEM_FILES_INTEGRATION.md** - Complete feature documentation
- **CODE_EXAMPLES.md** - Usage examples and best practices
- **ARCHITECTURE_DIAGRAM.md** - System architecture diagrams
- **IMPLEMENTATION_SUMMARY.md** - Technical details

---

**You're almost done!** Just uncomment the code in ContentView.swift and you'll have full system files integration! 🚀
