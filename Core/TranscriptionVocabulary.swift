import Foundation

enum TranscriptionVocabulary {
    private static let key = "transcription.contextualTerms"
    private static let defaults = ["Danobat", "Eneko", "Borja", "Gorosabel", "Ion Azpeitia", "Iván Olariaga"]

    static var terms: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: key) ?? defaults
            return Array(stored.prefix(100))
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            UserDefaults.standard.set(Array(cleaned.prefix(100)), forKey: key)
        }
    }
}
