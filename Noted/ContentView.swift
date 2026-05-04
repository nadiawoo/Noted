//
//  ContentView.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
//

import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ContentView: View {
    @State private var screenshots = ScreenshotDraft.samples
    @State private var calendarEvents = CalendarEvent.samples
    @State private var showingSorter = false
#if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
#endif
    @State private var isClassifyingScreenshot = false
    @State private var classificationMessage: String?

    private var uncertainScreenshots: [ScreenshotDraft] {
        screenshots.filter { $0.requiresManualReview }
    }

    private var calendarQueueCount: Int {
        screenshots.filter { $0.status == .calendarQueued }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    calendarHeader
                    importedCalendar
                    classificationControls
                    reviewQueueButton
                    topicPreview
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .background(Color.notedGroupedBackground)
            .navigationTitle("Noted")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationDestination(isPresented: $showingSorter) {
                ScreenshotSorterView(screenshots: $screenshots)
            }
#if os(iOS)
            .onChange(of: selectedPhotoItem) { _, item in
                classifySelectedPhoto(item)
            }
#endif
        }
    }

    private var calendarHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Imported Calendar")
                        .font(.title2.bold())
                    Text("Deadlines found in screenshots appear here before they are added to your calendar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 14) {
                CalendarProviderBadge(provider: .apple)
                CalendarProviderBadge(provider: .google)
                Spacer()
            }
        }
    }

    private var importedCalendar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {} label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text("May 2026")
                    .font(.headline)

                Spacer()

                Button {} label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            CalendarMonthGrid(events: calendarEvents)
                .padding(16)

            Divider()

            VStack(spacing: 12) {
                ForEach(calendarEvents) { event in
                    CalendarEventRow(event: event)
                }
            }
            .padding(16)
        }
        .background(Color.notedSurface, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var classificationControls: some View {
#if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(isClassifyingScreenshot ? "Classifying" : "Import Screenshot", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isClassifyingScreenshot)

                Button {
                    classifySampleOCR()
                } label: {
                    Image(systemName: "text.viewfinder")
                }
                .buttonStyle(.bordered)
                .disabled(isClassifyingScreenshot)
            }

#if DEBUG
            Button {
                classifyBundledFixture()
            } label: {
                Label("Test Fixture", systemImage: "photo.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isClassifyingScreenshot)
#endif

            if let classificationMessage {
                Text(classificationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.notedSurface, in: RoundedRectangle(cornerRadius: 8))
#else
        VStack(alignment: .leading, spacing: 12) {
            Button {
                classifySampleOCR()
            } label: {
                Label(isClassifyingScreenshot ? "Classifying" : "Classify Sample OCR", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isClassifyingScreenshot)

            if let classificationMessage {
                Text(classificationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.notedSurface, in: RoundedRectangle(cornerRadius: 8))
#endif
    }

    private var reviewQueueButton: some View {
        Button {
            showingSorter = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sort Screenshots")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(uncertainScreenshots.count) need review, \(calendarQueueCount) calendar-ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.notedSurface, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var topicPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Topic Albums")
                    .font(.headline)
                Spacer()
                Text("\(AlbumTopic.allCases.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AlbumTopic.allCases) { topic in
                    AlbumCard(topic: topic, count: screenshots.filter { $0.topic == topic }.count)
                }
            }
        }
    }

#if os(iOS)
    private func classifySelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            setClassificationState(isRunning: true, message: "Reading screenshot text...")

            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    setClassificationState(isRunning: false, message: "Could not read that image.")
                    return
                }

                let text = try await ScreenshotTextRecognizer.recognizeText(in: image)
                setClassificationState(
                    isRunning: true,
                    message: "Found \(text.trimmingCharacters(in: .whitespacesAndNewlines).count) characters. Classifying..."
                )
                try await classify(extractedText: text)
            } catch {
                setClassificationState(isRunning: false, message: error.localizedDescription)
            }
        }
    }

