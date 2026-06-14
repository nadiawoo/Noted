// MainMenuView.swift — Noted
// Main Menu matching the NoteThisDown Figma (node 13:10):
// notebook + settings header, calendar card with D|W|M|Y toggle,
// and an "Upcoming Events:" card whose date badges are pink when
// unconfirmed and mint green when confirmed. Cozy, hand-drawn, warm.

import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var vm: NotedViewModel
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var calendarView: CalendarView = .month

    /// Upcoming events, always sorted chronologically (soonest first).
    private var filteredEvents: [NotedEvent] {
        let active = vm.events.filter { $0.status != .deleted }
        let scoped: [NotedEvent]
        if let d = selectedDate {
            scoped = active.filter { e in
                guard let ed = e.date else { return false }
                return Calendar.current.isDate(ed, inSameDayAs: d)
            }
        } else {
            scoped = active
        }
        return scoped.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.nBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        calendarCard
                        eventsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
            }

            addButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await vm.restoreAndImportGoogle()
        }
        .onAppear {
            // Auto-ingest new screenshots in the background (only if access
            // was already granted — never prompts here).
            vm.photoSync.start()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                vm.navPath.append(AppRoute.syncProgress)
            } label: {
                Image("Plans")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                vm.navPath.append(AppRoute.settings)
            } label: {
                Image("Settings")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Calendar card

    private var calendarCard: some View {
        MenuCard {
            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    Text("Calendar")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.nBrown)
                    Spacer()
                    CalendarViewToggle(selected: $calendarView)
                }

                switch calendarView {
                case .month:
                    MonthCalendarView(
                        displayedMonth:   $displayedMonth,
                        selectedDate:     $selectedDate,
                        confirmedDates:   vm.confirmedDates,
                        unconfirmedDates: vm.unconfirmedDates
                    )
                case .week:
                    WeekStripView(
                        selectedDate:     $selectedDate,
                        confirmedDates:   vm.confirmedDates,
                        unconfirmedDates: vm.unconfirmedDates
                    )
                case .day:
                    DayHeaderView(date: selectedDate ?? Date())
                case .year:
                    YearGridView(
                        selectedDate:     $selectedDate,
                        confirmedDates:   vm.confirmedDates,
                        unconfirmedDates: vm.unconfirmedDates
                    )
                }
            }
        }
    }

    // MARK: - Events card

    private var eventsCard: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedDate == nil ? "Upcoming Events:" : formattedSelectedDate)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.nBrown)
                    Spacer()
                    if selectedDate != nil {
                        Button("All") { withAnimation { selectedDate = nil } }
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.nBrown.opacity(0.6))
                    }
                }

                if filteredEvents.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredEvents) { event in
                            EventRow(event: event)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    vm.navPath.append(AppRoute.confirmEvent(event.id))
                                }
                        }
                    }

                    if filteredEvents.count > 2 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.nBrown.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 34))
                .foregroundColor(.nBrown.opacity(0.25))
            Text("No events yet.\nScan a screenshot to get started.")
                .multilineTextAlignment(.center)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.nBrown.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var formattedSelectedDate: String {
        guard let d = selectedDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: d)
    }

    // MARK: - Add (FAB)

    private var addButton: some View {
        Button {
            vm.navPath.append(AppRoute.addEvent)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.nBrown)
                    .frame(width: 58, height: 58)
                    .shadow(color: .nBrown.opacity(0.35), radius: 8, x: 2, y: 3)
                Image("Add")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .colorMultiply(.nBg)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 28)
    }
}

// MARK: - Menu Card (near-white, soft brown border)

struct MenuCard<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.55))
                    .shadow(color: .nBrown.opacity(0.08), radius: 6, x: 1, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.nBrown.opacity(0.22), lineWidth: 1)
            )
    }
}

// MARK: - D | W | M | Y Toggle

struct CalendarViewToggle: View {
    @Binding var selected: CalendarView
    private let options: [(CalendarView, String)] = [
        (.day, "D"), (.week, "W"), (.month, "M"), (.year, "Y")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                let (view, label) = opt
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selected = view }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: selected == view ? .bold : .regular, design: .rounded))
                        .foregroundColor(.nBrown)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected == view ? Color.nMint : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                if idx < options.count - 1 {
                    Text("|")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.nBrown.opacity(0.4))
                }
            }
        }
    }
}

