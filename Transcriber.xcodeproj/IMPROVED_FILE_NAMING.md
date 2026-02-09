# Improved File Naming

## What Changed

The app now preserves original filenames instead of replacing them with random UUIDs, making it much easier to identify imported audio files.

## Before vs After

### Before:
**Filename**: `import-A3B5C7D9-1234-5678-ABCD-123456789ABC.m4a`  
**Title**: `Imported: import-A3B5C7D9-1234-5678-ABCD-123456789ABC`  
❌ Impossible to identify the original file  
❌ Meaningless title in the list  

### After:
**Filename**: `Meeting-Notes-1702677600.m4a`  
**Title**: `Meeting Notes`  
✅ Can identify the file by name  
✅ Clean, readable title  

## How It Works

### File Naming Strategy:

When you import a file called `"Meeting Notes.m4a"`:

1. **Original name preserved**: `Meeting Notes`
2. **Spaces replaced with dashes**: `Meeting-Notes`
3. **Timestamp added** (to avoid conflicts): `Meeting-Notes-1702677600`
4. **Extension preserved**: `.m4a`
5. **Final filename**: `Meeting-Notes-1702677600.m4a`

### Title Generation:

The title shown in the app is cleaned up:

1. **Remove timestamp**: `Meeting-Notes-1702677600` → `Meeting-Notes`
2. **Replace dashes with spaces**: `Meeting-Notes` → `Meeting Notes`
3. **Capitalize**: `Meeting Notes` → `Meeting Notes`
4. **Final title**: `Meeting Notes`

## Examples

| Original File | Saved As | Title in App |
|--------------|----------|--------------|
| `Interview John.m4a` | `Interview-John-1702677600.m4a` | `Interview John` |
| `voice memo 123.m4a` | `voice-memo-123-1702677601.m4a` | `Voice Memo 123` |
| `Spanish Lesson.mp3` | `Spanish-Lesson-1702677602.mp3` | `Spanish Lesson` |
| `Call Recording.wav` | `Call-Recording-1702677603.wav` | `Call Recording` |

## Why Add Timestamps?

The timestamp (Unix epoch time) ensures:
- ✅ **No filename conflicts**: Import the same file multiple times without errors
- ✅ **Chronological sorting**: Files can be sorted by timestamp if needed
- ✅ **Unique identifiers**: Each import is uniquely identifiable

## Benefits

### For Users:
✅ **Recognizable filenames**: Easy to identify files in backups or file managers  
✅ **Clean titles**: Beautiful, readable titles in the app  
✅ **No confusion**: Know exactly which file is which  

### For Developers:
✅ **Better debugging**: Can identify files in logs  
✅ **Easier file management**: Filenames make sense  
✅ **No conflicts**: Timestamp prevents duplicate filename issues  

## Technical Details

### Import Flow:
1. User selects file: `"My Audio.m4a"`
2. App sanitizes name: `"My-Audio"`
3. App adds timestamp: `"My-Audio-1702677600"`
4. App saves with extension: `"My-Audio-1702677600.m4a"`
5. App creates transcription with clean title: `"My Audio"`

### Shortcuts Integration:
Shortcuts also preserve filenames! When you use the "Transcribe and Save" intent:
- Uses `audioFile.filename` if available
- Falls back to the `title` parameter
- Same naming strategy applied

### Character Handling:
- **Spaces** → Replaced with dashes
- **Special characters** → Preserved (but may cause issues on some systems)
- **Extensions** → Always preserved from original file

## Future Improvements

Possible enhancements:
- Remove special characters for better compatibility
- Add date prefix option (e.g., `2024-12-15-Meeting-Notes`)
- Custom naming patterns
- Option to use just original name (no timestamp)
- Automatic duplicate detection before import

## Files Modified

1. ✅ **ImportAudioView.swift**
   - Updated `handleFileSelection()` to preserve original filename
   - Added smart title generation from filename
   - Removes timestamp from displayed title

2. ✅ **TranscribeAndSaveIntent.swift**
   - Updated to use original filename from `audioFile.filename`
   - Falls back to title parameter if filename unavailable
   - Same naming strategy as import

## Testing

After this update:

1. **Import a file** named "Test Recording.m4a"
2. **Check the title** in the app → Should show "Test Recording"
3. **Check the filename** in documents directory → Should be "Test-Recording-[timestamp].m4a"
4. **Import the same file again** → Should create new file with different timestamp
5. **Use shortcuts** → Should also preserve filenames

---

**Your files now have meaningful names!** 🎉
