# Auto Language Detection Feature

## Overview

The app now includes **automatic language detection**! The system will analyze the audio and determine whether it's English or Spanish before transcribing.

## How It Works

### Detection Process:
1. **Audio Analysis** - The first few seconds of audio are tested with each supported language
2. **Confidence Scoring** - Each language receives a confidence score based on recognition quality
3. **Best Match Selection** - The language with the highest confidence is selected
4. **Transcription** - The full audio is transcribed using the detected language

## User Interface

### Import Audio View:

**Toggle Control:**
```
Auto-detect language: [ON/OFF]
```

**When Auto-detect is ON:**
- No language picker shown
- Shows message: "Language will be automatically detected"
- Detection happens automatically during transcription

**When Auto-detect is OFF:**
- Segmented control appears with manual language selection
- User chooses: English (US) or Spanish (Spain)

### Progress Indicators:

**During Detection:**
```
🔄 Detecting language...
   Analyzing audio to determine the best language
```

**During Transcription:**
```
🔄 Transcribing audio...
   This may take a few moments
```

## App Shortcuts Integration

Both shortcut actions now support auto-detection!

### Transcribe Audio Intent:
- **Auto-detect Language** parameter (default: ON)
- **Language** parameter (used if auto-detect is OFF)

**Smart Parameter Summary:**
- When auto-detect ON: "Transcribe [file] with auto-detected language"
- When auto-detect OFF: "Transcribe [file] in [language]"

### Transcribe and Save Intent:
- Same auto-detection parameters
- Saves the detected language with the transcription

## Technical Implementation

### Files Modified:

1. **SpeechTranscriptionManager.swift**
   - Added `detectLanguage(audioURL:)` method
   - Tests each supported language
   - Returns best match based on confidence scores

2. **ImportAudioView.swift**
   - Added auto-detect toggle
   - Added language detection progress indicator
   - Conditional UI based on auto-detect setting

3. **TranscribeAudioIntent.swift**
   - Added `autoDetect` parameter
   - Smart parameter summary
   - Auto-detection in perform method

4. **TranscribeAndSaveIntent.swift**
   - Added `autoDetect` parameter
   - Saves detected language with transcription

## Benefits

✅ **Better User Experience**
- No need to manually select language
- Reduces cognitive load
- One less decision to make

✅ **More Accurate**
- System chooses the best language match
- Based on actual audio analysis
- Reduces transcription errors from wrong language

✅ **Flexible**
- Can still manually select language if needed
- Useful for mixed-language content
- Power users have control

✅ **Shortcuts Integration**
- Automation workflows don't need language specification
- "Just transcribe this" - system handles the rest

## Default Behavior

**Default: Auto-detect is ON**

Most users will never need to turn it off. The app will automatically:
1. Detect if audio is English or Spanish
2. Use the appropriate language for transcription
3. Save the detected language with the transcription

## Use Cases

### When Auto-detect is Perfect:
- ✅ Single-language audio files
- ✅ Clear, distinct English or Spanish
- ✅ Quick transcriptions
- ✅ Shortcut automations

### When Manual Selection is Better:
- ⚠️ Mixed-language content (choose dominant language)
- ⚠️ Very short audio clips (detection may be uncertain)
- ⚠️ Heavy accents or unclear audio
- ⚠️ You know the language and want to skip detection

## Testing

Test both scenarios:

1. **Auto-detect ON:**
   - Import English audio → Should detect "en-US"
   - Import Spanish audio → Should detect "es-ES"
   - Check progress shows "Detecting language..."

2. **Auto-detect OFF:**
   - Toggle off auto-detect
   - Segmented control appears
   - Select language manually
   - No detection step happens

3. **Shortcuts:**
   - Use shortcuts with auto-detect enabled
   - Verify it works with voice memos
   - Check saved transcriptions have correct language

## Performance Notes

- **Detection time:** ~3-5 seconds (analyzes first portion of audio)
- **Total time:** Detection + Transcription (slightly longer than manual selection)
- **Worth it:** More accurate transcriptions make it worthwhile
- **Can be skipped:** Toggle off for speed if you know the language

## Future Enhancements

Possible improvements:
- Support more languages (French, German, etc.)
- Detect multiple languages in same audio
- Language confidence indicator in UI
- Remember user's preference per source

---

**This feature makes the app truly "smart" - it just works without user intervention!**
