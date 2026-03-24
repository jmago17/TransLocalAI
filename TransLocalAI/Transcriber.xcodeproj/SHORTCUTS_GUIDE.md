# Transcriber App Shortcuts

Your Transcriber app now supports Shortcuts! This allows you to transcribe audio files from anywhere in iOS using Siri, the Shortcuts app, or automation.

## Available Shortcuts

### 1. **Transcribe Audio** 
Transcribes an audio file and returns the text. Perfect for quick transcriptions without saving to the app.

**Parameters:**
- **Audio File**: The audio file to transcribe (required)
- **Language**: The language of the audio (default: "en-US")

**Returns:** The transcribed text as a string

**Use Cases:**
- Quick transcription to clipboard
- Process audio in automation workflows
- Extract text without cluttering your library

### 2. **Transcribe and Save**
Transcribes an audio file and saves it to your Transcriber library for later access.

**Parameters:**
- **Audio File**: The audio file to transcribe (required)
- **Title**: Custom title for the transcription (default: "Shortcut Transcription")
- **Language**: The language of the audio (default: "en-US")

**Returns:** Confirmation message

**Use Cases:**
- Save transcriptions from Voice Memos
- Process files from cloud storage
- Automate transcription workflows

## How to Use

### Method 1: Using Siri

Simply say:
- "Hey Siri, transcribe audio with Transcriber"
- "Hey Siri, transcribe and save with Transcriber"

Siri will ask you for the audio file and process it.

### Method 2: In the Shortcuts App

1. Open the **Shortcuts** app
2. Tap **"+"** to create a new shortcut
3. Search for **"Transcribe"**
4. Add either action:
   - **Transcribe Audio** - Returns text only
   - **Transcribe and Save** - Saves to app library
5. Configure the parameters
6. Run the shortcut!

### Method 3: Building Automation Workflows

#### Example 1: Transcribe Voice Memos Automatically

```
When: Voice Memo is recorded
1. Get latest Voice Memo
2. Transcribe Audio (Transcriber)
3. Copy to Clipboard
4. Show notification "Transcription ready!"
```

#### Example 2: Transcribe Files from iCloud

```
1. Get File from iCloud Drive
2. Transcribe and Save (Transcriber)
   - Set custom title
   - Set language
3. Show result
```

#### Example 3: Share Sheet Extension

```
When: File is shared with Shortcuts
1. Receive File input
2. Transcribe Audio (Transcriber)
3. Share transcription via Messages/Email
```

## Supported Languages

- English (US) - "en-US"
- Spanish (Spain) - "es-ES"

## Supported Audio Formats

- M4A
- MP3
- WAV
- AAC
- Any format supported by iOS AVFoundation

## Tips

1. **Internet Required**: Speech recognition requires an active internet connection
2. **File Size**: Large files (>1 minute) are automatically split into chunks
3. **Permissions**: First use will request Speech Recognition permission
4. **Language**: Make sure to specify the correct language for best results

## Example Shortcuts

### Quick Transcription to Clipboard

```
1. Select File
2. Transcribe Audio (File, "en-US")
3. Copy to Clipboard
```

### Batch Process Multiple Files

```
1. Get Files from Folder
2. Repeat with Each File:
   - Transcribe and Save (File, File Name, "en-US")
3. Show "Processed X files"
```

### Voice Memo to Note

```
1. Get Latest Voice Memo
2. Transcribe Audio (Voice Memo, "en-US")
3. Create Note (Transcription)
```

## Troubleshooting

**"Permission Denied" Error**
- Go to Settings → Transcriber → Enable Speech Recognition

**"Transcription Failed" Error**
- Check internet connection
- Verify audio file format is supported
- Check file isn't corrupted

**Shortcuts Not Appearing**
- Rebuild and reinstall the app
- Check Shortcuts app → Search for "Transcriber"

## Privacy

All transcriptions use Apple's Speech Recognition framework:
- On-device when available
- Server-based (Apple servers only) for longer files
- No third-party services involved
- Your audio is not stored by Apple after processing
