# Transcriber App - iOS Audio Transcription
# Transcriber

A native iOS app that transcribes audio files in multiple languages using Apple's Speech Recognition framework.

## Features

✅ **Audio Import**
- Import audio files from Voice Memos, Files app, or any source
- Support for multiple audio formats (MP3, M4A, WAV, AAC, etc.)
- Automatic transcription of imported files
- Handles large files with intelligent chunking

✅ **Smart Transcription**
- Server-based transcription using Apple's Speech framework
- Support for English (US) and Spanish (Spain)
- Automatic chunking for long audio files (>1 minute)
- Privacy-focused - only Apple's servers are used

✅ **App Shortcuts Integration**
- Transcribe audio files via Siri
- Automate transcription workflows
- Search and retrieve transcriptions
- Share transcriptions across apps

✅ **Data Management**
- SwiftData persistence for all transcriptions
- Edit transcription titles and text
- Search through transcriptions
- Share transcriptions as text
- Delete transcriptions and associated audio files

## Project Structure

### Core Files

- **ContentView.swift** - Main list view showing all transcriptions
- **Item.swift** - SwiftData model for storing transcriptions
- **TranscriberApp.swift** - App entry point with SwiftData container

### Transcription

- **SpeechTranscriptionManager.swift** - Manages speech-to-text using Speech framework with chunking support
- **ImportAudioView.swift** - UI for importing audio files

### App Intents & Shortcuts

- **TranscribeAudioIntent.swift** - Shortcut action to transcribe audio files
- **TranscribeAndSaveIntent.swift** - Shortcut action to transcribe and save to library
- **GetRecentTranscriptionsIntent.swift** - Shortcut actions for retrieving and searching transcriptions

### Display & Editing

- **TranscriptionDetailView.swift** - View and edit individual transcriptions

### Documentation

- **INFO_PLIST_REQUIREMENTS.md** - Required permissions setup
- **SHARE_EXTENSION_SETUP.md** - Future: how to add share extension support

## Setup Instructions

### 1. Required Permissions

Add these keys to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to your microphone to record audio for transcription.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition access to transcribe your audio recordings into text.</string>
```

### 2. Build and Run

1. Open the project in Xcode
2. Select your target device or simulator (iOS 17.0+)
3. Build and run (⌘R)

### 3. First Launch

On first launch, the app will request:
- Microphone permission (for recording)
- Speech recognition permission (for transcription)

Both permissions are required for full functionality.

## Usage

### Recording Audio

1. Tap the "+" button in the navigation bar
2. Select "Record Audio"
3. Choose your transcription language (English or Spanish)
4. Tap the Record button to start recording
5. Tap Stop when finished
6. Tap "Transcribe Audio" to convert speech to text
7. The transcription will be saved and appear in your list

### Importing Audio Files

1. Tap the "+" button in the navigation bar
2. Select "Import Audio File"
3. Choose your transcription language
4. Tap "Choose Audio File" and select a file
5. Tap "Start Transcription"
6. Wait for processing to complete

### Viewing & Editing

1. Tap any transcription in the list
2. View the full text and metadata
3. Tap "Edit" to modify the title or transcription text
4. Use the share button to export the text

### Searching

Use the search bar at the top to find transcriptions by title or content.

## Technical Details

### Frameworks Used

- **SwiftUI** - Modern declarative UI
- **SwiftData** - Data persistence
- **AVFoundation** - Audio recording
- **Speech** - On-device speech recognition
- **UniformTypeIdentifiers** - File type handling

### Language Support

The app supports on-device transcription for:
- English (US)
- English (UK)
- Spanish (Spain)
- Spanish (Mexico)

Note: Available languages may vary by device and iOS version.

### Privacy & Security

- All transcription happens on-device
- No data is sent to external servers
- Audio files are stored locally in the app's documents directory
- Users have full control over their data

## Future Enhancements

- [ ] Share Extension for transcribing files from other apps
- [ ] Real-time transcription during recording
- [ ] Export transcriptions as PDF or other formats
- [ ] Support for additional languages
- [ ] Audio playback from within the app
- [ ] Batch transcription of multiple files
- [ ] iCloud sync across devices
- [ ] Transcription accuracy confidence scores
- [ ] Speaker identification (diarization)
- [ ] Timestamps for transcription segments

## Requirements

- iOS 17.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later
- Device with microphone (for recording)

## Notes

### On-Device vs Server-Based Recognition

This app uses `requiresOnDeviceRecognition = true` to ensure all processing happens locally. This means:
- ✅ Works offline
- ✅ Better privacy
- ✅ No data usage
- ⚠️ May be less accurate than server-based recognition
- ⚠️ Limited to languages with on-device support

### Audio File Storage

Recorded and imported audio files are stored in the app's Documents directory. Each transcription references its audio file, and files are automatically deleted when transcriptions are removed.

## Troubleshooting

**"Speech recognition not available"**
- Ensure you've granted speech recognition permission
- Check that your device supports on-device recognition
- Some older devices may not support all languages

**"Microphone permission denied"**
- Go to Settings > Privacy & Security > Microphone
- Enable permission for Transcriber

**Poor transcription quality**
- Ensure clear audio with minimal background noise
- Speak clearly and at a moderate pace
- Try recording in a quiet environment
- Check that you've selected the correct language

## License

This is a sample project for educational purposes.
