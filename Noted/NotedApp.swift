//
//  NotedApp.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
//

import SwiftUI
import FirebaseCore
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

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
        FirebaseApp.configure()
    }
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
