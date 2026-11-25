import SwiftUI
import AppKit

@main
struct PixelPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = PlayerModel.shared

    var body: some Scene {
        WindowGroup("PixelPlayer", id: "main") {
            RootView()
                .environment(model)
                .tint(PP.primary)
        }
        // No toolbar band at the top: the content runs to the edge and the traffic lights sit in the sidebar.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        Settings {
            SettingsView()
                .environment(model)
                .tint(PP.primary)
        }
        // Not in the menu bar during scripted captures, so a run leaves nothing behind on the screen.
        MenuBarExtra("PixelPlayer", systemImage: "music.note", isInserted: .constant(!Debug.active)) {
            MenuBarPanel()
                .environment(model)
                .tint(PP.primary)
                .focusEffectDisabled()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Debug.launch()
        NSApp.activate()
        // New versions from GitHub: at launch, when the app comes to the front, and every hour. The Dev build never looks.
        Updater.shared.checkIfDue()
        Updater.shared.startPeriodicChecks()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Updater.shared.checkIfDue()
    }
}
