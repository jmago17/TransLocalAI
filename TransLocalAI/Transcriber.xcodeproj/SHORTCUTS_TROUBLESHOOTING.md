# Troubleshooting: Shortcuts Not Appearing

## Quick Fixes (Try These First)

### Fix 1: Complete Reinstall
This fixes 90% of cases:

1. **Delete the app** completely from your iPhone
   - Long-press app icon → Remove App → Delete App
2. In Xcode: **Product → Clean Build Folder** (Shift + Cmd + K)
3. Close Xcode completely
4. Delete Derived Data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Transcriber-*
   ```
5. Reopen Xcode
6. **Build and Run** (Cmd + R)
7. Wait 30-60 seconds after app launches
8. Open Shortcuts app
9. Search for "Transcriber"

### Fix 2: Verify Target Membership

In Xcode:
1. Select these files in Project Navigator:
   - `TranscribeAudioIntent.swift`
   - `TranscribeAndSaveIntent.swift`
   - `GetRecentTranscriptionsIntent.swift`

2. For EACH file:
   - Open File Inspector (right sidebar, first tab)
   - Under "Target Membership"
   - Ensure "Transcriber" is checked ✅

3. If not checked, check the box
4. Clean and rebuild

### Fix 3: Check iOS Version

App Intents require **iOS 16.0 or later**

Check your iPhone:
- Settings → General → About → Software Version
- Must be iOS 16.0+

If you're on iOS 15 or earlier, the shortcuts won't appear.

### Fix 4: Wait and Restart

Sometimes iOS needs time to index:

1. Install the app
2. Wait 2-3 minutes
3. **Restart your iPhone**
4. Wait another minute
5. Open Shortcuts app
6. Search for "Transcriber"

### Fix 5: Reset Shortcuts Database

On your iPhone:
1. Go to Settings → Shortcuts
2. Toggle off "Allow Running Scripts"
3. Wait 10 seconds
4. Toggle it back on
5. Restart iPhone
6. Try again

## Detailed Diagnostics

### Step 1: Verify Files Are in Project

In Xcode Project Navigator, you should see:
- ✅ TranscribeAudioIntent.swift
- ✅ TranscribeAndSaveIntent.swift
- ✅ GetRecentTranscriptionsIntent.swift

If missing, they weren't added to the project properly.

### Step 2: Check Build Phases

1. Select Transcriber project
2. Select Transcriber target
3. Go to "Build Phases" tab
4. Expand "Compile Sources"
5. Verify these files are listed:
   - TranscribeAudioIntent.swift
   - TranscribeAndSaveIntent.swift
   - GetRecentTranscriptionsIntent.swift

If not listed, add them:
- Click "+" button
- Add the missing files

### Step 3: Verify Info.plist Keys

The app needs these permissions:
- `NSSpeechRecognitionUsageDescription`

Make sure it's set in:
- Target → Info tab → Custom iOS Target Properties

### Step 4: Check Deployment Target

1. Select Transcriber target
2. Go to General tab
3. Under "Deployment Info"
4. Minimum Deployments should be iOS 16.0 or higher

### Step 5: Verify Scheme

1. Product → Scheme → Edit Scheme
2. Select "Run" on left
3. Go to "Info" tab
4. Build Configuration should be "Debug"
5. Click "Close"

## Advanced Fixes

### Check AppIntents Metadata

Add this environment variable to see debug info:

1. Product → Scheme → Edit Scheme
2. Select "Run"
3. Go to "Arguments" tab
4. Under "Environment Variables", add:
   - Name: `APP_INTENTS_METADATA_DEBUG`
   - Value: `1`
5. Run app
6. Check Xcode console for AppIntents messages

### Verify Signing

1. Select Transcriber target
2. Go to "Signing & Capabilities"
3. Ensure "Automatically manage signing" is ON
4. A team should be selected
5. No signing errors should appear

### Check for Build Errors

1. Press Cmd + B to build
2. Check Issue Navigator (Cmd + 5)
3. Fix any errors or warnings related to AppIntents
4. Clean and rebuild

## Still Not Working?

### Option 1: Manual Intent Registration

Try explicitly importing in your main app file:

```swift
// In TranscriberApp.swift
import AppIntents

@main
struct TranscriberApp: App {
    init() {
        // Force registration
        _ = TranscriberShortcuts.self
    }
    
    // ... rest of app
}
```

### Option 2: Simplify First

Create a minimal test intent:

```swift
import AppIntents

struct TestIntent: AppIntent {
    static var title: LocalizedStringResource = "Test"
    static var description = IntentDescription("Test intent")
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct TestShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [AppShortcut(intent: TestIntent(), phrases: ["Test"], shortTitle: "Test", systemImageName: "star")]
    }
}
```

If this appears, the issue is with the complex intents.

### Option 3: Check System Logs

On Mac, with iPhone connected:

1. Open Console app
2. Select your iPhone
3. Filter for "appintents" or "shortcuts"
4. Install app and watch for errors

## Common Error Messages

### "App not trusted"
- Delete app
- Clean build
- Reinstall
- Trust developer certificate (Settings → General → VPN & Device Management)

### "Shortcuts not available"
- Check iOS version (must be 16+)
- Check internet connection (first launch may need it)
- Restart iPhone

### "Intent not found"
- Verify Target Membership
- Clean and rebuild
- Complete reinstall

## Verification Checklist

Before asking for help, verify:

- [ ] iOS 16.0 or later
- [ ] Files in Target Membership
- [ ] No build errors
- [ ] App completely deleted and reinstalled
- [ ] Derived Data cleaned
- [ ] Waited 60+ seconds after install
- [ ] iPhone restarted
- [ ] Shortcuts app searched for app name
- [ ] Signing configured correctly
- [ ] Deployment target set to iOS 16.0+

## Alternative: Test Without Shortcuts

The app should work fine without shortcuts! You can:
- Import files normally
- Transcribe through the app UI
- All features work

Shortcuts are a bonus feature, not required for core functionality.

## Contact Support Info

If nothing works, provide:
1. iOS version
2. Xcode version
3. macOS version
4. Build errors (if any)
5. Console logs with APP_INTENTS_METADATA_DEBUG=1
6. Screenshots of Target Membership

---

**Most Common Solution**: Complete reinstall (Fix 1) solves it 90% of the time!
