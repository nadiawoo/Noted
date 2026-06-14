// ConfirmEventView.swift — Noted
// Matches the warm, hand-drawn Figma design: date badge + compact fields + sketch buttons

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Main View

struct ConfirmEventView: View {
    let eventID: UUID
    let initial: NotedEvent

    @EnvironmentObject var vm: NotedViewModel
    @State private var event: NotedEvent
    @State private var showDateEditor  = false
    @State private var showDeleteAlert = false
    @State private var showPoof        = false
    @FocusState private var focused: ConfirmField?

    enum ConfirmField: Hashable { case title, location, guests, notes }

    init(eventID: UUID, initial: NotedEvent) {
        self.eventID = eventID
        self.initial = initial
        _event = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            Color.nBg.ignoresSafeArea()

            VStack(spacing: 0) {
                DrawnHeader(
                    onBack: { vm.navPath.removeLast() },
                    onSettings: { vm.navPath.append(AppRoute.settings) }
                )

                ScrollView {
                    VStack(spacing: 24) {

                        // ── Hand-lettered title ─────────────────────
                        VStack(spacing: 8) {
                            Image("ConfirmEvent")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 36)
                            confidencePill
                        }
                        .padding(.top, 4)

                        // ── Event card ──────────────────────────────
                        VStack(spacing: 12) {
                            // Date badge + title + quick meta
                            HStack(alignment: .top, spacing: 12) {
                                dateBadge
                                    .onTapGesture { withAnimation(.easeInOut) { showDateEditor.toggle() } }

                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Event title", text: $event.title, axis: .vertical)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.nBrown)
                                        .tint(.nBrown)
                                        .lineLimit(1...2)
                                        .focused($focused, equals: .title)
                                    Rectangle()
                                        .fill(Color.nBrown.opacity(0.35))
                                        .frame(height: 0.75)
                                    HStack(spacing: 8) {
                                        kindMenu
                                        Spacer(minLength: 0)
                                        Button { withAnimation(.easeInOut) { showDateEditor.toggle() } } label: {
                                            Text(dateSummary)
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundColor(.nBrown.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if showDateEditor { dateEditor }

                            VStack(spacing: 10) {
                                labeledField(icon: "mappin", label: "Location",
                                             placeholder: "Add location…",
                                             text: $event.location, field: .location)
                                labeledField(icon: "person.2", label: "Guests",
                                             placeholder: "Add guests…",
                                             text: $event.guests, field: .guests)
                                labeledField(icon: "text.alignleft", label: "Description",
                                             placeholder: "Add a description…",
                                             text: $event.notes, field: .notes, multiline: true)
                                reminderField
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.nBrown.opacity(0.33), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        // ── Hand-drawn action buttons ───────────────
                        VStack(spacing: 16) {
                            if event.sourceImage != nil {
                                Button {
                                    vm.navPath.append(AppRoute.screenshotPreview(eventID))
                                } label: {
                                    Image("ViewScreenshot")
                                        .resizable().scaledToFit()
                                        .frame(height: 58)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                Task { await confirmEvent() }
                            } label: {
                                Image("Confirm")
                                    .resizable().scaledToFit()
                                    .frame(height: 46)
                            }
                            .buttonStyle(.plain)

                            Button { showDeleteAlert = true } label: {
                                Image("Detele")
                                    .resizable().scaledToFit()
                                    .frame(height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 48)
                    }
                }
            }

            // Poof animation overlay
            if showPoof {
                poofOverlay
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown)
            }
        }
        .alert("Delete this event?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { vm.delete(id: eventID) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from Noted.")
        }
    }

    // MARK: - Sub-views

    private var dateBadge: some View {
        VStack(spacing: 0) {
            if let date = event.date {
                Text(monthStr(date))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.nBrown)
                    .padding(.top, 6)
                Text(dayStr(date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.nBrown)
                    .padding(.bottom, 6)
            } else {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20))
                    .foregroundColor(.nBrown)
                    .padding(8)
            }
        }
        .frame(width: 51, height: 51)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(event.status == .confirmed ? Color.nMint : Color.nPink.opacity(0.44))
        )
    }

    // An editable field that grows into a larger box while you're typing in it.
    @ViewBuilder
    private func labeledField(
        icon: String,
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: ConfirmField,
        multiline: Bool = false
    ) -> some View {
        let isFocused = focused == field
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.nBrown.opacity(0.55))
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.nBrown.opacity(0.5))
                TextField(placeholder, text: text, axis: .vertical)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.nBrown)
                    .tint(.nBrown)
                    .lineLimit(multiline ? (isFocused ? 4...10 : 1...3) : 1...2)
                    .focused($focused, equals: field)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(isFocused ? Color.white : Color.nBrown.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isFocused ? Color.nBrown.opacity(0.6) : Color.nBrown.opacity(0.25),
                              lineWidth: isFocused ? 1.4 : 0.8)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .contentShape(Rectangle())
        .onTapGesture { focused = field }
    }

    private var reminderField: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.system(size: 13))
                .foregroundColor(.nBrown.opacity(0.55))
                .frame(width: 18)
            Text("Reminder")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.nBrown.opacity(0.5))
            Spacer()
            Menu {
                ForEach(ReminderOffset.allCases) { r in
                    Button(r.rawValue) { event.reminder = r }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(event.reminder.rawValue)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.nBrown)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.nBrown.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.nBrown.opacity(0.25), lineWidth: 0.8))
    }

    // Quick event-type presets (also sets all-day + a sensible default reminder).
    private var kindMenu: some View {
        Menu {
            ForEach(EventKind.allCases) { k in
                Button { applyKind(k) } label: { Label(k.label, systemImage: k.symbolName) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: event.kind.symbolName).font(.system(size: 10))
                Text(event.kind.label).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.nBrown)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.nMint.opacity(0.7)))
        }
    }

    private func applyKind(_ k: EventKind) {
        withAnimation(.easeInOut) {
            event.kind = k
            event.hasTime = k.timeUsuallyMatters
            event.reminder = k.defaultReminder
            if let d = event.date {
                event.endDate = Calendar.current.date(byAdding: event.hasTime ? .hour : .day, value: 1, to: d)
            }
        }
    }

    private var dateEditor: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.nBrown)

            Toggle(isOn: Binding(
                get: { !event.hasTime },
                set: { isAllDay in
                    event.hasTime = !isAllDay
                    if let d = event.date {
                        event.endDate = Calendar.current.date(byAdding: event.hasTime ? .hour : .day, value: 1, to: d)
                    }
                }
            )) {
                Text("All-day")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown)
            }
            .tint(.nMint)

            if event.hasTime {
                DatePicker("Time", selection: dateBinding, displayedComponents: .hourAndMinute)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.nBrown)
                    .tint(.nBrown)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.nParchment.opacity(0.5)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { event.date ?? Date() },
            set: { d in
                event.date = d
                event.endDate = Calendar.current.date(byAdding: event.hasTime ? .hour : .day, value: 1, to: d)
            }
        )
    }

    private var dateSummary: String {
        guard let d = event.date else { return "Set date ›" }
        let f = DateFormatter()
        f.dateFormat = event.hasTime ? "EEE, MMM d · h:mm a" : "EEE, MMM d"
        let s = f.string(from: d)
        return event.hasTime ? s : "\(s) · All-day"
    }

    private var confidencePill: some View {
        let pct   = Int(initial.confidence * 100)
        let isHigh = initial.confidence >= 0.80
        return Text("\(pct)% confidence")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.nBrown.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isHigh ? Color.nMint : Color.nPink.opacity(0.6))
            )
    }

    private var poofOverlay: some View {
        ZStack {
            Color.nBg.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                // Sparkle drawing
                SparkleView()
                    .frame(width: 100, height: 100)

                Text("Event Added!")
                    .kerning(1)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown)

                Text("Check your calendar.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.nBrown.opacity(0.5))
            }
        }
    }

    // MARK: - Actions

    private func confirmEvent() async {
        withAnimation(.easeIn(duration: 0.2)) { showPoof = true }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await vm.confirm(id: eventID, updated: event)
    }

    // MARK: - Helpers

    private func monthStr(_ d: Date) -> String {
        DateFormatter().apply { $0.dateFormat = "MMM" }.string(from: d).uppercased()
    }
    private func dayStr(_ d: Date) -> String {
        DateFormatter().apply { $0.dateFormat = "d" }.string(from: d)
    }
}

