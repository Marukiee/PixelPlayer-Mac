import SwiftUI

/// The size of everything in the window, as Spotify's View › Actual Size, Zoom In and Zoom Out (⌘0, ⌘+, ⌘−), with its
/// steps (Chromium's). Like a browser's zoom the page is laid out again at the new size, not just made smaller: at 75% a
/// window shows as much as a window a third wider at 100%. The sizes in the app are Spotify's at 100%.
@MainActor @Observable
final class ZoomLevel {
    static let shared = ZoomLevel()
    static let steps: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25]

    private(set) var value: Double

    private init() {
        let saved = ProcessInfo.processInfo.environment["PP_ZOOM"].flatMap(Double.init)
            ?? (UserDefaults.standard.object(forKey: "view.zoom") as? Double) ?? 1
        value = Self.steps.min { abs($0 - saved) < abs($1 - saved) } ?? 1
    }

    func zoomIn() { set(Self.steps.first { $0 > value + 0.001 } ?? value) }
    func zoomOut() { set(Self.steps.last { $0 < value - 0.001 } ?? value) }
    func actualSize() { set(1) }

    private func set(_ new: Double) {
        guard new != value else { return }
        value = new
        UserDefaults.standard.set(new, forKey: "view.zoom")
    }
}

extension View {
    /// Lays the content out at the window's size divided by the zoom, then scales it to fill the window.
    func zoomed(_ zoom: Double) -> some View {
        GeometryReader { geo in
            self
                .frame(width: geo.size.width / zoom, height: geo.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
        }
        .ignoresSafeArea()
    }
}

/// View › Actual Size, Zoom In and Zoom Out, where Spotify has them. Fixed titles: a title that reads state rebuilds the
/// whole app on every change.
struct ZoomCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("Actual Size") { ZoomLevel.shared.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom In") { ZoomLevel.shared.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { ZoomLevel.shared.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
        }
    }
}
