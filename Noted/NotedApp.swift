//
//  NotedApp.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
//

import SwiftUI
import FirebaseAppCheck
import FirebaseCore
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#endif

private enum FirebaseBootstrap {
    static func configure() {
#if targetEnvironment(simulator)
#if DEBUG
        AppCheckDebugTokenLoader.applyLocalTokenIfAvailable()
#endif
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
#endif
        FirebaseApp.configure()
    }
}

#if DEBUG && targetEnvironment(simulator)
private enum AppCheckDebugTokenLoader {
    static func applyLocalTokenIfAvailable() {
        guard
            let url = Bundle.main.url(forResource: "AppCheckDebugToken", withExtension: "plist"),
            let tokenConfig = NSDictionary(contentsOf: url),
            let token = tokenConfig["FIRAAppCheckDebugToken"] as? String,
            token.isEmpty == false,
            token != "PASTE_YOUR_FIREBASE_APP_CHECK_DEBUG_TOKEN_HERE"
        else {
            return
        }

        setenv("FIRAAppCheckDebugToken", token, 1)
    }
}
#endif

#if canImport(UIKit)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()

        return true
    }
}
#endif

@main
struct NotedApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
#else
    init() {
        FirebaseBootstrap.configure()
    }
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