// MARK: - Sketch Button (hand-drawn border)

struct SketchButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .overlay(
                    SketchedRect(wiggle: 2.2)
                        .stroke(Color.nBrown, lineWidth: 1.4)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sketched Rectangle Shape

struct SketchedRect: Shape {
    var wiggle: CGFloat = 2.0
    var pad: CGFloat = 2.0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: pad, dy: pad)
        let w = wiggle
        var p = Path()

        // Top-left → top-right (top edge bows ever so slightly)
        p.move(to: CGPoint(x: r.minX + 5, y: r.minY + w * 0.4))
        p.addCurve(
            to:       CGPoint(x: r.maxX - 5,    y: r.minY - w * 0.2),
            control1: CGPoint(x: r.minX + r.width * 0.35, y: r.minY - w * 0.5),
            control2: CGPoint(x: r.minX + r.width * 0.70, y: r.minY + w * 0.3)
        )

        // Top-right corner
        p.addQuadCurve(
            to:      CGPoint(x: r.maxX + w * 0.3, y: r.minY + 5),
            control: CGPoint(x: r.maxX + w * 0.4, y: r.minY - w * 0.3)
        )

        // Right edge
        p.addCurve(
            to:       CGPoint(x: r.maxX + w * 0.1, y: r.maxY - 5),
            control1: CGPoint(x: r.maxX + w * 0.6, y: r.minY + r.height * 0.3),
            control2: CGPoint(x: r.maxX - w * 0.2, y: r.minY + r.height * 0.7)
        )

        // Bottom-right corner
        p.addQuadCurve(
            to:      CGPoint(x: r.maxX - 5,    y: r.maxY + w * 0.3),
            control: CGPoint(x: r.maxX + w * 0.4, y: r.maxY + w * 0.4)
        )

        // Bottom edge
        p.addCurve(
            to:       CGPoint(x: r.minX + 5,    y: r.maxY + w * 0.15),
            control1: CGPoint(x: r.minX + r.width * 0.65, y: r.maxY + w * 0.55),
            control2: CGPoint(x: r.minX + r.width * 0.30, y: r.maxY - w * 0.1)
        )

        // Bottom-left corner
        p.addQuadCurve(
            to:      CGPoint(x: r.minX - w * 0.3, y: r.maxY - 5),
            control: CGPoint(x: r.minX - w * 0.4, y: r.maxY + w * 0.3)
        )

        // Left edge
        p.addCurve(
            to:       CGPoint(x: r.minX - w * 0.1, y: r.minY + 5),
            control1: CGPoint(x: r.minX - w * 0.5, y: r.maxY - r.height * 0.3),
            control2: CGPoint(x: r.minX + w * 0.2, y: r.maxY - r.height * 0.7)
        )

        // Top-left corner back to start
        p.addQuadCurve(
            to:      CGPoint(x: r.minX + 5, y: r.minY + w * 0.4),
            control: CGPoint(x: r.minX - w * 0.3, y: r.minY - w * 0.2)
        )

        return p
    }
}

