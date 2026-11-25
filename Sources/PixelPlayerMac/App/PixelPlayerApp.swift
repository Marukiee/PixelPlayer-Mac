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
        .commands { PlaybackCommands(model: model) }
        .defaultSize(width: 1280, height: 800)
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Once: forget the sidebar width macOS saved from earlier versions, so the new, wider default shows.
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: "layout.version") < 2 {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSSplitView Subview Frames") {
                defaults.removeObject(forKey: key)
            }
            defaults.set(2, forKey: "layout.version")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Debug.launch()
        NSApp.activate()
        // The spacebar plays and pauses, as in Spotify, unless you are typing. Without this it pressed whatever button had
        // keyboard focus, such as Lyrics.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let typing = NSApp.keyWindow?.firstResponder is NSText
            guard event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty, !typing,
                  NSApp.keyWindow?.attachedSheet == nil else { return event }
            MainActor.assumeIsolated {
                let model = PlayerModel.shared
                // A sheet of its own (the welcome, song info) keeps the spacebar for its buttons.
                guard !model.showOnboarding, model.infoSong == nil else { return }
                model.setPlaying(!model.isPlaying)
            }
            return nil
        }
        // macOS starts a fresh window with a narrow sidebar, whatever its minimum says; give it its intended width once.
        for delay in [0.2, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.widenSidebar() }
        }
        // New versions from GitHub: at launch, when the app comes to the front, and every hour. The Dev build never looks.
        Updater.shared.checkIfDue()
        Updater.shared.startPeriodicChecks()
    }

    static func widenSidebar() {
        func split(in view: NSView?) -> NSSplitView? {
            guard let view else { return nil }
            if let found = view as? NSSplitView { return found }
            for child in view.subviews { if let found = split(in: child) { return found } }
            return nil
        }
        for window in NSApp.windows where window.isVisible && window.frame.width > 800 {
            guard let split = split(in: window.contentView), let sidebar = split.arrangedSubviews.first,
                  sidebar.frame.width < 260 else { continue }
            split.setPosition(280, ofDividerAt: 0)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Updater.shared.checkIfDue()
    }
}

/// The Controls menu, with the shortcuts of Spotify on the Mac, so hands that know Spotify feel at home.
struct PlaybackCommands: Commands {
    let model: PlayerModel

    var body: some Commands {
        CommandMenu("Controls") {
            Button(model.isPlaying ? "Pause" : "Play") { model.setPlaying(!model.isPlaying) }
            Button("Next") { Playback.shared.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { Playback.shared.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Seek Forward") { model.seek(to: min(model.duration, model.position + 5)) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button("Seek Backward") { model.seek(to: max(0, model.position - 5)) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            Divider()
            Button("Volume Up") { model.groupVolume = min(100, model.groupVolume + 10) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { model.groupVolume = max(0, model.groupVolume - 10) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Toggle("Shuffle", isOn: Binding(get: { model.shuffle }, set: { model.shuffle = $0 }))
                .keyboardShortcut("s", modifiers: .command)
            Toggle("Repeat", isOn: Binding(get: { model.repeatAll }, set: { model.repeatAll = $0 }))
                .keyboardShortcut("r", modifiers: .command)
            Button(model.liked ? "Remove from Liked Songs" : "Save to Liked Songs") { model.liked.toggle() }
                .keyboardShortcut("b", modifiers: [.option, .shift])
                .disabled(model.current.id.isEmpty)
            Divider()
            Button("Search") { model.go(.search) }
                .keyboardShortcut("l", modifiers: .command)
            Button(model.showQueue ? "Hide Queue" : "Show Queue") { withAnimation(Motion.panel) { model.showQueue.toggle() } }
                .keyboardShortcut("q", modifiers: [.option, .shift])
            Button(model.fullPlayer ? "Hide Lyrics" : "Show Lyrics") { model.setFullPlayer(!model.fullPlayer) }
                .keyboardShortcut("l", modifiers: [.option, .shift])
        }
    }
}
