//
//  TranscriberApp.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct TranscriberApp: App {
    static let bgTaskIdentifier = "com.josumartinez.transcriber.transcription"

    /// Holds the current BGContinuedProcessingTask so ImportAudioView can mark it complete.
    @MainActor static var currentBGTask: BGContinuedProcessingTask?
    /// Called when the BG task expires — ImportAudioView sets this to cancel the transcription.
    @MainActor static var onBGTaskExpiration: (() -> Void)?

    var sharedModelContainer: ModelContainer = {
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    importPendingTranscriptions()
                    registerBackgroundTask()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            // Store the task so ImportAudioView can call setTaskCompleted
            Task { @MainActor in
                TranscriberApp.currentBGTask = bgTask
            }

            bgTask.expirationHandler = {
                // System is reclaiming background time — cancel the transcription gracefully
                Task { @MainActor in
                    TranscriberApp.onBGTaskExpiration?()
                    TranscriberApp.currentBGTask = nil
                    TranscriberApp.onBGTaskExpiration = nil
                }
                bgTask.setTaskCompleted(success: false)
            }
        }
    }

    /// Import transcriptions created by the Share Extension
    private func importPendingTranscriptions() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.josumartinez.transcriber"
        ) else {
            return
        }

        let pendingDirectory = containerURL.appendingPathComponent("PendingTranscriptions", isDirectory: true)
        let audioDirectory = containerURL.appendingPathComponent("SharedAudio", isDirectory: true)

        guard FileManager.default.fileExists(atPath: pendingDirectory.path) else {
            return
        }

        do {
            let pendingFiles = try FileManager.default.contentsOfDirectory(
                at: pendingDirectory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }

            let context = sharedModelContainer.mainContext

            for file in pendingFiles {
                do {
                    let data = try Data(contentsOf: file)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }

                    let title = json["title"] as? String ?? "Shared Transcription"
                    let text = json["text"] as? String ?? ""
                    let language = json["language"] as? String ?? "en-US"
                    let duration = json["duration"] as? TimeInterval ?? 0
                    let audioFileName = json["audioFile"] as? String
                    let timestamp = json["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970

                    // Copy audio to app's documents directory if exists
                    var savedAudioFileName: String? = nil
                    if let audioFileName = audioFileName {
                        let sourceAudioURL = audioDirectory.appendingPathComponent(audioFileName)
                        if FileManager.default.fileExists(atPath: sourceAudioURL.path) {
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let destAudioURL = documentsDirectory.appendingPathComponent(audioFileName)
                            try? FileManager.default.copyItem(at: sourceAudioURL, to: destAudioURL)
                            savedAudioFileName = audioFileName
                            // Clean up shared audio
                            try? FileManager.default.removeItem(at: sourceAudioURL)
                        }
                    }

                    // Create transcription
                    let transcription = Transcription(
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        title: title,
                        transcriptionText: text,
                        language: language,
                        duration: duration,
                        audioFileURL: savedAudioFileName
                    )

                    context.insert(transcription)

                    // Remove processed pending file
                    try? FileManager.default.removeItem(at: file)

                } catch {
                    print("Failed to process pending transcription: \(error)")
                }
            }

            try? context.save()

        } catch {
            print("Failed to read pending directory: \(error)")
        }
    }
}

