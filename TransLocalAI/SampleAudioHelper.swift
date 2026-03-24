//
//  SampleAudioHelper.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import Foundation

struct SampleAudioHelper {
    /// Copies a sample audio file from the app bundle to the documents directory
    /// Returns the URL of the copied file
    static func copySampleAudioToDocuments(fileName: String) -> URL? {
        guard let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            print("Sample audio file '\(fileName)' not found in bundle")
            return nil
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsDirectory.appendingPathComponent(fileName)
        
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: destinationURL)
        
        do {
            try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
            print("Successfully copied sample audio to: \(destinationURL.path)")
            return destinationURL
        } catch {
            print("Failed to copy sample audio: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Returns all sample audio files available in the bundle
    static var availableSampleAudios: [String] {
        let sampleFiles = ["sample-audio.m4a", "sample-recording.mp3", "test-audio.wav"]
        return sampleFiles.filter { fileName in
            Bundle.main.url(forResource: fileName, withExtension: nil) != nil
        }
    }
}