// MARK: - Sparkle / Poof animation (SwiftUI-drawn, no image assets)

/// A warm, hand-drawn sun — wobbly ink circle with uneven, tapered rays.
/// Intentionally imperfect so it reads as sketched rather than generated.
struct SparkleView: View {
    @State private var appeared = false
    @State private var wiggle   = false

    private let rays = 11
    private let sunFill = Color(red: 0.97, green: 0.85, blue: 0.55) // soft warm yellow

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let bodyR: CGFloat = 19
            let ink = Color.nBrown

            // Rays: each one a slightly different length and angle, tapered ends.
            let step = CGFloat.pi * 2 / CGFloat(rays)
            for i in 0..<rays {
                // Deterministic per-ray jitter so it looks hand-placed, not uniform.
                let j = CGFloat(i)
                let angleJitter = sin(j * 1.7) * 0.06
                let lenJitter   = 0.5 + (sin(j * 2.3) + 1) / 2 * 0.7   // 0.5…1.2
                let angle = step * j - .pi / 2 + angleJitter + (wiggle ? 0.02 : -0.02)

                let inner = bodyR + 5
                let outer = inner + 9 + 11 * lenJitter
                let p1 = CGPoint(x: c.x + inner * cos(angle), y: c.y + inner * sin(angle))
                let p2 = CGPoint(x: c.x + outer * cos(angle), y: c.y + outer * sin(angle))

                // Slightly bowed ray (control point nudged sideways) for a drawn feel.
                let mid = CGPoint(x: (p1.x + p2.x) / 2 + sin(j * 3.1) * 2.0,
                                  y: (p1.y + p2.y) / 2 + cos(j * 2.7) * 2.0)
                var ray = Path()
                ray.move(to: p1)
                ray.addQuadCurve(to: p2, control: mid)
                ctx.stroke(ray, with: .color(ink.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }

            // Sun body: a wobbly, not-quite-round circle.
            let body = Self.wobblyCircle(center: c, radius: bodyR, points: 30)
            ctx.fill(body, with: .color(sunFill.opacity(0.55)))
            ctx.stroke(body, with: .color(ink),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

            // A tiny off-center smile + dots, sketched.
            var smile = Path()
            smile.move(to: CGPoint(x: c.x - 6, y: c.y + 4))
            smile.addQuadCurve(to: CGPoint(x: c.x + 6, y: c.y + 4),
                               control: CGPoint(x: c.x, y: c.y + 9))
            ctx.stroke(smile, with: .color(ink.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            for dx in [-6.0, 6.0] {
                let eye = Path(ellipseIn: CGRect(x: c.x + dx - 1.3, y: c.y - 4, width: 2.6, height: 2.6))
                ctx.fill(eye, with: .color(ink.opacity(0.8)))
            }
        }
        .frame(width: 110, height: 110)
        .scaleEffect(appeared ? 1 : 0.5)
        .rotationEffect(.degrees(appeared ? 0 : -12))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { wiggle = true }
        }
    }

    /// Builds a closed circle whose radius gently varies, so the outline looks
    /// drawn by hand rather than struck by a compass.
    private static func wobblyCircle(center: CGPoint, radius: CGFloat, points: Int) -> Path {
        var p = Path()
        for i in 0...points {
            let t = CGFloat(i) / CGFloat(points) * 2 * .pi
            let r = radius + sin(t * 3 + 0.6) * 1.1 + cos(t * 5 + 1.2) * 0.7
            let pt = CGPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
