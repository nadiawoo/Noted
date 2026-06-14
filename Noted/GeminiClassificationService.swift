//
//  GeminiClassificationService.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
//

import Foundation
import FirebaseCore
import FirebaseAILogic

/// One time-sensitive item extracted from a screenshot.
struct DetectedEvent: Decodable {
    let title: String
    let kind: EventKind
    let date: String?            // ISO-8601: "YYYY-MM-DD" (all-day) or full datetime
    let hasSpecificTime: Bool
    let location: String?
    let locationMatters: Bool
    let suggestedReminder: String?
    let notes: String
    let confidence: Double

    private enum CodingKeys: String, CodingKey {
        case title, kind, date, hasSpecificTime, location, locationMatters, suggestedReminder, notes, confidence
    }

    // Tolerant decoding — Gemini may omit fields; fall back to sensible defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title             = (try? c.decode(String.self, forKey: .title)).map { $0.isEmpty ? "Untitled Event" : $0 } ?? "Untitled Event"
        kind              = (try? c.decode(EventKind.self, forKey: .kind)) ?? .other
        date              = (try? c.decodeIfPresent(String.self, forKey: .date)).flatMap { $0 }
        hasSpecificTime   = (try? c.decode(Bool.self, forKey: .hasSpecificTime)) ?? kind.timeUsuallyMatters
        location          = (try? c.decodeIfPresent(String.self, forKey: .location)).flatMap { $0 }
        locationMatters   = (try? c.decode(Bool.self, forKey: .locationMatters)) ?? false
        suggestedReminder = (try? c.decodeIfPresent(String.self, forKey: .suggestedReminder)).flatMap { $0 }
        notes             = (try? c.decode(String.self, forKey: .notes)) ?? ""
        confidence        = (try? c.decode(Double.self, forKey: .confidence)) ?? 0.6
    }
}

/// Result of analysing a whole screenshot — may contain zero, one, or many events.
struct ScreenshotAnalysis: Decodable {
    let hasTimeSensitiveInfo: Bool
    let events: [DetectedEvent]
    let calendarProvider: CalendarProvider?
    let reasoning: String

    private enum CodingKeys: String, CodingKey {
        case hasTimeSensitiveInfo, events, calendarProvider, reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events               = (try? c.decode([DetectedEvent].self, forKey: .events)) ?? []
        hasTimeSensitiveInfo = (try? c.decode(Bool.self, forKey: .hasTimeSensitiveInfo)) ?? !events.isEmpty
        calendarProvider     = (try? c.decodeIfPresent(CalendarProvider.self, forKey: .calendarProvider)).flatMap { $0 }
        reasoning            = (try? c.decode(String.self, forKey: .reasoning)) ?? ""
    }
}

enum ScreenshotClassifierError: LocalizedError {
    case emptyOCRText
    case firebaseNotConfigured
    case invalidResponse(String)
    case requestFailed(String)
    case emptyCandidate

    var errorDescription: String? {
        switch self {
        case .emptyOCRText:
            "No readable text was found in that screenshot. Try a clearer screenshot or use the sample classifier to test Firebase AI."
        case .firebaseNotConfigured:
            "Firebase is not configured yet. Confirm GoogleService-Info.plist is in the app target and FirebaseApp.configure() runs at launch."
        case .invalidResponse(let message):
            message
        case .requestFailed(let message):
            message
        case .emptyCandidate:
            "Gemini did not return a classification candidate."
        }
    }
}

protocol ScreenshotClassifying {
    func analyze(imageData: Data?, ocrText: String) async throws -> ScreenshotAnalysis
}

final class GeminiClassificationService: ScreenshotClassifying {
    private let model: GenerativeModel

