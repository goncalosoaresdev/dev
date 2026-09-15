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
        ApplicationIcon.refresh()
        menuBar = MenuBarController(environment: environment)
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}

@MainActor
enum ApplicationIcon {
    static func refresh() {
        // Read the actual bundle file: the system's cached application image can
        // outlive a local rebuild, especially when switching out of accessory mode.
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              let url = Bundle.main.url(
                forResource: name,
                withExtension: (name as NSString).pathExtension.isEmpty ? "icns" : nil
              ),
              let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }
}
