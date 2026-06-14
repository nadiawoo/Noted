// SettingsView.swift — Noted
// Calendar connections and app preferences

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: NotedViewModel

    var body: some View {
        ZStack {
            Color.nBg.ignoresSafeArea()

            VStack(spacing: 0) {
                DrawnHeader(onBack: { vm.navPath.removeLast() })

                ScrollView {
                    VStack(spacing: 20) {
                    // Title
                    VStack(spacing: 4) {
                        Image("Settings")
                            .resizable().scaledToFit()
                            .frame(width: 40, height: 36)
                        Text("Settings")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundColor(.nBrown)
                    }
                    .padding(.top, 4)

                    // Google Calendar
                    ParchmentCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Google Calendar", systemImage: "g.circle.fill")
                                .font(.system(size: 15, weight: .medium, design: .serif))
                                .foregroundColor(.nBrown)

                            if vm.googleCalVM.isSignedIn {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Connected")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.nBrown)
                                        Text(vm.googleCalVM.accountEmail ?? "")
                                            .font(.system(size: 12))
                                            .foregroundColor(.nBrown.opacity(0.6))
                                    }
                                    Spacer()
                                    Circle().fill(Color.nMint).frame(width: 10, height: 10)
                                }

                                Button {
                                    vm.googleCalVM.signOut()
                                } label: {
                                    Text("Disconnect")
                                        .font(.system(size: 14, design: .serif))
                                        .foregroundColor(.nPink)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Color.nPink.opacity(0.5), lineWidth: 1)
                                        )
                                }
                            } else {
                                Text("Not connected")
                                    .font(.system(size: 13))
                                    .foregroundColor(.nBrown.opacity(0.5))

                                Button {
                                    Task {
                                        let imported = await vm.googleCalVM.connectAndImport()
                                        vm.importGoogleEvents(imported)
                                    }
                                } label: {
                                    Text("Connect Google Calendar")
                                        .font(.system(size: 14, weight: .medium, design: .serif))
                                        .foregroundColor(.nBg)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.nBrown))
                                }
                            }

                            if let msg = vm.googleCalVM.statusMessage, !msg.isEmpty {
                                Text(msg)
                                    .font(.system(size: 12))
                                    .foregroundColor(.nBrown.opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Apple Calendar note
                    ParchmentCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Apple Calendar", systemImage: "apple.logo")
                                .font(.system(size: 15, weight: .medium, design: .serif))
                                .foregroundColor(.nBrown)
                            Text("Apple Calendar events are added automatically when you confirm an event with Apple Calendar selected. Grant access when prompted.")
                                .font(.system(size: 13))
                                .foregroundColor(.nBrown.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Pending events summary
                    let unconfirmed = vm.events.filter { $0.status == .unconfirmed }
                    if !unconfirmed.isEmpty {
                        ParchmentCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Pending Review", systemImage: "exclamationmark.circle")
                                    .font(.system(size: 15, weight: .medium, design: .serif))
                                    .foregroundColor(.nBrown)
                                Text("\(unconfirmed.count) event\(unconfirmed.count == 1 ? "" : "s") waiting for confirmation.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.nBrown.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // App info
                    VStack(spacing: 4) {
                        Text("noted.")
                            .font(.system(size: 15, weight: .light, design: .serif))
                            .foregroundColor(.nBrown.opacity(0.4))
                        Text("Screenshot → Calendar, automatically.")
                            .font(.system(size: 12))
                            .foregroundColor(.nBrown.opacity(0.3))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { vm.googleCalVM.restoreSession() }
    }
}
