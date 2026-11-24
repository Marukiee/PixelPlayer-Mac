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
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandMenu("Richting") {
                ForEach(Array(Direction.allCases.enumerated()), id: \.element) { index, direction in
                    Button(direction.title) { model.direction = direction }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
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
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Debug.launch()
        NSApp.activate()
    }
}