#if DEBUG
    private func classifyBundledFixture() {
        Task {
            setClassificationState(isRunning: true, message: "Reading bundled test screenshot...")

            do {
                let imageURL = Bundle.main.url(
                    forResource: "cbl-coding-challenge",
                    withExtension: "png",
                    subdirectory: "TestFixtures"
                ) ?? Bundle.main.url(
                    forResource: "cbl-coding-challenge",
                    withExtension: "png"
                )

                guard let imageURL,
                      let image = UIImage(contentsOfFile: imageURL.path) else {
                    setClassificationState(isRunning: false, message: "Could not load bundled test screenshot.")
                    return
                }

                let text = try await ScreenshotTextRecognizer.recognizeText(in: image)
                setClassificationState(
                    isRunning: true,
                    message: "Fixture OCR found \(text.trimmingCharacters(in: .whitespacesAndNewlines).count) characters. Classifying..."
                )
                try await classify(extractedText: text)
            } catch {
                setClassificationState(isRunning: false, message: error.localizedDescription)
            }
        }
    }
#endif
#endif

    private func classifySampleOCR() {
        Task {
            setClassificationState(isRunning: true, message: "Classifying sample screenshot text...")

            do {
                try await classify(extractedText: """
                Summer Research Internship Application
                Complete your application by May 31, 2026 at 11:59 PM ET.
                Required: resume, unofficial transcript, and two short responses.
                Add the deadline to Google Calendar.
                """)
            } catch {
                setClassificationState(isRunning: false, message: error.localizedDescription)
            }
        }
    }

    private func classify(extractedText: String) async throws {
        let classifier = try GeminiClassificationService()
        let classification = try await classifier.classify(extractedText: extractedText)

        await MainActor.run {
            let draft = ScreenshotDraft(classification: classification, extractedText: extractedText)
            screenshots.insert(draft, at: 0)

            if let event = CalendarEvent(classification: classification) {
                calendarEvents.insert(event, at: 0)
            }

            let message = draft.status == .calendarQueued
                ? "Added to \(draft.topic.title) and queued a calendar event."
                : "Added to \(draft.topic.title) for review."
            isClassifyingScreenshot = false
            classificationMessage = message
#if os(iOS)
            selectedPhotoItem = nil
#endif
        }
    }

    @MainActor
    private func setClassificationState(isRunning: Bool, message: String?) {
        isClassifyingScreenshot = isRunning
        classificationMessage = message
    }
}

