//
//  GoogleCalendarService.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
//

import Combine
import Foundation
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#endif

struct ImportedGoogleCalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
}

enum GoogleCalendarError: LocalizedError {
    case missingClientID
    case missingPresenter
    case missingAccessToken
    case invalidResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Google Calendar OAuth client plist is missing a CLIENT_ID."
        case .missingPresenter:
            "Could not open Google sign-in because no presenting view controller was available."
        case .missingAccessToken:
            "Google sign-in did not return an access token."
        case .invalidResponse(let statusCode, let body):
            "Google Calendar returned HTTP \(statusCode): \(body)"
        }
    }
}

@MainActor
final class GoogleCalendarViewModel: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSyncing = false

    private let service = GoogleCalendarService()

    var statusText: String {
        if let accountEmail {
            return "Google Calendar: \(accountEmail)"
        }

        return "Google Calendar is not connected."
    }

    func restoreSession() {
        Task {
            do {
                let user = try await service.restorePreviousSignIn()
                apply(user: user)
            } catch {
                isSignedIn = false
                accountEmail = nil
            }
        }
    }

    /// Restore a previous session and, if signed in with calendar access, pull
    /// upcoming events. Returns an empty array if not signed in or on failure.
    func restoreAndFetch() async -> [ImportedGoogleCalendarEvent] {
        do {
            let user = try await service.restorePreviousSignIn()
            apply(user: user)
            return try await service.fetchUpcomingEvents()
        } catch {
            isSignedIn = false
            accountEmail = nil
            return []
        }
    }

#if canImport(UIKit)
    func connectAndImport() async -> [ImportedGoogleCalendarEvent] {
        isSyncing = true
        statusMessage = "Connecting to Google Calendar..."

        do {
            let user = try await service.signInIfNeeded()
            apply(user: user)

            statusMessage = "Importing Google Calendar events..."
            let events = try await service.fetchUpcomingEvents()
            statusMessage = "Imported \(events.count) Google Calendar events."
            isSyncing = false
            return events
        } catch {
            statusMessage = error.localizedDescription
            isSyncing = false
            return []
        }
    }
#endif

    func createEventIfNeeded(from event: NotedEvent) async -> ImportedGoogleCalendarEvent? {
        guard event.calendarProvider == .google else { return nil }

        isSyncing = true
        statusMessage = "Adding event to Google Calendar..."

        do {
            let user = try await service.signInIfNeeded()
            apply(user: user)

            let created = try await service.createEvent(from: event)
            statusMessage = "Added to Google Calendar."
            isSyncing = false
            return created
        } catch {
            statusMessage = error.localizedDescription
            isSyncing = false
            return nil
        }
    }

    func signOut() {
        service.signOut()
        isSignedIn = false
        accountEmail = nil
        statusMessage = "Google Calendar disconnected."
    }

    private func apply(user: GIDGoogleUser) {
        isSignedIn = true
        accountEmail = user.profile?.email
    }
}

final class GoogleCalendarService {
    static let calendarScope = "https://www.googleapis.com/auth/calendar.events"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        configureSignIn()
    }

    func restorePreviousSignIn() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: error ?? GoogleCalendarError.missingAccessToken)
                }
            }
        }
    }

#if canImport(UIKit)
    @MainActor
    func signInIfNeeded() async throws -> GIDGoogleUser {
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            let user = try await refreshedUser(currentUser)
            if hasCalendarScope(user) {
                return user
            }

            guard let presenter = UIViewController.notedTopPresenter else {
                throw GoogleCalendarError.missingPresenter
            }

            return try await addCalendarScope(to: user, presenter: presenter)
        }

        guard let presenter = UIViewController.notedTopPresenter else {
            throw GoogleCalendarError.missingPresenter
        }

        return try await signIn(presenter: presenter)
    }
#endif

    func fetchUpcomingEvents() async throws -> [ImportedGoogleCalendarEvent] {
        let token = try await accessToken()
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "timeMin", value: ISO8601DateFormatter().string(from: Date()))
        ]

        let response = try await calendarRequest(
            url: components.url!,
            method: "GET",
            accessToken: token
        )

        let decoded = try JSONDecoder.googleCalendar.decode(GoogleCalendarEventsResponse.self, from: response)
        return decoded.items.compactMap(\.importedEvent)
    }

    func createEvent(from event: NotedEvent) async throws -> ImportedGoogleCalendarEvent {
        let token = try await accessToken()
        let requestBody = GoogleCalendarCreateEventRequest(event: event)
        let body = try JSONEncoder.googleCalendar.encode(requestBody)

        let response = try await calendarRequest(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!,
            method: "POST",
            accessToken: token,
            body: body
        )

        let decoded = try JSONDecoder.googleCalendar.decode(GoogleCalendarEventResponse.self, from: response)
        return decoded.importedEvent ?? ImportedGoogleCalendarEvent(
            id: decoded.id ?? UUID().uuidString,
            title: requestBody.summary,
            startDate: requestBody.start.resolvedDate ?? Date()
        )
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    private func configureSignIn() {
        guard let clientID = Self.clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    private static var clientID: String? {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let oauthConfigs = Bundle.main.paths(forResourcesOfType: "plist", inDirectory: nil)
            .lazy
            .compactMap { NSDictionary(contentsOfFile: $0) }
            .filter { config in
                guard let clientID = config["CLIENT_ID"] as? String,
                      config["REVERSED_CLIENT_ID"] is String else { return false }
                // Ignore the placeholder example plist that ships in the bundle.
                return !clientID.contains("YOUR_")
            }

        return oauthConfigs.first { config in
            guard let bundleIdentifier else { return false }
            return config["BUNDLE_ID"] as? String == bundleIdentifier
        }?["CLIENT_ID"] as? String ?? oauthConfigs.first?["CLIENT_ID"] as? String
    }

#if canImport(UIKit)
    @MainActor
    private func signIn(presenter: UIViewController) async throws -> GIDGoogleUser {
        configureSignIn()

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [Self.calendarScope]
            ) { result, error in
                if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: error ?? GoogleCalendarError.missingAccessToken)
                }
            }
        }
    }

    @MainActor
    private func addCalendarScope(to user: GIDGoogleUser, presenter: UIViewController) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.addScopes([Self.calendarScope], presenting: presenter) { result, error in
                if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: error ?? GoogleCalendarError.missingAccessToken)
                }
            }
        }
    }
