// AddEventView.swift — Noted
// Import a screenshot and extract calendar events via OCR + Gemini

import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
#endif

struct AddEventView: View {
    @EnvironmentObject var vm: NotedViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var phase: Phase = .idle

    enum Phase { case idle, picked, processing, done, failed }

    var body: some View {
        ZStack {
            Color.nBg.ignoresSafeArea()

            VStack(spacing: 0) {
                DrawnHeader(
                    onBack: { vm.navPath.removeLast() },
                    onSettings: { vm.navPath.append(AppRoute.settings) }
                )

                // Hand-lettered "ADD EVENT" title (asset is stored vertically)
                Image("Add Event")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .rotationEffect(.degrees(90))
                    .frame(height: 60)
                    .padding(.top, 6)

                Spacer(minLength: 8)

                // Scan viewfinder: four hand-drawn corners around the content
                ZStack {
                    Image("Top Left Frame").resizable().scaledToFit()
                        .frame(width: 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Image("Top Right Frame").resizable().scaledToFit()
                        .frame(width: 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    Image("Bottom Left Frame").resizable().scaledToFit()
                        .frame(width: 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    Image("Bottom Right Frame").resizable().scaledToFit()
                        .frame(width: 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                    Group {
                        switch phase {
                        case .idle, .picked:
                            idleContent
                        case .processing:
                            processingContent
                        case .done:
                            doneContent
                        case .failed:
                            failedContent
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            phase = .picked
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    selectedImage = img
                    phase = .processing
                    await vm.processScreenshot(img)
                    phase = vm.processingMessage.isEmpty || !vm.isProcessing ? .done : .failed
                } else {
                    phase = .failed
                }
            }
        }
    }

    // MARK: - Phase Views

    private var idleContent: some View {
        VStack(spacing: 20) {
            // Center "+" — tap to pick a screenshot
            PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                Image("Add")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)

            Text("Tap to add a screenshot")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.nBrown)

            Text("Invites, reminders, deadlines\nand reservations all work.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.nBrown.opacity(0.45))
        }
    }

    private var processingContent: some View {
        VStack(spacing: 20) {
            if let img = selectedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.nBrown.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .nBrown.opacity(0.1), radius: 8, x: 0, y: 3)
            }

            HStack(spacing: 10) {
                ProgressView()
                    .tint(.nBrown)
                Text(vm.processingMessage)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.nBrown.opacity(0.7))
            }
        }
    }

    private var doneContent: some View {
        VStack(spacing: 16) {
            SparkleView()
                .frame(width: 80, height: 80)

            Text("Event detected!")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.nBrown)

            Text("Review the details and confirm\nbefore adding to your calendar.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.nBrown.opacity(0.55))
        }
    }

    private var failedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundColor(.nPink)

            Text(vm.processingMessage.isEmpty ? "Something went wrong." : vm.processingMessage)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.nBrown)

            PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                Text("Try another screenshot")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.nBrown.opacity(0.4), lineWidth: 1)
                    )
            }
            .onTapGesture { phase = .idle }
        }
    }
}

// MARK: - Scan illustration (SwiftUI-drawn, no image assets)

struct ScanIllustration: View {
    @State private var scanY: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pad: CGFloat = 10

            // Outer rounded rect (the "screenshot frame")
            let frameRect = CGRect(x: pad, y: pad + 6, width: w - pad * 2, height: h - pad * 2 - 6)
            var framePath = Path(roundedRect: frameRect, cornerRadius: 8)
            ctx.stroke(framePath, with: .color(Color.nBrown.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))

            // Corner ticks
            let tick: CGFloat = 8
            for corner in [
                CGPoint(x: frameRect.minX, y: frameRect.minY),
                CGPoint(x: frameRect.maxX, y: frameRect.minY),
                CGPoint(x: frameRect.minX, y: frameRect.maxY),
                CGPoint(x: frameRect.maxX, y: frameRect.maxY)
            ] {
                var tp = Path()
                let xDir: CGFloat = corner.x < w / 2 ? 1 : -1
                let yDir: CGFloat = corner.y < h / 2 ? 1 : -1
                tp.move(to: CGPoint(x: corner.x + xDir * tick, y: corner.y))
                tp.addLine(to: corner)
                tp.addLine(to: CGPoint(x: corner.x, y: corner.y + yDir * tick))
                ctx.stroke(tp, with: .color(Color.nBrown.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            // Scan line
            let scanLineY = frameRect.minY + scanY * (frameRect.height)
            var scanPath = Path()
            scanPath.move(to: CGPoint(x: frameRect.minX + 2, y: scanLineY))
            scanPath.addLine(to: CGPoint(x: frameRect.maxX - 2, y: scanLineY))
            ctx.stroke(scanPath, with: .color(Color.nMint.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.5))

            // Tiny text lines inside (decorative)
            for i in 0..<4 {
                let ly = frameRect.minY + frameRect.height * 0.25 + CGFloat(i) * 10
                var lp = Path()
                lp.move(to: CGPoint(x: frameRect.minX + 10, y: ly))
                lp.addLine(to: CGPoint(x: frameRect.maxX - (i % 2 == 0 ? 20 : 14), y: ly))
                ctx.stroke(lp, with: .color(Color.nBrown.opacity(0.18)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.2)) {
                scanY = 0.82
            }
        }
    }
}


