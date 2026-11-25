import AppKit

/// The folder with music on this Mac. Songs found here win over the same songs on the server.
enum MusicFolder {
    static var path: String? {
        if let saved = UserDefaults.standard.string(forKey: "music.folder") { return saved }
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].path
        return FileManager.default.fileExists(atPath: music) ? music : nil
    }

    @MainActor
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder with your music"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: "music.folder")
        return url.path
    }
}
