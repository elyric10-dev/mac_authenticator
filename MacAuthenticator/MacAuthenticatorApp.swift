import SwiftUI

@main
struct MacAuthenticatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AccountStore()
    @StateObject private var clock = TickingClock()
    @StateObject private var appController = AppController()

    var body: some Scene {
        MenuBarExtra("Authenticator", systemImage: "shield.lefthalf.filled") {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(clock)
                .environmentObject(appController)
        }
        .menuBarExtraStyle(.window)
    }
}
