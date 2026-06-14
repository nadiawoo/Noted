// SyncProgressView.swift — Noted
// Reached from the "Plans" notebook icon in the top-left of the Main Menu.
//
// Shows, in the center, a hand-drawn wheel whose ring fills with how many of
// the screenshots in the user's album the app has reviewed. Below it sits a
// contextual action: grant access, sync new screenshots, or — when the user
// granted *limited* access — add more screenshots to the selection.

import SwiftUI
#if os(iOS)
import Photos

struct SyncProgressView: View {
    @EnvironmentObject var vm: NotedViewModel
    @ObservedObject var sync: PhotoLibrarySync

    var body: some View {
        ZStack {
            Color.nBg.ignoresSafeArea()

            VStack(spacing: 0) {
                DrawnHeader(onBack: { if !vm.navPath.isEmpty { vm.navPath.removeLast() } })

                Text("Screenshot Sync")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.nBrown)
                    .padding(.top, 4)

                Spacer()

                ProgressWheel(
                    progress:  sync.progress,
                    processed: sync.processedScreenshots,
                    total:     sync.totalScreenshots,
                    spinning:  sync.isSyncing
                )
                .frame(width: 240, height: 240)

                statusLabel
                    .padding(.top, 18)

                Spacer()

                actions
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { sync.start() }
    }

    // MARK: - Status line

    @ViewBuilder
    private var statusLabel: some View {
        let text: String = {
            switch sync.authorization {
            case .notDetermined:
                return "Allow access to scan your screenshots\nfor events and deadlines automatically."
            case .denied, .restricted:
                return "Photo access is off. Enable it in Settings\nso Noted can find events for you."
            default:
                if sync.isSyncing {
                    return "Reviewing your screenshots…"
                } else if sync.totalScreenshots == 0 {
                    return "No screenshots found yet."
                } else if sync.pendingCount == 0 {
                    return "All caught up — \(sync.totalScreenshots) screenshots reviewed."
                } else {
                    return "\(sync.pendingCount) new screenshot\(sync.pendingCount == 1 ? "" : "s") to review."
                }
            }
        }()

        Text(text)
            .multilineTextAlignment(.center)
            .font(.system(size: 14, design: .rounded))
            .foregroundColor(.nBrown.opacity(0.6))
    }

    // MARK: - Contextual actions

    @ViewBuilder
    private var actions: some View {
        switch sync.authorization {
        case .notDetermined:
            primaryButton("Allow screenshot access") {
                Task { await sync.requestAccessAndSync() }
            }

        case .denied, .restricted:
            primaryButton("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

        default:
            VStack(spacing: 12) {
                if sync.isSyncing {
                    primaryButton("Syncing…", disabled: true) {}
                } else if sync.pendingCount > 0 {
                    primaryButton("Sync new images") { sync.refresh() }
                } else {
                    primaryButton("Up to date", disabled: true) {}
                }

                // Limited access → let the user widen the selection.
                if sync.isLimited {
                    secondaryButton("Add more screenshots") {
                        sync.presentLimitedPicker()
                    }
                }

                // Reach back past the 30-day window on demand.
                secondaryButton("Sync older screenshots") {
                    sync.syncEntireLibrary()
                }
            }
        }
    }

    private func primaryButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.nBg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.nBrown.opacity(disabled ? 0.35 : 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.nBrown)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.nBrown.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hand-drawn progress wheel

struct ProgressWheel: View {
    let progress: Double      // 0…1
    let processed: Int
    let total: Int
    var spinning: Bool = false

    @State private var spin = false

    var body: some View {
        ZStack {
            // Hand-drawn dashed outer ring (the "sketch" feel).
            Circle()
                .stroke(
                    Color.nBrown.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1.5, dash: [2, 4])
                )
                .padding(4)

            // Track.
            Circle()
                .stroke(Color.nBrown.opacity(0.12), lineWidth: 16)
                .padding(22)

            // Progress arc.
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    progress >= 1 ? Color.nMint : Color.nPink,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(22)
                .animation(.easeInOut(duration: 0.4), value: progress)

            // A little orbiting dot while actively syncing.
            if spinning {
                Circle()
                    .fill(Color.nPink)
                    .frame(width: 12, height: 12)
                    .offset(y: -97)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }

            // Center readout.
            VStack(spacing: 2) {
                if total == 0 {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 30))
                        .foregroundColor(.nBrown.opacity(0.4))
                } else {
                    Text("\(processed)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.nBrown)
                    Text("of \(total)")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.nBrown.opacity(0.55))
                    Text("screenshots")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.nBrown.opacity(0.45))
                }
            }
        }
    }
}
#endif
