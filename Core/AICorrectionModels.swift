//
//  AICorrectionModels.swift
//  Transcriber
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable Types for Structured AI Output

@available(iOS 26, macOS 26, *)
@Generable
enum CorrectionCategory: String, Sendable {
    case mishearing
    case grammar
    case punctuation
    case formatting
    case fillerWord
    case unclear
}

@available(iOS 26, macOS 26, *)
@Generable
struct SingleCorrection: Sendable {
    @Guide(description: "The exact original text that needs correction")
    var originalText: String

    @Guide(description: "The suggested replacement text")
    var suggestedText: String

    @Guide(description: "The type of correction")
    var category: CorrectionCategory

    @Guide(description: "Brief explanation of why this correction is suggested")
    var reason: String

    @Guide(description: "Confidence level from 1 (low) to 10 (high)")
    var confidence: Int
}

@available(iOS 26, macOS 26, *)
@Generable
struct CorrectionBatch: Sendable {
    @Guide(description: "List of corrections found, maximum 20")
    var corrections: [SingleCorrection]
}
#endif

// MARK: - Runtime Model

enum CorrectionStatus: String {
    case pending
    case accepted
    case rejected
}

@available(iOS 26, macOS 26, *)
@Observable
final class TranscriptionCorrection: Identifiable {
    let id = UUID()
    var originalText: String
    var suggestedText: String
    var category: String // Raw value from CorrectionCategory
    var reason: String
    var confidence: Int
    var status: CorrectionStatus = .pending
    var userOverride: String? // For unclear items where user provides custom text
    var rangeInText: Range<String.Index>? // Position in the full transcription text

    init(originalText: String, suggestedText: String, category: String, reason: String, confidence: Int) {
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.category = category
        self.reason = reason
        self.confidence = confidence
    }

    var displayCategory: String {
        switch category {
        case "mishearing": return "Mishearing"
        case "grammar": return "Grammar"
        case "punctuation": return "Punctuation"
        case "formatting": return "Formatting"
        case "fillerWord": return "Filler Word"
        case "unclear": return "Unclear"
        default: return category.capitalized
        }
    }

    var categoryIcon: String {
        switch category {
        case "mishearing": return "ear.trianglebadge.exclamationmark"
        case "grammar": return "textformat.abc"
        case "punctuation": return "textformat"
        case "formatting": return "text.alignleft"
        case "fillerWord": return "minus.circle"
        case "unclear": return "questionmark.circle"
        default: return "pencil"
        }
    }

    var categoryColor: String {
        switch category {
        case "mishearing": return "red"
        case "grammar": return "orange"
        case "punctuation": return "blue"
        case "formatting": return "purple"
        case "fillerWord": return "gray"
        case "unclear": return "yellow"
        default: return "gray"
        }
    }

    /// The text to apply — either the user override (for unclear) or the suggested text
    var effectiveReplacement: String {
        userOverride ?? suggestedText
    }
}
