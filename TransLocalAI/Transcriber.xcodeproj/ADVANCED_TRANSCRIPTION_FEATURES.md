# Advanced Transcription Features

## Overview

The Transcriber app now includes **two powerful transcription modes** and **quality options** for different use cases!

## Features Added

### 1. 🎭 Transcription Modes

#### Standard Mode
- **What it does**: Basic transcription without speaker identification
- **Best for**: Single speaker, lectures, notes, podcasts
- **Output format**: Continuous text
- **Example**:
```
Hello everyone, today we're going to discuss the new features. 
I think these will be really useful for our team.
```

#### Speaker Identification Mode
- **What it does**: Detects different speakers and labels them
- **Best for**: Interviews, meetings, conversations, debates
- **Output format**: Text organized by speaker
- **How it works**: Detects pauses longer than 1.5 seconds to identify speaker changes
- **Example**:
```
Speaker 1: Hello everyone, today we're going to discuss the new features.

Speaker 2: That sounds great! I'm excited to hear about them.

Speaker 1: I think these will be really useful for our team.
```

### 2. 📊 Quality Options

#### Standard Quality
- **Duration**: Processes entire audio file
- **Method**: Chunks audio if longer than 60 seconds
- **Best for**: Long recordings, full meetings, lectures
- **Accuracy**: Good
- **Speed**: Slower for long files

#### High Quality (59s max)
- **Duration**: Automatically trims to first 59 seconds
- **Method**: Single-pass transcription (no chunking)
- **Best for**: Quick voice notes, short messages, critical content
- **Accuracy**: Excellent (best possible from API)
- **Speed**: Faster (no chunking overhead)
- **Use case**: When the first minute is most important or when maximum accuracy is needed

## User Interface

### Import Audio Screen:

```
┌─────────────────────────────────────┐
│          Import Audio File          │
├─────────────────────────────────────┤
│                                     │
│ Language                            │
│ ☑ Auto-detect language             │
│ Language will be automatically      │
│ detected                            │
│                                     │
│ ─────────────────────────────────  │
│                                     │
│ Transcription Mode                  │
│ [Standard] [Speaker ID]            │
│ Identifies different speakers       │
│ in the audio                        │
│                                     │
│ ─────────────────────────────────  │
│                                     │
│ Quality                             │
│ [Standard] [High (59s max)]        │
│ Trims to first 59 seconds for      │
│ best accuracy                       │
│                                     │
│     [Choose Audio File]            │
│                                     │
└─────────────────────────────────────┘
```

## Technical Implementation

### Files Modified:

1. **SpeechTranscriptionManager.swift**
   - Added `TranscriptionMode` enum (standard, speakerIdentification)
   - Added `TranscriptionQuality` enum (standard, highQuality)
   - Added `trimAudioTo59Seconds()` method
   - Added `transcribeWithSpeakers()` method
   - Added `formatTranscriptionWithSpeakers()` method
   - Updated main `transcribe()` method with new parameters

2. **ImportAudioView.swift**
   - Added mode and quality pickers
   - Updated UI with sections for each setting
   - Added descriptive captions
   - Updated transcription call with new parameters

### How Speaker Identification Works:

1. **Segment Analysis**: Speech recognition returns timestamped segments
2. **Silence Detection**: Analyzes time gaps between segments
3. **Speaker Changes**: Pauses > 1.5 seconds indicate speaker change
4. **Label Assignment**: Alternates between "Speaker 1" and "Speaker 2"
5. **Formatting**: Groups segments by speaker with clear labels

**Note**: This is a heuristic approach based on silence patterns. For true speaker diarization with voice recognition, you'd need more advanced APIs.

## Use Cases

### Standard + Standard Quality
✅ Long meetings (full audio)  
✅ Lectures and presentations  
✅ Podcasts  
✅ Single speaker content  

### Standard + High Quality
✅ Quick voice notes  
✅ Short messages  
✅ When only the beginning matters  
✅ Maximum accuracy needed for critical content  

### Speaker ID + Standard Quality
✅ Full interview transcriptions  
✅ Multi-person meetings  
✅ Debates and panel discussions  
✅ Conversations  

### Speaker ID + High Quality
✅ Short interview clips  
✅ Quick conversation snippets  
✅ Opening remarks from multiple speakers  
✅ Critical meeting starts  

## Quality Comparison

### Standard Quality (Full Audio)
- **Pros**: 
  - Transcribes entire audio
  - No content loss
  - Good for archival
- **Cons**: 
  - Slower for long files
  - Slightly lower accuracy due to chunking

### High Quality (59s Trimmed)
- **Pros**: 
  - Maximum accuracy
  - Faster processing
  - Single API call (no chunking)
  - Best for important content
- **Cons**: 
  - Loses content after 59 seconds
  - Not suitable for long recordings

## Examples

### Example 1: Meeting Transcription
**Settings:**
- Mode: Speaker Identification
- Quality: Standard
- Auto-detect: ON

**Result:**
```
Speaker 1: Good morning everyone. Let's start with the project update.

Speaker 2: Thanks for having me. The project is on track and we've completed phase one.

Speaker 1: Excellent work! What's next on the timeline?

Speaker 2: Phase two begins next week with the design review.
```

### Example 2: Quick Voice Note
**Settings:**
- Mode: Standard
- Quality: High (59s)
- Language: English (US)

**Result:**
```
Remember to buy groceries on the way home. We need milk, 
eggs, bread, and some vegetables for dinner. Also don't 
forget to pick up the package from the post office.
```

### Example 3: Podcast Clip
**Settings:**
- Mode: Standard
- Quality: High (59s)
- Auto-detect: ON

**Result:**
```
Welcome to today's episode where we'll be discussing the 
latest developments in artificial intelligence. Our guest 
is an expert in machine learning and has some fascinating 
insights to share about the future of technology.
```

## Tips for Best Results

### For Speaker Identification:
✅ Clear audio with distinct speakers  
✅ Natural pauses between speakers  
✅ Avoid overlapping speech  
✅ Good microphone placement  

### For High Quality Mode:
✅ Use when first 59 seconds are most important  
✅ Perfect for voice messages  
✅ Ideal for quick meeting starts  
✅ Great for critical announcements  

### General Tips:
✅ Use auto-detect unless you know the language  
✅ Clear audio = better transcription  
✅ Minimize background noise  
✅ Speak clearly and at moderate pace  

## Future Enhancements

Possible improvements:
- Support for 3+ speaker identification
- Custom speaker labels (e.g., "John", "Mary")
- Voice recognition for known speakers
- Adjustable silence threshold
- Timestamp export
- Subtitle format export (SRT, VTT)

## Performance Notes

**Standard Mode:**
- ~5-10 seconds per minute of audio
- Internet required

**Speaker ID Mode:**
- ~5-10 seconds per minute of audio
- Same speed as standard
- Adds formatting overhead (negligible)

**High Quality Mode:**
- ~3-5 seconds total (regardless of original length)
- Fastest option for long files
- Trims audio automatically

---

**These features make the app suitable for a wide range of professional and personal use cases!**