    init(
        modelName: String = "gemini-3-flash-preview",
        firebaseAI: FirebaseAI? = nil
    ) throws {
        guard FirebaseApp.app() != nil else {
            throw ScreenshotClassifierError.firebaseNotConfigured
        }

        let firebaseAI = firebaseAI ?? FirebaseAI.firebaseAI(backend: .googleAI())
        self.model = firebaseAI.generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json"
            )
        )
    }

    func analyze(imageData: Data?, ocrText: String) async throws -> ScreenshotAnalysis {
        let trimmedText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = Self.analysisPrompt(ocrText: trimmedText)

        let response: GenerateContentResponse
        do {
            if let imageData {
                // Multimodal: let Gemini read the screenshot directly (far more
                // accurate than OCR text), with OCR text as a backup hint.
                let imagePart = InlineDataPart(data: imageData, mimeType: "image/jpeg")
                response = try await model.generateContent(imagePart, prompt)
            } else {
                guard !trimmedText.isEmpty else { throw ScreenshotClassifierError.emptyOCRText }
                response = try await model.generateContent(prompt)
            }
        } catch let error as ScreenshotClassifierError {
            throw error
        } catch {
            throw ScreenshotClassifierError.requestFailed(Self.describeGenerationError(error))
        }

        guard let text = response.text else {
            throw ScreenshotClassifierError.emptyCandidate
        }

        guard let data = text.cleanedJSONString.data(using: .utf8) else {
            throw ScreenshotClassifierError.invalidResponse("""
            Gemini returned text that could not be converted to UTF-8 data.
            Raw response: \(text)
            """)
        }

        do {
            return try JSONDecoder().decode(ScreenshotAnalysis.self, from: data)
        } catch {
            throw ScreenshotClassifierError.invalidResponse("""
            Gemini returned a response Noted could not decode.
            Decode error: \(error.localizedDescription)
            Raw response: \(text)
            """)
        }
    }

    private static func analysisPrompt(ocrText: String) -> String {
        let today = ISO8601DateFormatter().string(from: Date())
        return """
        You are the event extractor for Noted. You are given a phone screenshot \
        (and OCR text as a backup hint). Find any time-sensitive information and \
        return STRICT JSON only — no markdown, no prose outside the JSON.

        Think about, in order:
        1) Is there ANY event or time-sensitive information at all?
        2) Is exactly one event mentioned, or several? Emit one object per distinct event.
        3) For each: which date actually matters, and does the specific clock time matter?
        4) Is it an application/submission (wants an EARLIER reminder before the due day),
           or a timed event where the exact hour/minute and a physical location matter?

        Return JSON shaped exactly like:
        {
          "hasTimeSensitiveInfo": true | false,
          "calendarProvider": "apple" | "google" | null,
          "reasoning": "one short sentence",
          "events": [
            {
              "title": "short human title, e.g. 'Research Application' (NOT the whole sentence)",
              "kind": "application" | "deadline" | "appointment" | "event" | "reservation" | "meeting" | "interview" | "other",
              "date": "YYYY-MM-DD for all-day/deadlines, or YYYY-MM-DDTHH:MM:SS when a clock time matters, or null",
              "hasSpecificTime": true only if a specific hour/minute matters; false for deadlines/applications,
              "location": "physical place, or null. Never put URLs or descriptions here",
              "locationMatters": true only if showing up in person at a place matters,
              "suggestedReminder": "atTime" | "oneHour" | "oneDay" | "oneWeek" | "none",
              "notes": "ONE short sentence of useful detail, under 140 chars. Do NOT dump all the text here",
              "confidence": 0.0 to 1.0
            }
          ]
        }

        Rules:
        - Keep "title" concise. Do NOT stuff date, time, location, links, or a long description into title or notes.
        - Applications & submission deadlines: kind "application"/"deadline", hasSpecificTime false, and an EARLIER suggestedReminder ("oneWeek" for applications, "oneDay" for deadlines).
        - Meetings/appointments/reservations/interviews: hasSpecificTime true, suggestedReminder "oneHour", set location + locationMatters when there is a venue.
        - If several deadlines/events appear, return multiple objects in "events".
        - If there is no time-sensitive info, set hasTimeSensitiveInfo=false and events=[].
        - Today is \(today). Resolve relative dates ("tomorrow", "next Friday") against today.
        - calendarProvider: only set when the screenshot clearly names Apple or Google calendar; else null.

        OCR text (backup hint, may be empty or noisy):
        \(ocrText)
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
