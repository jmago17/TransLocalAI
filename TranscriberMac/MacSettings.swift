//
//  MacSettings.swift
//  TranscriberMac
//
//  User-selectable engines for the Mac processing pipeline + API key storage.
//  Engine choices live in the App Group UserDefaults; secrets in the Keychain.
//

import Foundation
import Security

enum TranscribeBackend: String, CaseIterable, Identifiable, Sendable {
    case appleSpeech      // SpeechAnalyzer / SpeechTranscriber (on-device, no download)
    case whisperKit       // WhisperKit (downloads a model once)
    case whisperCpp       // external whisper.cpp CLI (whisper-cli + ggml model)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .whisperKit:  return "WhisperKit"
        case .whisperCpp:  return "whisper.cpp (CLI)"
        }
    }
}

enum RedactBackend: String, CaseIterable, Identifiable, Sendable {
    case appleFoundation  // on-device Apple Foundation Models (default)
    case openAI           // OpenAI API
    case openAICLI        // shell out to a local `openai`/`chatgpt` style CLI
    case claudeCLI        // shell out to the `claude` CLI (the original pipeline)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleFoundation: return "Apple Foundation (local)"
        case .openAI:          return "OpenAI API"
        case .openAICLI:       return "CLI OpenAI"
        case .claudeCLI:       return "CLI Claude"
        }
    }
    var needsAPIKey: Bool { self == .openAI }
}

@MainActor
@Observable
final class MacSettings {
    static let shared = MacSettings()

    private let defaults = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard

    private enum K {
        static let transcribe = "mac.transcribeBackend"
        static let redact = "mac.redactBackend"
        static let whisperCppBin = "mac.whisperCppBin"
        static let whisperCppModel = "mac.whisperCppModel"
        static let cliPath = "mac.redactCliPath"
        static let openAIModel = "mac.openAIModel"
        static let launchAtLogin = "mac.launchAtLogin"
    }

    var transcribe: TranscribeBackend {
        didSet { defaults.set(transcribe.rawValue, forKey: K.transcribe) }
    }
    var redact: RedactBackend {
        didSet { defaults.set(redact.rawValue, forKey: K.redact) }
    }
    // whisper.cpp paths (sensible defaults for Josu's mini)
    var whisperCppBin: String {
        didSet { defaults.set(whisperCppBin, forKey: K.whisperCppBin) }
    }
    var whisperCppModel: String {
        didSet { defaults.set(whisperCppModel, forKey: K.whisperCppModel) }
    }
    var redactCliPath: String {
        didSet { defaults.set(redactCliPath, forKey: K.cliPath) }
    }
    var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: K.openAIModel) }
    }

    private init() {
        let d = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard
        transcribe = TranscribeBackend(rawValue: d.string(forKey: K.transcribe) ?? "") ?? .appleSpeech
        redact = RedactBackend(rawValue: d.string(forKey: K.redact) ?? "") ?? .appleFoundation
        whisperCppBin = d.string(forKey: K.whisperCppBin) ?? "/opt/homebrew/bin/whisper-cli"
        whisperCppModel = d.string(forKey: K.whisperCppModel)
            ?? NSString(string: "~/whisper-models/ggml-large-v3-turbo-q5_0.bin").expandingTildeInPath
        redactCliPath = d.string(forKey: K.cliPath) ?? NSString(string: "~/.local/bin/claude").expandingTildeInPath
        openAIModel = d.string(forKey: K.openAIModel) ?? "gpt-4o"
    }

    // MARK: - API keys (Keychain)

    func openAIKey() -> String? { Keychain.read("openai-api-key") }
    func setOpenAIKey(_ value: String) {
        value.isEmpty ? Keychain.delete("openai-api-key") : Keychain.write("openai-api-key", value)
    }
}

/// Minimal Keychain wrapper for storing API keys.
enum Keychain {
    private static let service = "com.josumartinez.transcriber.mac"

    static func write(_ account: String, _ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
