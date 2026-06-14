// NotedViewModel.swift — Noted
// Central state: screenshot processing, event management, calendar sync

import SwiftUI
import Combine
#if os(iOS)
import UIKit
import EventKit
#endif

@MainActor
final class NotedViewModel: ObservableObject {
    @Published var events: [NotedEvent] = []
    @Published var isProcessing = false
    @Published var processingMessage = ""
    @Published var navPath = NavigationPath()
    @Published var googleCalVM = GoogleCalendarViewModel()

    /// Automatic background screenshot ingestion (see PhotoLibrarySync).
    let photoSync = PhotoLibrarySync()

    private var classifier: GeminiClassificationService? = {
        try? GeminiClassificationService()
    }()

    init() {
        // Route screenshots that pass the free OCR pre-filter through Gemini.
        photoSync.processImage = { [weak self] image, ocrText in
            await self?.ingestBackground(image: image, ocrText: ocrText)
        }
    }

    // MARK: - Screenshot → Event

    func processScreenshot(_ image: UIImage) async {
        isProcessing = true
        processingMessage = "Reading screenshot…"

        guard let classifier else {
            processingMessage = "Classifier unavailable."
            isProcessing = false
            return
        }

        // OCR text is a backup hint; Gemini reads the image directly.
        let ocrText = (try? await ScreenshotTextRecognizer.recognizeText(in: image)) ?? ""
        let imageData = image.jpegData(compressionQuality: 0.75)

        do {
            processingMessage = "Looking for events…"
            let analysis = try await classifier.analyze(imageData: imageData, ocrText: ocrText)

            guard analysis.hasTimeSensitiveInfo, !analysis.events.isEmpty else {
                processingMessage = "No event or deadline detected."
                isProcessing = false
                return
            }

            let created = analysis.events.map { detected in
                makeEvent(from: detected,
                          provider: analysis.calendarProvider,
                          imageData: imageData,
                          ocrText: ocrText)
            }

            // Newest first; show the first detected event for confirmation.
            for e in created.reversed() { events.insert(e, at: 0) }

            isProcessing = false
            processingMessage = created.count > 1 ? "Found \(created.count) events." : ""

            if let first = created.first {
                navPath.append(AppRoute.confirmEvent(first.id))
            }
        } catch {
            processingMessage = error.localizedDescription
            isProcessing = false
        }
    }

    /// Background variant used by automatic library sync: classify and append
    /// any detected events, but never navigate or surface processing UI. New
    /// events land in the list as unconfirmed (pink) for the user to review.
    /// OCR has already run upstream, so we don't repeat it here.
    func ingestBackground(image: UIImage, ocrText: String) async {
        guard let classifier else { return }
        let imageData = image.jpegData(compressionQuality: 0.75)
        do {
            let analysis = try await classifier.analyze(imageData: imageData, ocrText: ocrText)
            guard analysis.hasTimeSensitiveInfo, !analysis.events.isEmpty else { return }
            let created = analysis.events.map {
                makeEvent(from: $0,
                          provider: analysis.calendarProvider,
                          imageData: imageData,
                          ocrText: ocrText)
            }
            for e in created.reversed() { events.insert(e, at: 0) }
        } catch {
            // Background work fails quietly; the manual flow surfaces errors.
        }
    }

    /// Build a NotedEvent from a detected event, resolving the date, all-day
    /// flag, location relevance, and a smart default reminder.
    private func makeEvent(
        from detected: DetectedEvent,
        provider: CalendarProvider?,
        imageData: Data?,
        ocrText: String
    ) -> NotedEvent {
        var e = NotedEvent(
            title:            detected.title,
            notes:            detected.notes,
            confidence:       detected.confidence,
            calendarProvider: provider,
            sourceImageData:  imageData,
            sourceText:       ocrText
        )
        e.kind     = detected.kind
        e.hasTime  = detected.hasSpecificTime
        if detected.locationMatters, let loc = detected.location { e.location = loc }

        if let dateStr = detected.date {
            let resolved = ISO8601DateFormatter().date(from: dateStr) ?? parseYMD(dateStr)
            e.date = resolved
            if let d = resolved {
                e.endDate = Calendar.current.date(byAdding: .hour, value: e.hasTime ? 1 : 0, to: d)
            }
        }

        // Honor Gemini's suggestion, else fall back to a kind-appropriate default.
        if detected.suggestedReminder != nil {
            e.reminder = ReminderOffset(string: detected.suggestedReminder)
        } else {
            e.reminder = detected.kind.defaultReminder
        }
        return e
    }

    // MARK: - Event CRUD

    func confirm(id: UUID, updated: NotedEvent) async {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        var final = updated
        final.status = .confirmed
        events[idx] = final
        navPath = NavigationPath()

        if final.calendarProvider == .apple {
            await addToAppleCalendar(event: final)
        } else {
            // Default to Google when no provider was chosen.
            var googleEvent = final
            googleEvent.calendarProvider = .google
            _ = await googleCalVM.createEventIfNeeded(from: googleEvent)
        }
    }

    // MARK: - Google Calendar import

    /// Merge events pulled from Google Calendar into the local list as
    /// confirmed events, de-duplicating by Google event id.
    func importGoogleEvents(_ imported: [ImportedGoogleCalendarEvent]) {
        for g in imported where !events.contains(where: { $0.googleEventID == g.id }) {
            var e = NotedEvent(title: g.title, date: g.startDate)
            e.endDate          = Calendar.current.date(byAdding: .hour, value: 1, to: g.startDate)
            e.status           = .confirmed
            e.calendarProvider = .google
            e.googleEventID    = g.id
            events.append(e)
        }
    }

    /// Restore a Google session on launch and import any upcoming events.
    func restoreAndImportGoogle() async {
        let imported = await googleCalVM.restoreAndFetch()
        importGoogleEvents(imported)
    }

    func delete(id: UUID) {
        events.removeAll { $0.id == id }
        if !navPath.isEmpty { navPath.removeLast() }
    }

    func update(_ event: NotedEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx] = event
    }

    // MARK: - Calendar helpers

    var unconfirmedDates: Set<DateComponents> {
        Set(events.filter { $0.status == .unconfirmed }.compactMap {
            $0.date.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
        })
    }

    var confirmedDates: Set<DateComponents> {
        Set(events.filter { $0.status == .confirmed }.compactMap {
            $0.date.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
        })
    }

    // MARK: - Private

    private func addToAppleCalendar(event: NotedEvent) async {
        let store = EKEventStore()
        do {
            if #available(iOS 17, *) {
                try await store.requestFullAccessToEvents()
            } else {
                _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                    store.requestAccess(to: .event) { granted, error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: granted) }
                    }
                }
            }
            let start = event.date ?? Date()
            let ek = EKEvent(eventStore: store)
            ek.title    = event.title
            ek.location = event.location.isEmpty ? nil : event.location
            ek.notes    = event.notes.isEmpty ? nil : event.notes
            ek.isAllDay = !event.hasTime
            ek.startDate = start
            ek.endDate   = event.endDate
                ?? Calendar.current.date(byAdding: event.hasTime ? .hour : .day, value: 1, to: start)!
            if let offset = event.reminder.relativeOffset {
                ek.addAlarm(EKAlarm(relativeOffset: offset))
            }
            ek.calendar  = store.defaultCalendarForNewEvents
            try store.save(ek, span: .thisEvent)
        } catch {
            print("EventKit: \(error)")
        }
    }

    private func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
