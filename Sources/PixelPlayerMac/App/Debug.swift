import SwiftUI
import AppKit
import PixelPlayerKit

/// Scripted captures of the prototype, so every direction is shown in the same state. Only active
/// with `PP_DEBUG_DIR` set. Screenshots are made with `screencapture -l` of the app's own windows,
/// never of the screen. A popover is a window of its own: it is captured too and laid over the picture
/// of the main window at its real place.
///
/// - `PP_APPEARANCE=light|dark`, `PP_WINDOW=1180x760`, `PP_SLOW=6`, `PP_FREEZE=1`
/// - `PP_SCRIPT=page:home,wait:1,shot:a-home,devices:1,wait:1.5,shot:a-devices,quit`
///   Steps: page (home, search, songs, liked, playlist:<id>, album:<id>, artist:<id>, shelf:<key>), filter, search:<text>, sort:<order>, queue (1|0), devices (1|0), full (1|0), indiv (1|0), play (1|0),
///   minimize, openapp (as Open PixelPlayer in the menu bar), resume, dump, render:<name>[:sheet] (without the screen),
///   appearance, wait, slow, shot:<name>, settings:<tab>, settingsshot:<name>, closesettings,
///   stage:<name> (menu bar panel), frames:<name>:<seconds>, quit.
@MainActor
enum Debug {
    private static let env = ProcessInfo.processInfo.environment
    static let directory: URL? = env["PP_DEBUG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static var active: Bool { directory != nil }
    nonisolated(unsafe) static var freezeClock = false
    private static var started = false
    private static var stageWindow: NSWindow?

    static func launch() {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = PlayerModel.shared
        if let slow = env["PP_SLOW"].flatMap(Double.init) { Motion.slow = slow }
        freezeClock = env["PP_FREEZE"] != nil
        setAppearance(env["PP_APPEARANCE"])
    }

    static func windowAppeared() {
        guard active, !started else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let size = env["PP_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2, let window = mainWindow() {
                window.setContentSize(NSSize(width: size[0], height: size[1]))
                window.center()
            }
            mainWindow()?.makeKeyAndOrderFront(nil)
            mainWindow()?.makeFirstResponder(nil)
            NSApp.activate()
        }
        if let script = env["PP_SCRIPT"] {
            let steps = script.split(separator: ",").map(String.init)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.0))
                for step in steps { await perform(step) }
            }
        }
    }

    private static func setAppearance(_ name: String?) {
        switch name {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    private static func isPopover(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("Popover")
    }

    static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 !== stageWindow && !isPopover($0) && $0.styleMask.contains(.titled) && $0.frame.width > 800 }
    }

    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 !== stageWindow && !isPopover($0) && $0.styleMask.contains(.titled) && $0.frame.width <= 800 }
    }

    private static func perform(_ step: String) async {
        let model = PlayerModel.shared
        let parts = step.split(separator: ":").map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "page":
            if let route = Route(script: parts.dropFirst().joined(separator: ":")) {
                model.searchText = ""
                if model.fullPlayer { model.fullPlayer = false }
                model.route = route
            }
        case "filter":
            if let f = LibraryFilter(rawValue: value) { model.filter = f }
        case "search":
            model.searchText = value
        case "queue":
            withAnimation(Motion.panel) { model.showQueue = value == "1" }
        case "devices":
            model.showDevices = value == "1"
        case "full":
            model.setFullPlayer(value == "1")
        case "playsong":
            // `playsong:<title>` starts that song with the whole library after it.
            if let song = Library.shared.songs.first(where: { $0.title == value }) { model.play(song, in: Library.shared.songs) }
        case "like", "unlike":
            if let song = Library.shared.songs.first(where: { $0.title == value }) { model.setLiked(song, parts[0] == "like") }
        case "seek":
            model.seek(to: Double(value) ?? 0)
        case "phone":
            // `phone:<name>` plays on that phone (PP_REMOTE_TCP lists them), `phone:off` comes back to the Mac.
            let remote = RemoteController.shared
            remote.refreshPhones()
            if value == "off" { remote.disconnect() } else if let phone = remote.phones.first(where: { $0.name == value }) { remote.connect(phone) }
        case "next":
            Playback.shared.next()
        case "prev":
            Playback.shared.previous()
        case "pause", "resume":
            model.setPlaying(parts[0] == "resume")
        case "volume":
            model.volume = Double(value) ?? 50
        case "repeat":
            model.repeatAll = value == "1"
        case "addqueue", "playnext":
            if let song = Library.shared.songs.first(where: { $0.title == value }) {
                if parts[0] == "playnext" { model.userQueue.insert(song, at: 0) } else { model.userQueue.append(song) }
            }
        case "sonos", "sonosoff":
            // `sonos:<room>` adds a room (PP_SONOS_HOSTS lists the speakers), `sonosoff:<room>` takes it out.
            let sonos = SonosOutput.shared
            sonos.connectShown(true)
            for _ in 0..<40 where !sonos.rooms.contains(where: { $0.name == value }) { try? await Task.sleep(for: .milliseconds(250)) }
            if let room = sonos.rooms.first(where: { $0.name == value }) { sonos.setRoom(room, on: parts[0] == "sonos") }
        case "sonosmac":
            SonosOutput.shared.backToMac()
        case "groupvolume":
            model.groupVolume = Double(value) ?? 30
        case "sonosstate":
            let sonos = SonosOutput.shared
            let rooms = sonos.session?.group.members.map(\.name).joined(separator: "+") ?? "-"
            let line = "\(value)\tcurrent=\(model.current.title)\tpos=\(Int(model.position))\tplaying=\(model.isPlaying)\trooms=\(rooms)"
                + "\tvolume=\(sonos.session?.groupVolume.map(String.init) ?? "-")\tspeakerPlaying=\(sonos.session?.isPlaying ?? false)"
                + "\tqueue=\(model.userQueue.count)+\(model.upNext.count)\tnote=\(sonos.note ?? "-")\n"
            let url = file("sonos.txt")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        case "testupdate":
            // The whole update path against the real latest release: check, download, the checks, and the swap.
            // Run a release build with PP_UPDATE_TEST_FROM set; the new app is put in place but not opened.
            await Updater.shared.runTestUpdate()
        case "update":
            // `update:available|downloading|installing|failed` shows the update card with a made-up release.
            let release = Updater.Release(version: "0.2.0", notes: "Faster start\n\nNew\n\n\u{2022} Lyrics follow the song on Sonos\n\u{2022} Add songs to a playlist from the right-click menu",
                                          zipURL: URL(string: "https://example.invalid/PixelPlayer-macOS.zip")!, shaURL: nil, sigURL: nil,
                                          size: 18_400_000, page: URL(string: "https://example.invalid")!)
            switch value {
            case "available": Updater.shared.state = .available(release)
            case "downloading": Updater.shared.state = .available(release); try? await Task.sleep(for: .milliseconds(50)); Updater.shared.state = .downloading(release, Double(parts.count > 2 ? parts[2] : "0.42") ?? 0.42)
            case "installing": Updater.shared.state = .downloading(release, 1); try? await Task.sleep(for: .milliseconds(50)); Updater.shared.state = .installing
            default: Updater.shared.state = .idle
            }
        case "remotestate":
            // What the Mac shows while a phone plays, for the remote checks.
            let remote = RemoteController.shared
            let line = "\(parts.count > 1 ? value : "state")\tcurrent=\(model.current.title)\tid=\(model.current.id)\tpos=\(Int(model.position))"
                + "\tplaying=\(model.isPlaying)\tvolume=\(Int(model.volume))\tqueue=\(model.userQueue.count)+\(model.upNext.count)"
                + "\tactive=\(remote.active?.name ?? "-")\tnote=\(remote.active.flatMap(remote.note(for:)) ?? remote.phones.first.flatMap(remote.note(for:)) ?? "-")\n"
            let url = file("remote.txt")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        case "dump":
            // What the merged library looks like, for checks of the local-first rules.
            let lines = Library.shared.songs.map { "\($0.id)\t\($0.title)\t\($0.artist)\tlocal=\($0.isLocal)\tserver=\($0.source.serverID ?? "-")\tliked=\(Library.shared.likedIDs.contains($0.id))" }
            try? lines.joined(separator: "\n").write(to: file("library.txt"), atomically: true, encoding: .utf8)
        case "sort":
            // `sort:title|artist|album|added|custom` orders the list on the page, as the sort menu does.
            if let order = TrackOrder(rawValue: value) { model.trackOrders[model.route] = order }
        case "minimize":
            mainWindow()?.miniaturize(nil)
        case "openapp":
            // What Open PixelPlayer in the menu bar panel does.
            MainWindow.show(open: nil)
        case "fullscreen":
            model.setFullScreen(value == "1")
        case "info":
            model.infoSong = value == "1" ? model.current : nil
        case "indiv":
            withAnimation(Motion.panel) { model.individualVolume = value == "1" }
        case "play":
            withAnimation(Motion.bouncy) { model.isPlaying = value == "1" }
        case "appearance":
            setAppearance(value)
        case "slow":
            Motion.slow = Double(value) ?? 1
        case "wait":
            try? await Task.sleep(for: .seconds(Double(value) ?? 1))
        case "shot":
            await shot(value) { mainWindow() }
        case "render":
            // `render:<name>[:sheet]` draws the window (or its sheet) into a picture without the screen, so it also works
            // while the screen is locked. Glass and materials come out flat; for checking content, not looks.
            let window = parts.count > 2 && parts[2] == "sheet" ? mainWindow()?.attachedSheet : mainWindow()
            if let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: file("\(value).png"))
            }
        case "focusshot":
            // Moves keyboard focus a few steps, as Tab does, and captures without clearing it: for checking focus rings.
            if let window = mainWindow() {
                for _ in 0..<(Int(parts.count > 2 ? parts[2] : "3") ?? 3) { window.selectNextKeyView(nil) }
                try? await Task.sleep(for: .seconds(0.5))
                await capture(window.windowNumber, to: file("\(value).png"))
            }
        case "settings":
            if let tab = SettingsTab(rawValue: value) { model.settingsTab = tab }
            if settingsWindow() == nil { model.settingsRequest += 1 }
            try? await Task.sleep(for: .seconds(1.2))
        case "settingsshot":
            await shot(value) { settingsWindow() }
        case "closesettings":
            settingsWindow()?.close()
            mainWindow()?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.6))
        case "stage":
            showStage()
            try? await Task.sleep(for: .seconds(1.5))
            if let stageWindow { await capture(stageWindow.windowNumber, to: file("\(value).png")) }
            stageWindow?.orderOut(nil)
            mainWindow()?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            try? await Task.sleep(for: .seconds(0.6))
        case "frames":
            if let window = mainWindow() { startFrames(window.windowNumber, name: value, seconds: Double(parts.count > 2 ? parts[2] : "4") ?? 4) }
        case "windows":
            let lines = NSApp.windows.map { "\(String(describing: type(of: $0))) visible=\($0.isVisible) id=\($0.windowNumber) frame=\($0.frame) level=\($0.level.rawValue) identifier=\($0.identifier?.rawValue ?? "-") minimized=\($0.isMiniaturized)" }
            try? lines.joined(separator: "\n").write(to: file("windows.txt"), atomically: true, encoding: .utf8)
        case "quit":
            try? await Task.sleep(for: .seconds(0.5))
            NSApp.terminate(nil)
        default:
            break
        }
    }

    /// One picture of a window, retried until its traffic lights are in colour (a window in the background
    /// draws its glass dimmed), with any open popover laid over it.
    private static func shot(_ name: String, window pick: () -> NSWindow?) async {
        let url = file("\(name).png")
        for attempt in 0..<4 {
            guard let window = pick() else { return }
            if attempt > 0 || !(NSApp.isActive && window.isKeyWindow) {
                bringToFront()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .seconds(0.8))
            }
            // No keyboard focus ring in the pictures.
            window.makeFirstResponder(nil)
            for popover in NSApp.windows where popover.isVisible && isPopover(popover) { popover.makeFirstResponder(nil) }
            try? await Task.sleep(for: .seconds(0.2))
            await capture(window.windowNumber, to: url)
            if looksActive(url) { break }
        }
        // An open popover is a child window of this one: screencapture -l takes it along, glass and all,
        // also where it reaches past the window's edge.
    }

    private static func bringToFront() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [Bundle.main.bundlePath]
        try? open.run()
    }

    /// True when a red traffic light shows in the top left corner.
    private static func looksActive(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let image = NSBitmapImageRep(data: data) else { return true }
        for y in stride(from: 10, to: min(160, image.pixelsHigh), by: 3) {
            for x in stride(from: 10, to: min(260, image.pixelsWide), by: 3) {
                if let c = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   c.redComponent > 0.85, c.greenComponent < 0.5, c.blueComponent < 0.5 { return true }
            }
        }
        return false
    }

    private static func file(_ name: String) -> URL { directory!.appendingPathComponent(name) }

    nonisolated private static func screencapture(_ id: Int, _ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(id)", path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func capture(_ id: Int, to url: URL) async {
        let path = url.path
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                screencapture(id, path)
                done.resume()
            }
        }
    }

    /// Frames of the window, as fast as screencapture allows, each with its moment, so a clip can be
    /// put together at the real speed afterwards.
    private static func startFrames(_ id: Int, name: String, seconds: Double) {
        let folder = file("frames-\(name)")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slow = Motion.slow
        Thread.detachNewThread {
            let start = Date()
            var index = 0
            var log = "slow \(slow)\n"
            while Date().timeIntervalSince(start) < seconds {
                let t = Date().timeIntervalSince(start)
                screencapture(id, folder.appendingPathComponent(String(format: "%05d.png", index)).path)
                log += String(format: "%05d %.4f\n", index, t)
                index += 1
            }
            try? log.write(to: folder.appendingPathComponent("times.txt"), atomically: true, encoding: .utf8)
        }
    }

    private static func showStage() {
        let host = NSHostingView(rootView: MenuBarStage().environment(PlayerModel.shared).tint(PP.primary))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        stageWindow = window
    }
}
