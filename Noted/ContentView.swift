// ContentView.swift — Noted
// App root: brand colors, shared types, navigation shell

import SwiftUI
import Foundation
#if os(iOS)
import PhotosUI
import UIKit
#endif

// MARK: - Brand Colors

extension Color {
    // Key colors from the NoteThisDown Figma (node 13:10)
    static let nBg        = Color(red: 1.000, green: 0.996, blue: 0.980) // #FFFEFA warm cream
    static let nBrown     = Color(red: 0.451, green: 0.373, blue: 0.333) // #735F55 "Noted - Brown"
    static let nMint      = Color(red: 0.827, green: 0.910, blue: 0.902) // #D3E8E6 confirmed
    static let nParchment = Color(red: 0.940, green: 0.920, blue: 0.860)
    static let nPink      = Color(red: 0.914, green: 0.365, blue: 0.455) // #E95D74 unconfirmed
    static let notedGroupedBackground = nBg
    static let notedSurface           = Color.white
    static let notedInsetSurface      = nParchment
}

// MARK: - Shared Types

enum CalendarProvider: String, CaseIterable, Identifiable, Codable {
    case apple, google
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbolName: String { self == .apple ? "apple.logo" : "g.circle" }
    var tint: Color { self == .apple ? .nBrown : Color(red: 0.26, green: 0.52, blue: 0.96) }
}

enum ScreenshotCategory: String, Codable {
    case timeSensitive, topic
}

enum AlbumTopic: String, CaseIterable, Identifiable, Codable {
    case applications, deadlines, fashion, computerScience, socialAnalysis, travel, general
    var id: Self { self }
    var title: String {
        switch self {
        case .applications:    "Applications"
        case .deadlines:       "Deadlines"
        case .fashion:         "Fashion Inspo"
        case .computerScience: "Computer Science"
        case .socialAnalysis:  "Social Analysis"
        case .travel:          "Travel Ideas"
        case .general:         "General"
        }
    }
    var symbolName: String {
        switch self {
        case .applications:    "doc.text.magnifyingglass"
        case .deadlines:       "calendar.badge.exclamationmark"
        case .fashion:         "tshirt"
        case .computerScience: "cpu"
        case .socialAnalysis:  "chart.bar.xaxis"
        case .travel:          "airplane"
        case .general:         "tray.full"
        }
    }
}

enum EventStatus: String, Equatable, Codable { case unconfirmed, confirmed, deleted }

/// What kind of time-sensitive thing this is — drives default reminders and
/// whether the specific hour/minute and location matter.
enum EventKind: String, Codable, CaseIterable, Identifiable {
    case application, deadline, appointment, event, reservation, meeting, interview, other
    var id: Self { self }

    var label: String {
        switch self {
        case .application: "Application"
        case .deadline:    "Deadline"
        case .appointment: "Appointment"
        case .event:       "Event"
        case .reservation: "Reservation"
        case .meeting:     "Meeting"
        case .interview:   "Interview"
        case .other:       "Reminder"
        }
    }

    var symbolName: String {
        switch self {
        case .application: "doc.text"
        case .deadline:    "flag"
        case .appointment: "calendar"
        case .event:       "sparkles"
        case .reservation: "fork.knife"
        case .meeting:     "person.2"
        case .interview:   "briefcase"
        case .other:       "bell"
        }
    }

    /// Deadlines/applications are usually all-day with an earlier nudge;
    /// time-and-place events default to an hour before.
    var defaultReminder: ReminderOffset {
        switch self {
        case .application:        .oneWeek
        case .deadline:           .oneDay
        default:                  .oneHour
        }
    }

    /// Whether the exact hour/minute typically matters for this kind.
    var timeUsuallyMatters: Bool {
        switch self {
        case .application, .deadline: false
        default:                      true
        }
    }
}

enum ReminderOffset: String, CaseIterable, Identifiable {
    case atTime  = "At event time"
    case oneHour = "1 hour before"
    case oneDay  = "1 day before"
    case oneWeek = "1 week before"
    case none    = "No reminder"
    var id: Self { self }

    /// Seconds relative to the event start (negative = before). nil = no alarm.
    var relativeOffset: TimeInterval? {
        switch self {
        case .atTime:  0
        case .oneHour: -3600
        case .oneDay:  -86_400
        case .oneWeek: -604_800
        case .none:    nil
        }
    }

    /// Minutes before the event start, for Google Calendar reminder overrides.
    var minutesBefore: Int? {
        guard let relativeOffset, relativeOffset <= 0 else { return nil }
        return Int(-relativeOffset / 60)
    }

    init(string: String?) {
        switch string?.lowercased() {
        case "attime", "at_time", "at event time": self = .atTime
        case "onehour", "one_hour", "1 hour before", "hour": self = .oneHour
        case "oneday", "one_day", "1 day before", "day": self = .oneDay
        case "oneweek", "one_week", "1 week before", "week": self = .oneWeek
        case "none", "no reminder", "": self = .none
        default: self = .oneHour
        }
    }
}

enum CalendarView { case month, week, day, year }

// MARK: - Event Model

struct NotedEvent: Identifiable, Equatable {
    var id         = UUID()
    var title      = ""
    var date: Date?
    var endDate: Date?
    var location   = ""
    var guests     = ""
    var notes      = ""
    var reminder   = ReminderOffset.oneHour
    var status     = EventStatus.unconfirmed
    var confidence = 0.0
    var calendarProvider: CalendarProvider? = nil
    var sourceImageData: Data? = nil
    var sourceText = ""
    var googleEventID: String? = nil
    var kind       = EventKind.other
    var hasTime    = true          // false → all-day (deadlines, applications)

    var sourceImage: UIImage? { sourceImageData.flatMap { UIImage(data: $0) } }
    var needsConfirmation: Bool { status == .unconfirmed }
}

// MARK: - App Navigation

enum AppRoute: Hashable {
    case confirmEvent(UUID)
    case addEvent
    case settings
    case screenshotPreview(UUID)
    case syncProgress
}

// MARK: - Shared hand-drawn header (Plans + Back · Settings)

struct DrawnHeader: View {
    var onBack: () -> Void
    var onSettings: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image("Plans")
                        .resizable().scaledToFit()
                        .frame(width: 46, height: 40)
                    Image("Back")
                        .resizable().scaledToFit()
                        .frame(height: 22)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let onSettings {
                Button(action: onSettings) {
                    Image("Settings")
                        .resizable().scaledToFit()
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var vm = NotedViewModel()
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                NavigationStack(path: $vm.navPath) {
                    MainMenuView()
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .confirmEvent(let id):
                                if let event = vm.events.first(where: { $0.id == id }) {
                                    ConfirmEventView(eventID: id, initial: event)
                                        .environmentObject(vm)
                                }
                            case .addEvent:
                                AddEventView()
                                    .environmentObject(vm)
                            case .settings:
                                SettingsView()
                                    .environmentObject(vm)
                            case .screenshotPreview(let id):
                                if let event = vm.events.first(where: { $0.id == id }),
                                   let img = event.sourceImage {
                                    ScreenshotPreviewView(image: img)
                                }
                            case .syncProgress:
                                SyncProgressView(sync: vm.photoSync)
                                    .environmentObject(vm)
                            }
                        }
                }
                .environmentObject(vm)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: showSplash)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                showSplash = false
            }
        }
    }
}
