// ScreenshotPreviewView.swift — Noted
// Full-screen screenshot viewer — fits the image to the screen, pinch to zoom.

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ScreenshotPreviewView: View {
    let image: UIImage
    @EnvironmentObject var vm: NotedViewModel
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.nBg.ignoresSafeArea()

            VStack(spacing: 8) {
                DrawnHeader(onBack: { if !vm.navPath.isEmpty { vm.navPath.removeLast() } })

                Text("Screenshot")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.nBrown)

                // Fit the image into the available space at a sensible size.
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(scale)
                            .frame(width: geo.size.width * scale, height: geo.size.height * scale)
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in scale = min(max(1, lastScale * val), 4) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scale = scale > 1.2 ? 1 : 2
                            lastScale = scale
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.nBrown.opacity(0.18), lineWidth: 1)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
