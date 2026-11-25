import SwiftUI
import AppKit

/// The system's share menu, for a song, an album or a playlist as one line of text.
@MainActor
enum Share {
    static func text(for song: Song) -> String { "\(song.title) by \(song.artist)" }

    /// Opens the share menu at the pointer, once the menu that asked for it has closed.
    static func text(_ text: String) {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? Debug.mainWindow(), let view = window.contentView else { return }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            NSSharingServicePicker(items: [text]).show(relativeTo: NSRect(x: point.x, y: point.y, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
    }
}

/// The library window, from the menu bar.
@MainActor
enum MainWindow {
    /// Brings PixelPlayer forward with its window: back from the Dock when it was minimised, a new one only when it was closed.
    static func show(open: OpenWindowAction?) {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && ($0.isVisible || $0.isMiniaturized) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            open?(id: "main")
        }
    }
}
