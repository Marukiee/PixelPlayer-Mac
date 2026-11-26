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
        MenuBarExtra("PixelPlayer", systemImage: "music.note", isInserted: MenuBarSetting.shared.binding) {
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
        // Before the window shows, so it never flashes light on a Mac set to light.
        Appearance.apply(Appearance.saved)
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
        // The back and forward buttons on the side of a mouse.
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber == 3 || event.buttonNumber == 4 else { return event }
            MainActor.assumeIsolated {
                if event.buttonNumber == 3 { PlayerModel.shared.goBack() } else { PlayerModel.shared.goForward() }
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

    nonisolated(unsafe) static var lastScan = Date.now

    static func widenSidebar() {
        func split(in view: NSView?) -> NSSplitView? {
            guard let view else { return nil }
            if let found = view as? NSSplitView { return found }
            for child in view.subviews { if let found = split(in: child) { return found } }
            return nil
        }
        for window in NSApp.windows where window.isVisible && window.frame.width > 800 {
            // Nothing focused at the start, so the search field does not open with a blue ring around it.
            window.makeFirstResponder(nil)
            guard let split = split(in: window.contentView), let sidebar = split.arrangedSubviews.first,
                  sidebar.frame.width < 260 else { continue }
            split.setPosition(280, ofDividerAt: 0)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Updater.shared.checkIfDue()
        // New songs in the music folder: looked for when the app comes to the front, at most every five minutes.
        // Unchanged files come from the cache, so this is quick.
        Task { @MainActor in await Library.shared.checkNewDay() }
        let watch = UserDefaults.standard.object(forKey: "music.watch") as? Bool ?? true
        if watch, !Debug.active, Date.now.timeIntervalSince(Self.lastScan) > 300 {
            Self.lastScan = .now
            Task { @MainActor in await Library.shared.scanLocal() }
        }
    }
}

/// The Controls menu, with the shortcuts of Spotify on the Mac, so hands that know Spotify feel at home.
struct PlaybackCommands: Commands {
    let model: PlayerModel

    // Fixed titles on purpose: a title that reads the player's state makes SwiftUI rebuild the whole app on every
    // change, which with a long library froze the window.
    var body: some Commands {
        CommandMenu("Controls") {
            Button("Play or Pause") { model.setPlaying(!model.isPlaying) }
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
            Button("Shuffle On or Off") { model.shuffle.toggle() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Repeat On or Off") { model.repeatAll.toggle() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Like or Unlike") { if !model.current.id.isEmpty { model.liked.toggle() } }
                .keyboardShortcut("b", modifiers: [.option, .shift])
            Divider()
            Button("Search") { model.go(.search); model.searchRequest += 1 }
                .keyboardShortcut("l", modifiers: .command)
            Button("Queue") { withAnimation(Motion.panel) { model.showQueue.toggle() } }
                .keyboardShortcut("q", modifiers: [.option, .shift])
            Button("Lyrics") { model.setFullPlayer(!model.fullPlayer) }
                .keyboardShortcut("l", modifiers: [.option, .shift])
        }
        // Back and forward through the pages, with Spotify's shortcuts on the Mac.
        CommandMenu("Go") {
            Button("Back") { model.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { model.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Home") { model.go(.home) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}

/// Whether the player shows in the menu bar. An observable value, not an @AppStorage on the app: the menu bar item writes
/// its binding back whenever it is set up, and a write to @AppStorage, even of the same value, rebuilt the whole app,
/// which set the item up again: a loop that kept the processor busy.
@MainActor @Observable
final class MenuBarSetting {
    static let shared = MenuBarSetting()
    private(set) var show = UserDefaults.standard.object(forKey: "menubar.show") as? Bool ?? true

    func set(_ value: Bool) {
        guard value != show else { return }
        show = value
        UserDefaults.standard.set(value, forKey: "menubar.show")
    }

    var binding: Binding<Bool> {
        Binding(get: { !Debug.active && self.show }, set: { value in
            // Only a real change from the listener counts; the item's own write-back of the same value is ignored.
            guard !Debug.active else { return }
            self.set(value)
        })
    }
}