// MARK: - Month Calendar

struct MonthCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date?
    let confirmedDates: Set<DateComponents>
    let unconfirmedDates: Set<DateComponents>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["Su","Mo","Tu","We","Th","Fr","Sa"]
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            // Month nav: ‹  [Month ⌄] [Year ⌄]  ›
            HStack(spacing: 8) {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.nBrown)
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    ForEach(1...12, id: \.self) { m in
                        Button(monthName(m)) { setComponent(.month, to: m) }
                    }
                } label: { pill(monthName(currentMonth)) }

                Menu {
                    ForEach(yearRange, id: \.self) { y in
                        Button(String(y)) { setComponent(.year, to: y) }
                    }
                } label: { pill(String(currentYear)) }

                Spacer()

                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.nBrown)
                }
                .buttonStyle(.plain)
            }

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.nBrown.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date:          day,
                            isSelected:    selectedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                            isToday:       cal.isDateInToday(day),
                            isConfirmed:   confirmedDates.contains(dc(day)),
                            isUnconfirmed: unconfirmedDates.contains(dc(day))
                        )
                        .onTapGesture {
                            selectedDate = cal.isDate(day, inSameDayAs: selectedDate ?? .distantFuture) ? nil : day
                        }
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func pill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.nBrown)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.nBrown.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.nBrown.opacity(0.25), lineWidth: 1)
        )
    }

    private var currentMonth: Int { cal.component(.month, from: displayedMonth) }
    private var currentYear: Int { cal.component(.year, from: displayedMonth) }
    private var yearRange: [Int] {
        let y = cal.component(.year, from: Date())
        return Array((y - 3)...(y + 5))
    }

    private func monthName(_ m: Int) -> String {
        DateFormatter().monthSymbols[m - 1]
    }

    private func setComponent(_ comp: Calendar.Component, to value: Int) {
        var comps = cal.dateComponents([.year, .month], from: displayedMonth)
        if comp == .month { comps.month = value } else { comps.year = value }
        comps.day = 1
        if let d = cal.date(from: comps) { displayedMonth = d }
    }

    private func changeMonth(_ delta: Int) {
        displayedMonth = cal.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }

    private func dc(_ date: Date) -> DateComponents {
        cal.dateComponents([.year, .month, .day], from: date)
    }

    private var calendarDays: [Date?] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)) else { return [] }
        let startWeekday = cal.component(.weekday, from: first) - 1
        let range = cal.range(of: .day, in: .month, for: displayedMonth)!
        var days: [Date?] = Array(repeating: nil, count: startWeekday)
        for d in range {
            days.append(cal.date(bySetting: .day, value: d, of: first))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isConfirmed: Bool
    let isUnconfirmed: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.nMint)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.nBrown.opacity(0.5), lineWidth: 1.2))
                } else if isConfirmed {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.nMint)
                } else if isToday {
                    Circle()
                        .fill(Color.nBrown.opacity(0.10))
                }

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday || isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(.nBrown.opacity(isToday || isSelected ? 1.0 : 0.8))
            }
            .frame(height: 36)

            // Pink dot for unconfirmed events
            if isUnconfirmed {
                Circle()
                    .fill(Color.nPink)
                    .frame(width: 7, height: 7)
                    .offset(x: -2, y: 2)
            }
        }
    }
}

// MARK: - Week Strip

struct WeekStripView: View {
    @Binding var selectedDate: Date?
    let confirmedDates: Set<DateComponents>
    let unconfirmedDates: Set<DateComponents>

    private let cal = Calendar.current