#endif

    private func refreshedUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: error ?? GoogleCalendarError.missingAccessToken)
                }
            }
        }
    }

    private func hasCalendarScope(_ user: GIDGoogleUser) -> Bool {
        user.grantedScopes?.contains(Self.calendarScope) == true
    }

    private func accessToken() async throws -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleCalendarError.missingAccessToken
        }

        let user = try await refreshedUser(currentUser)
        return user.accessToken.tokenString
    }

    private func calendarRequest(
        url: URL,
        method: String,
        accessToken: String,
        body: Data? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body."
            throw GoogleCalendarError.invalidResponse(statusCode, body)
        }

        return data
    }
}

private struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEventResponse]
}

private struct GoogleCalendarEventResponse: Decodable {
    let id: String?
    let summary: String?
    let start: GoogleCalendarEventDate?

    var importedEvent: ImportedGoogleCalendarEvent? {
        guard let id, let summary, let startDate = start?.resolvedDate else {
            return nil
        }

        return ImportedGoogleCalendarEvent(id: id, title: summary, startDate: startDate)
    }
}

private struct GoogleCalendarEventDate: Codable {
    let date: String?
    let dateTime: Date?
    let timeZone: String?

    var resolvedDate: Date? {
        if let dateTime {
            return dateTime
        }

        guard let date else { return nil }
        return DateFormatter.googleCalendarDate.date(from: date)
    }
}

private struct GoogleCalendarReminders: Encodable {
    struct Override: Encodable { let method: String; let minutes: Int }
    let useDefault: Bool
    let overrides: [Override]
}

private struct GoogleCalendarCreateEventRequest: Encodable {
    let summary: String
    let description: String?
    let location: String?
    let start: GoogleCalendarEventDate
    let end: GoogleCalendarEventDate
    let reminders: GoogleCalendarReminders

    init(event: NotedEvent) {
        summary = event.title.isEmpty ? "Untitled Event" : event.title

        var desc = event.notes
        if !event.guests.isEmpty {
            desc += (desc.isEmpty ? "" : "\n") + "Guests: \(event.guests)"
        }
        description = desc.isEmpty ? nil : desc
        location = event.location.isEmpty ? nil : event.location

        let startDate = event.date ?? Date()
        let timeZone = TimeZone.current.identifier

        if event.hasTime {
            let endDate = event.endDate
                ?? Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
                ?? startDate
            start = GoogleCalendarEventDate(date: nil, dateTime: startDate, timeZone: timeZone)
            end   = GoogleCalendarEventDate(date: nil, dateTime: endDate, timeZone: timeZone)
        } else {
            // All-day: date-only; Google treats the end date as exclusive (next day).
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            start = GoogleCalendarEventDate(
                date: DateFormatter.googleCalendarDate.string(from: startDate),
                dateTime: nil, timeZone: nil
            )
            end = GoogleCalendarEventDate(
                date: DateFormatter.googleCalendarDate.string(from: nextDay),
                dateTime: nil, timeZone: nil
            )
        }

        if let minutes = event.reminder.minutesBefore {
            reminders = GoogleCalendarReminders(useDefault: false,
                                                overrides: [.init(method: "popup", minutes: minutes)])
        } else {
            reminders = GoogleCalendarReminders(useDefault: false, overrides: [])
        }
    }
}

private extension JSONDecoder {
    static var googleCalendar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var googleCalendar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension DateFormatter {
    static let googleCalendarDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#if canImport(UIKit)
private extension UIViewController {
    static var notedTopPresenter: UIViewController? {
        let foregroundScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        let root = foregroundScene?.windows.first { $0.isKeyWindow }?.rootViewController
        return root?.notedTopMostViewController
    }

    var notedTopMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.notedTopMostViewController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.notedTopMostViewController ?? navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.notedTopMostViewController ?? tabBarController
        }

        return self
    }
}
#endif
