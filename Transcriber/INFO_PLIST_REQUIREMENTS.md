# Required Info.plist Keys for Transcriber App

Add this key to your Info.plist file:

## Privacy - Speech Recognition Usage Description
Key: `NSSpeechRecognitionUsageDescription`
Value: "This app needs speech recognition access to transcribe your audio recordings into text."

---

## How to add this to your project:

1. Open your project in Xcode
2. Select your app target
3. Go to the "Info" tab
4. Click the "+" button to add new entries
5. Add the privacy key with its description

Alternatively, you can edit the Info.plist file directly in XML format:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition access to transcribe your audio recordings into text.</string>

