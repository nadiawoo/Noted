//
//  GeminiClassificationService.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
//

import Foundation
import FirebaseCore
import FirebaseAILogic

struct ScreenshotClassification: Decodable {
    let title: String
    let category: ScreenshotCategory
    let folder: AlbumTopic
    let confidence: Double
    let recommendedAction: String
    let deadlineDate: String?
    let calendarTitle: String?
    let calendarProvider: CalendarProvider?
    let reasoning: String
}

enum ScreenshotClassifierError: LocalizedError {
    case emptyOCRText
    case firebaseNotConfigured
    case invalidResponse
    case requestFailed(String)
    case emptyCandidate

    var errorDescription: String? {
        switch self {
        case .emptyOCRText:
            "No readable text was found in that screenshot. Try a clearer screenshot or use the sample classifier to test Firebase AI."
        case .firebaseNotConfigured:
            "Firebase is not configured yet. Confirm GoogleService-Info.plist is in the app target and FirebaseApp.configure() runs at launch."
        case .invalidResponse:
            "Gemini returned a response Noted could not decode."
        case .requestFailed(let message):
            message
        case .emptyCandidate:
            "Gemini did not return a classification candidate."
        }
    }
}

protocol ScreenshotClassifying {
    func classify(extractedText: String) async throws -> ScreenshotClassification
}

final class GeminiClassificationService: ScreenshotClassifying {
    private let model: GenerativeModel

    init(
        modelName: String = "gemini-2.0-flash",
        firebaseAI: FirebaseAI? = nil
    ) throws {
        guard FirebaseApp.app() != nil else {
            throw ScreenshotClassifierError.firebaseNotConfigured
        }

        let firebaseAI = firebaseAI ?? FirebaseAI.firebaseAI()
        self.model = firebaseAI.generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json"
            )
        )
    }

    func classify(extractedText: String) async throws -> ScreenshotClassification {
        let trimmedText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ScreenshotClassifierError.emptyOCRText
        }

        let response: GenerateContentResponse
        do {
            response = try await model.generateContent(Self.classificationPrompt(for: trimmedText))
        } catch {
            throw ScreenshotClassifierError.requestFailed(Self.describeGenerationError(error))
        }

        guard let text = response.text else {
            throw ScreenshotClassifierError.emptyCandidate
        }

        guard let classificationData = text.cleanedJSONString.data(using: .utf8) else {
            throw ScreenshotClassifierError.invalidResponse
        }

        return try JSONDecoder().decode(ScreenshotClassification.self, from: classificationData)
    }

    private static func classificationPrompt(for extractedText: String) -> String {
        """
                    Classify this iPhone screenshot OCR text for Noted, a screenshot sorter.

                    Rules:
                    - category must be "timeSensitive" when the text includes an application, registration, event, deadline, due date, appointment, reservation, interview, meeting, or any action tied to a specific date/time.
                    - category must be "topic" for evergreen reference material, inspiration, notes, analysis, shopping ideas, or learning material.
                    - folder must be one of: applications, deadlines, fashion, computerScience, socialAnalysis, travel, general.
                    - Applications go in applications. Deadlines that are not application-specific go in deadlines.
                    - If category is timeSensitive, recommendedAction should describe the calendar event to create and deadlineDate should be ISO-8601 if a date/time is present.
                    - If category is topic, deadlineDate and calendarTitle should be null.
                    - calendarProvider should be "apple", "google", or null. Use null when the screenshot itself does not name a provider.
                    - confidence must be between 0 and 1.
                    - Return JSON only.

                    OCR text:
                    \(extractedText)
                    """
    }

    private static func describeGenerationError(_ error: Error) -> String {
        let details: String

        if let generateError = error as? GenerateContentError {
            switch generateError {
            case .internalError(let underlying):
                details = describeUnderlyingError(underlying)
            case .promptImageContentError(let underlying):
                details = "Prompt image content error: \(describeUnderlyingError(underlying))"
            case .promptBlocked(let response):
                let reason = response.promptFeedback?.blockReason.map { "\($0)" } ?? "unknown"
                let message = response.promptFeedback?.blockReasonMessage ?? "No block message returned."
                details = "Prompt blocked. Reason: \(reason). Message: \(message)"
            case .responseStoppedEarly(let reason, let response):
                let text = response.text ?? "No partial text returned."
                details = "Response stopped early. Reason: \(reason). Partial response: \(text)"
            }
        } else {
            details = describeUnderlyingError(error)
        }

        return """
        Firebase AI could not classify the screenshot.
        Details: \(details)
        """
    }

    private static func describeUnderlyingError(_ error: Error) -> String {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        let fallback = String(describing: error)

        guard !nsError.userInfo.isEmpty else {
            return description == fallback ? description : "\(description) \(fallback)"
        }

        let userInfo = nsError.userInfo
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "; ")

        return "\(description) Domain: \(nsError.domain). Code: \(nsError.code). \(userInfo)"
    }
}

private extension String {
    var cleanedJSONString: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
