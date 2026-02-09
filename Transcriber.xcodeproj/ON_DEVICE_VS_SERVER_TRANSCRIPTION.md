# On-Device vs Server Transcription

## Overview

The Transcriber app uses **server-based transcription** (Apple's cloud servers) for all transcriptions. This document explains why and what the differences are.

## Transcription Types

### On-Device Transcription
- **Processing**: Happens on your iPhone/iPad
- **Duration Limit**: ~1 minute maximum
- **Internet**: Not required
- **Privacy**: Most private (never leaves device)
- **Accuracy**: Good
- **Languages**: Limited support
- **Speed**: Fast (no network latency)

### Server-Based Transcription (What We Use)
- **Processing**: Happens on Apple's servers
- **Duration Limit**: No hard limit (we chunk long files)
- **Internet**: Required
- **Privacy**: Secure (Apple's servers only, encrypted)
- **Accuracy**: Excellent
- **Languages**: Better support
- **Speed**: Depends on connection

## Why Server-Based?

The app uses **server-based transcription** (`requiresOnDeviceRecognition = false`) because:

### ✅ Advantages:
1. **No 1-minute limit** - Can handle files of any length
2. **Better accuracy** - More powerful processing
3. **More reliable** - Better language models
4. **Chunking works** - Can split long files
5. **Speaker ID works** - Can process longer conversations

### ❌ If we used on-device:
1. **1-minute hard limit** - Longer files would fail with error 1107
2. **No chunking** - Can't split files reliably
3. **Limited languages** - Not all languages available on-device
4. **Storage requirements** - Requires downloaded language models

## How Our App Handles Long Files

### Standard Mode (>60 seconds):
```
Original audio: 5 minutes
↓
Split into chunks:
- Chunk 1: 0:00-0:55 → Transcribe
- Chunk 2: 0:55-1:50 → Transcribe
- Chunk 3: 1:50-2:45 → Transcribe
- Chunk 4: 2:45-3:40 → Transcribe
- Chunk 5: 3:40-4:35 → Transcribe
- Chunk 6: 4:35-5:00 → Transcribe
↓
Join all chunks → Final transcription
```

### Speaker ID Mode (>60 seconds):
```
Original audio: 5 minutes
↓
Split into chunks (same as above)
↓
Each chunk:
- Transcribe with speaker detection
- Maintain speaker numbers across chunks
- Format with "Speaker 1:", "Speaker 2:", etc.
↓
Join with proper speaker continuity
```

### High Quality Mode (<60 seconds):
```
Original audio: any length
↓
Trim to first 59 seconds
↓
Single transcription call → Best accuracy
```

## Privacy & Security

Even though we use server-based transcription:

✅ **Apple's servers only** - Not third-party  
✅ **Encrypted transmission** - HTTPS/TLS  
✅ **Not stored by Apple** - Processed and discarded  
✅ **No account linking** - Anonymous processing  
✅ **GDPR compliant** - Apple's privacy standards  

From Apple's documentation:
> "Audio data sent to Apple servers is not stored or shared. It is used only to provide the transcription service and is immediately discarded after processing."

## Error 1107 Explained

**Error 1107** = "Recognition request failed"

### Common Causes:
1. ❌ Trying on-device transcription >1 minute
2. ❌ No internet connection (for server-based)
3. ❌ Audio file corrupted or unsupported format
4. ❌ API rate limiting (too many requests)

### Our Fixes:
✅ Use server-based (no 1-minute limit)  
✅ Chunk files >60 seconds  
✅ Add delay between chunks (avoid rate limiting)  
✅ Fallback handling for errors  

## Current Implementation

### Standard Transcription:
- **≤60 seconds**: Single API call
- **>60 seconds**: Chunked (55s per chunk)
- **Mode**: Server-based
- **Result**: Complete transcription

### Speaker ID Transcription:
- **≤60 seconds**: Single API call with speaker detection
- **>60 seconds**: Chunked with continuous speaker tracking
- **Mode**: Server-based
- **Result**: Transcription with speaker labels

### High Quality Transcription:
- **Any length**: Trimmed to 59 seconds
- **Mode**: Server-based, single call
- **Result**: Maximum accuracy for first minute

## Internet Requirements

### When Internet is Needed:
- ✅ All transcriptions (server-based)
- ✅ Language detection
- ✅ Both modes (standard & speaker ID)
- ✅ All quality settings

### When Internet is NOT Needed:
- ✅ Playing recorded audio
- ✅ Viewing saved transcriptions
- ✅ Editing transcriptions
- ✅ Deleting transcriptions
- ✅ Searching transcriptions

## Performance Comparison

| Feature | On-Device | Server-Based (Our Choice) |
|---------|-----------|---------------------------|
| Max Duration | ~60 seconds | Unlimited (chunked) |
| Accuracy | Good | Excellent |
| Internet | Not required | Required |
| Privacy | Maximum | Very good |
| Speed | Fast | Good |
| Long files | ❌ Fails | ✅ Works |
| Speaker ID | Limited | ✅ Works |

## Future Possibilities

### Potential Hybrid Approach:
```
IF file ≤ 55 seconds AND on-device available:
    → Use on-device (faster, offline)
ELSE:
    → Use server-based (more capable)
```

### Benefits:
- ✅ Short files work offline
- ✅ Long files still work
- ✅ Best of both worlds

### Implementation:
```swift
if duration <= 55 && recognizer.supportsOnDeviceRecognition {
    request.requiresOnDeviceRecognition = true
} else {
    request.requiresOnDeviceRecognition = false
}
```

## Recommendations

### For Most Users:
✅ Current implementation (server-based) is best  
✅ Works reliably for all file lengths  
✅ Best accuracy  
✅ No configuration needed  

### For Offline Use:
⚠️ Record in Voice Memos while offline  
⚠️ Import and transcribe when online  
⚠️ Or use High Quality mode for <59s files  

### For Maximum Privacy:
⚠️ Use Voice Memos' built-in transcription  
⚠️ Then copy/paste to this app  
⚠️ (Voice Memos uses on-device when available)  

## Summary

**The app uses server-based transcription because:**
1. No 1-minute limitation
2. Can handle files of any length via chunking
3. Better accuracy and reliability
4. Speaker identification works for long files
5. More consistent user experience

**Trade-off**: Requires internet connection, but this is acceptable for most use cases since users typically transcribe when online anyway.

---

**Bottom line**: Server-based is the right choice for a transcription app that needs to handle real-world use cases like meetings, interviews, and lectures.
