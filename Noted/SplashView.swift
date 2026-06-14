// SplashView.swift — Noted
// Splash: hand-drawn "NOTED" wordmark centered on warm cream (Figma node 10:2)

import SwiftUI

struct SplashView: View {
    @State private var logoOpacity = 0.0
    @State private var logoScale   = 0.86

    var body: some View {
        ZStack {
            Color.nBg.ignoresSafeArea()

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 240)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) {
                logoOpacity = 1
                logoScale   = 1
            }
        }
    }
}
