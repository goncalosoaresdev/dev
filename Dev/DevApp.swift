import SwiftUI

@main
struct DevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Kept so SwiftUI has a scene. The real window is opened by SettingsWindowController.
        Settings {
            SettingsView()
                .environment(appDelegate.environment)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.environment.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(environment: environment)
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}