private struct CalendarMonthGrid: View {
    let events: [CalendarEvent]

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let days = Array(1...31)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(weekdays.indices, id: \.self) { index in
                Text(weekdays[index])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(0..<5, id: \.self) { _ in
                Color.clear
                    .frame(height: 30)
            }

            ForEach(days, id: \.self) { day in
                let matchingEvents = events.filter { $0.day == day }

                VStack(spacing: 3) {
                    Text("\(day)")
                        .font(.subheadline.weight(matchingEvents.isEmpty ? .regular : .semibold))
                        .foregroundStyle(day == 4 ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(day == 4 ? Color.accentColor : Color.clear, in: Circle())

                    HStack(spacing: 3) {
                        ForEach(matchingEvents.prefix(3)) { event in
                            Circle()
                                .fill(event.provider.tint)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
            }
        }
    }
}

private struct CalendarProviderBadge: View {
    let provider: CalendarProvider

    var body: some View {
        Label(provider.title, systemImage: provider.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(provider.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(provider.tint.opacity(0.12), in: Capsule())
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(event.month)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(event.day)")
                    .font(.headline)
            }
            .frame(width: 46, height: 50)
            .background(event.provider.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                Text(event.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: event.kind.symbolName)
                .foregroundStyle(event.provider.tint)
        }
    }
}

private struct ScreenshotSorterView: View {
    @Binding var screenshots: [ScreenshotDraft]
    @State private var selectedMode: SorterMode = .review

    private var reviewItems: [ScreenshotDraft] {
        screenshots.filter { $0.status == .needsReview }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Sorter Mode", selection: $selectedMode) {
                    ForEach(SorterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if selectedMode == .review {
                    reviewQueue
                } else {
                    albumGrid
                }
            }
            .padding(20)
        }
        .background(Color.notedGroupedBackground)
        .navigationTitle("Sort Screenshots")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var reviewQueue: some View {
        VStack(spacing: 14) {
            if reviewItems.isEmpty {
                ContentUnavailableView("All Sorted", systemImage: "checkmark.circle", description: Text("New uncertain screenshots will appear here."))
            } else {
                ForEach(reviewItems) { draft in
                    ScreenshotReviewCard(
                        draft: draft,
                        onConfirm: { mark(draft, as: .sorted) },
                        onTopicChange: { topic in updateTopic(for: draft, topic: topic) }
                    )
                }
            }
        }
    }

    private var albumGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(AlbumTopic.allCases) { topic in
                AlbumCard(topic: topic, count: screenshots.filter { $0.topic == topic }.count)
            }
        }
    }

    private func mark(_ draft: ScreenshotDraft, as status: ScreenshotStatus) {
        guard let index = screenshots.firstIndex(where: { $0.id == draft.id }) else { return }
        screenshots[index].status = status
    }

    private func updateTopic(for draft: ScreenshotDraft, topic: AlbumTopic) {
        guard let index = screenshots.firstIndex(where: { $0.id == draft.id }) else { return }
        screenshots[index].topic = topic
    }
}

private struct ScreenshotReviewCard: View {
    let draft: ScreenshotDraft
    let onConfirm: () -> Void
    let onTopicChange: (AlbumTopic) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ScreenshotThumbnail(draft: draft)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(draft.title)
                            .font(.headline)
                        Spacer()
                        ConfidenceBadge(confidence: draft.confidence)
                    }

                    Text(draft.extractedText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Picker("Album", selection: Binding(
                get: { draft.topic },
                set: { onTopicChange($0) }
            )) {
                ForEach(AlbumTopic.allCases) { topic in
                    Text(topic.title).tag(topic)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Label(draft.recommendedAction, systemImage: draft.category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onConfirm) {
                    Label("Confirm", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color.notedSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ScreenshotThumbnail: View {
    let draft: ScreenshotDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(draft.topic.tint.gradient)
                .frame(height: 72)
                .overlay {
                    Image(systemName: draft.topic.symbolName)
                        .font(.title2)
                        .foregroundStyle(.white)
                }

            Text(draft.topic.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: 92)
        .background(Color.notedInsetSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AlbumCard: View {
    let topic: AlbumTopic
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(topic.tint.opacity(0.18))

                Image(systemName: topic.symbolName)
                    .font(.title2)
                    .foregroundStyle(topic.tint)
            }
            .aspectRatio(1.35, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(count) screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.notedSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2.weight(.bold))
            .foregroundStyle(confidence < 0.72 ? Color.orange : Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((confidence < 0.72 ? Color.orange : Color.green).opacity(0.12), in: Capsule())
    }
}

enum CalendarProvider: String, CaseIterable, Identifiable, Codable {
    case apple
    case google

    var id: Self { self }

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }

    var symbolName: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle"
        }
    }

    var tint: Color {
        switch self {
        case .apple: .blue
        case .google: .green
        }
    }
}

private enum SorterMode: String, CaseIterable, Identifiable {
    case review
    case albums

    var id: Self { self }

    var title: String {
        switch self {
        case .review: "Needs Review"
        case .albums: "Albums"
        }
    }
}

enum ScreenshotStatus {
    case needsReview
    case calendarQueued
    case sorted
}

enum ScreenshotCategory: String, Codable {
    case timeSensitive
    case topic

    var symbolName: String {
        switch self {
        case .timeSensitive: "calendar.badge.clock"
        case .topic: "rectangle.stack"
        }
    }
}

private enum CalendarEventKind {
    case deadline
    case reminder

    var symbolName: String {
        switch self {
        case .deadline: "exclamationmark.circle.fill"
        case .reminder: "bell.fill"
        }
    }
}

enum AlbumTopic: String, CaseIterable, Identifiable, Codable {
    case applications
    case deadlines
    case fashion
    case computerScience
    case socialAnalysis
    case travel
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .applications: "Applications"
        case .deadlines: "Deadlines"
        case .fashion: "Fashion Inspo"
        case .computerScience: "Computer Science"
        case .socialAnalysis: "Social Analysis"
        case .travel: "Travel Ideas"
        case .general: "General"
        }
    }

    var symbolName: String {
        switch self {
        case .applications: "doc.text.magnifyingglass"
        case .deadlines: "calendar.badge.exclamationmark"
        case .fashion: "tshirt"
        case .computerScience: "cpu"
        case .socialAnalysis: "chart.bar.xaxis"
        case .travel: "airplane"
        case .general: "tray.full"
        }
    }

    var tint: Color {
        switch self {
        case .applications: .purple
        case .deadlines: .red
        case .fashion: .pink
        case .computerScience: .blue
        case .socialAnalysis: .green
        case .travel: .orange
        case .general: .gray
        }
    }
}

private struct CalendarEvent: Identifiable {
    let id = UUID()
    let day: Int
    let month: String
    let title: String
    let source: String
    let kind: CalendarEventKind
    let provider: CalendarProvider

    static let samples = [
        CalendarEvent(day: 8, month: "MAY", title: "Scholarship application due", source: "Apple Calendar", kind: .deadline, provider: .apple),
        CalendarEvent(day: 14, month: "MAY", title: "CS research talk registration", source: "Google Calendar", kind: .reminder, provider: .google),
        CalendarEvent(day: 22, month: "MAY", title: "Portfolio submission deadline", source: "Apple Calendar", kind: .deadline, provider: .apple),
        CalendarEvent(day: 28, month: "MAY", title: "Portfolio critique", source: "Google Calendar", kind: .reminder, provider: .google)
    ]

    init(day: Int, month: String, title: String, source: String, kind: CalendarEventKind, provider: CalendarProvider) {
        self.day = day
        self.month = month
        self.title = title
        self.source = source
        self.kind = kind
        self.provider = provider
    }

    init?(classification: ScreenshotClassification) {
        guard classification.category == .timeSensitive else { return nil }

        let provider = classification.calendarProvider ?? .apple
        let parsedDay = classification.deadlineDate.flatMap { CalendarEvent.day(from: $0) } ?? 1

        self.init(
            day: parsedDay,
            month: "MAY",
            title: classification.calendarTitle ?? classification.title,
            source: provider == .apple ? "Apple Calendar" : "Google Calendar",
            kind: .deadline,
            provider: provider
        )
    }

    private static func day(from isoDate: String) -> Int? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoDate) {
            return Calendar.current.component(.day, from: date)
        }

        return Int(isoDate.split(separator: "-").last?.prefix(2) ?? "")
    }
}

private struct ScreenshotDraft: Identifiable {
    let id = UUID()
    var title: String
    var extractedText: String
    var category: ScreenshotCategory
    var topic: AlbumTopic
    var confidence: Double
    var recommendedAction: String
    var status: ScreenshotStatus

