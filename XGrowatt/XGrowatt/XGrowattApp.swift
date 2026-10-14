//
//  XGrowattApp.swift
//  XGrowatt
//
//  Created by xx on 27/6/2026.
//

import SwiftUI
import FirebaseCore
import FirebaseAppCheck

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // App Check: Use debug provider in DEBUG builds, App Attest in production
        #if DEBUG
        // In DEBUG mode, App Check prints your debug token to Xcode console.
        // Copy that token and register it at:
        // Firebase Console → App Check → iOS App → Debug tokens → Add token
        let providerFactory = AppCheckDebugProviderFactory()
        #else
        // In production, use Apple's App Attest (requires iOS 14+)
        let providerFactory = AppAttestProvider.self  // handled automatically by default
        #endif

        AppCheck.setAppCheckProviderFactory(providerFactory)
        FirebaseApp.configure()

        return true
    }
}

@main
struct XGrowattApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
