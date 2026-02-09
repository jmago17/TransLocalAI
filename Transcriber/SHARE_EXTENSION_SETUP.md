# Setting Up Share Extension for Transcriber App

To enable sharing audio files from other apps directly to your Transcriber app, you'll need to create a Share Extension target.

## Steps to Add Share Extension:

### 1. Add Share Extension Target
1. In Xcode, go to File > New > Target
2. Choose "Share Extension" under iOS
3. Name it "TranscriberShare"
4. Click Finish

### 2. Configure the Share Extension

Edit the `Info.plist` in your Share Extension target to accept audio files:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsFileWithMaxCount</key>
            <integer>1</integer>
            <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
            <integer>0</integer>
            <key>NSExtensionActivationSupportsWebPageWithMaxCount</key>
            <integer>0</integer>
            <key>NSExtensionActivationSupportsImageWithMaxCount</key>
            <integer>0</integer>
            <key>NSExtensionActivationSupportsMovieWithMaxCount</key>
            <integer>1</integer>
            <key>NSExtensionActivationSupportsText</key>
            <false/>
        </dict>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
</dict>
```

### 3. Create ShareViewController

Replace the default ShareViewController.swift with this code:

```swift
import UIKit
import Social
import UniformTypeIdentifiers
import SwiftData

class ShareViewController: UIViewController {
    
    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transcription.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedAudio()
    }
    
    private func handleSharedAudio() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { [weak self] url, error in
                guard let self = self, let url = url else {
                    self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    return
                }
                
                // Copy the file to app group container
                self.copyToAppContainer(url: url)
            }
        } else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    private func copyToAppContainer(url: URL) {
        do {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsDirectory.appendingPathComponent("shared-\(UUID().uuidString).\(url.pathExtension)")
            
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            // Save a pending transcription
            let transcription = Transcription(
                title: "Shared: \(url.deletingPathExtension().lastPathComponent)",
                transcriptionText: "Pending transcription...",
                language: "en-US",
                duration: 0,
                audioFileURL: destinationURL.lastPathComponent
            )
            
            let context = sharedModelContainer.mainContext
            context.insert(transcription)
            try context.save()
            
            // Complete the share
            DispatchQueue.main.async { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        } catch {
            print("Failed to copy file: \(error)")
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
```

### 4. Enable App Groups (Optional but Recommended)

For better data sharing between the main app and the share extension:

1. In both targets (main app and share extension), enable App Groups capability
2. Create an app group like: `group.com.yourcompany.transcriber`
3. Update ModelConfiguration to use the app group container:

```swift
let modelConfiguration = ModelConfiguration(
    schema: schema,
    url: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourcompany.transcriber")!
        .appendingPathComponent("Transcriber.sqlite"),
    isStoredInMemoryOnly: false
)
```

### 5. Handle Pending Transcriptions

In your main app, add logic to detect and transcribe files that were shared but not yet transcribed (those with "Pending transcription..." text).

## Note

The Share Extension is an advanced feature. Start with the main app functionality first (record and import), then add the share extension once the core features are working well.
```