    var requiresManualReview: Bool {
        category == .topic && status == .needsReview
    }

    init(
        title: String,
        extractedText: String,
        category: ScreenshotCategory,
        topic: AlbumTopic,
        confidence: Double,
        recommendedAction: String,
        status: ScreenshotStatus
    ) {
        self.title = title
        self.extractedText = extractedText
        self.category = category
        self.topic = topic
        self.confidence = confidence
        self.recommendedAction = recommendedAction
        self.status = status
    }

    init(classification: ScreenshotClassification, extractedText: String) {
        self.init(
            title: classification.title,
            extractedText: extractedText,
            category: classification.category,
            topic: classification.folder,
            confidence: classification.confidence,
            recommendedAction: classification.recommendedAction,
            status: classification.category == .timeSensitive ? .calendarQueued : .needsReview
        )
    }

    static let samples = [
        ScreenshotDraft(
            title: "Application Portal",
            extractedText: "Deadline: May 8, 2026 at 11:59 PM. Submit transcript, resume, and short response.",
            category: .timeSensitive,
            topic: .applications,
            confidence: 0.68,
            recommendedAction: "Create calendar deadline",
            status: .calendarQueued
        ),
        ScreenshotDraft(
            title: "Runway Detail",
            extractedText: "Cropped blazer, silver flats, oversized tote, textured skirt.",
            category: .topic,
            topic: .fashion,
            confidence: 0.64,
            recommendedAction: "Add to topic album",
            status: .needsReview
        ),
        ScreenshotDraft(
            title: "Creator Metrics Thread",
            extractedText: "Watch time and save rate matter more than likes for long-term distribution.",
            category: .topic,
            topic: .socialAnalysis,
            confidence: 0.79,
            recommendedAction: "Add to topic album",
            status: .sorted
        ),
        ScreenshotDraft(
            title: "Compiler Notes",
            extractedText: "Lexing, parsing, AST generation, semantic analysis, intermediate representation.",
            category: .topic,
            topic: .computerScience,
            confidence: 0.71,
            recommendedAction: "Add to topic album",
            status: .needsReview
        )
    ]
}

private extension Color {
    static let notedGroupedBackground = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let notedSurface = Color(red: 1.0, green: 1.0, blue: 1.0)
    static let notedInsetSurface = Color(red: 0.94, green: 0.94, blue: 0.96)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