    private var weekDays: [Date] {
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1
        let sunday = cal.date(byAdding: .day, value: -weekday, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: sunday) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let dc = cal.dateComponents([.year, .month, .day], from: day)
                DayCell(
                    date:          day,
                    isSelected:    selectedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                    isToday:       cal.isDateInToday(day),
                    isConfirmed:   confirmedDates.contains(dc),
                    isUnconfirmed: unconfirmedDates.contains(dc)
                )
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    selectedDate = cal.isDate(day, inSameDayAs: selectedDate ?? .distantFuture) ? nil : day
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Day Header

struct DayHeaderView: View {
    let date: Date
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayOfWeek)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown.opacity(0.5))
                Text(dayNumber)
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundColor(.nBrown)
                Text(monthYear)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.nBrown.opacity(0.6))
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var dayOfWeek: String { DateFormatter().apply { $0.dateFormat = "EEEE" }.string(from: date) }
    private var dayNumber: String { DateFormatter().apply { $0.dateFormat = "d" }.string(from: date) }
    private var monthYear: String { DateFormatter().apply { $0.dateFormat = "MMMM yyyy" }.string(from: date) }
}

// MARK: - Year Grid

struct YearGridView: View {
    @Binding var selectedDate: Date?
    let confirmedDates: Set<DateComponents>
    let unconfirmedDates: Set<DateComponents>

    private let cal = Calendar.current
    private var months: [Date] {
        let year = cal.component(.year, from: Date())
        return (1...12).compactMap {
            cal.date(from: DateComponents(year: year, month: $0, day: 1))
        }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(months, id: \.self) { month in
                MiniMonthView(month: month, confirmedDates: confirmedDates, unconfirmedDates: unconfirmedDates)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MiniMonthView: View {
    let month: Date
    let confirmedDates: Set<DateComponents>
    let unconfirmedDates: Set<DateComponents>

    private let cal = Calendar.current
    private var label: String {
        DateFormatter().apply { $0.dateFormat = "MMM" }.string(from: month)
    }

    private var hasActivity: Bool {
        let comps = cal.dateComponents([.year, .month], from: month)
        let hasConf = confirmedDates.contains { $0.year == comps.year && $0.month == comps.month }
        let hasUnconf = unconfirmedDates.contains { $0.year == comps.year && $0.month == comps.month }
        return hasConf || hasUnconf
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.nBrown)
            Circle()
                .fill(hasActivity ? Color.nMint : Color.clear)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.nParchment.opacity(0.5)))
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: NotedEvent

    private var isConfirmed: Bool { event.status == .confirmed }

    var body: some View {
        HStack(spacing: 12) {
            dateBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Untitled Event" : event.title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown)
                    .lineLimit(1)

                Rectangle()
                    .fill(Color.nBrown.opacity(0.25))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(detailLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.nBrown.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.nBrown.opacity(0.35))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.nBrown.opacity(0.33), lineWidth: 1)
        )
    }

    // Pink when unconfirmed, mint green when confirmed.
    private var dateBadge: some View {
        VStack(spacing: 0) {
            if let date = event.date {
                Text(monthString(date))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.nBrown)
                Text(dayString(date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.nBrown)
            } else {
                Image(systemName: "calendar.badge.questionmark")
                    .font(.system(size: 20))
                    .foregroundColor(.nBrown.opacity(0.6))
            }
        }
        .frame(width: 51, height: 51)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isConfirmed ? Color.nMint : Color.nPink.opacity(0.44))
        )
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if !event.location.isEmpty { lines.append(event.location) }
        if !event.notes.isEmpty { lines.append(event.notes) }
        if lines.isEmpty {
            lines.append(isConfirmed ? "Confirmed" : "Needs review")
        }
        return Array(lines.prefix(2))
    }

    private func dayString(_ d: Date) -> String {
        DateFormatter().apply { $0.dateFormat = "d" }.string(from: d)
    }
    private func monthString(_ d: Date) -> String {
        DateFormatter().apply { $0.dateFormat = "MMM" }.string(from: d)
    }
}

// MARK: - Parchment Card (used by Settings)

struct ParchmentCard<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.nParchment)
                    .shadow(color: .nBrown.opacity(0.1), radius: 6, x: 1, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.nBrown.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - Helpers

extension DateFormatter {
    @discardableResult
    func apply(_ block: (DateFormatter) -> Void) -> DateFormatter {
        block(self); return self
    }
}
