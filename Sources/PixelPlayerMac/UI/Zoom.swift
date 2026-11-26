import SwiftUI

/// The size of everything in the window, as Spotify's View › Actual Size, Zoom In and Zoom Out (⌘0, ⌘+, ⌘−). Like a
/// browser's zoom the page is laid out again at the new size, not just made smaller. The sizes in the app are Spotify's
/// at 100%. Spotify's steps are whole zoom levels, each 1.2 times the last: its prefs keep `app.browser.zoom-level` in
/// hundredths of a level, and Mark's -100 is 83.3% (his screenshot of Spotify's menu agrees: rows 32 × 0.833 apart).
@MainActor @Observable
final class ZoomLevel {
    static let shared = ZoomLevel()
    static let steps: [Double] = (-3...3).map { pow(1.2, Double($0)) }
    /// Without a choice of its own the app opens one step smaller than 100%, as Mark has Spotify (2026-11-26: "net te
    /// groot", Spotify's size is perfect).
    static let standard = 1 / 1.2

    private(set) var value: Double

    private init() {
        let saved = ProcessInfo.processInfo.environment["PP_ZOOM"].flatMap(Double.init)
            ?? (UserDefaults.standard.object(forKey: "view.zoom") as? Double) ?? Self.standard
        value = Self.steps.min { abs($0 - saved) < abs($1 - saved) } ?? Self.standard
    }

    func zoomIn() { set(Self.steps.first { $0 > value + 0.001 } ?? value) }
    func zoomOut() { set(Self.steps.last { $0 < value - 0.001 } ?? value) }
    func actualSize() { set(1) }

    private func set(_ new: Double) {
        guard abs(new - value) > 0.001 else { return }
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
                // The menus place themselves in this, which the pointer shares (window from its top left, over the zoom).
                .coordinateSpace(.named(MenuPresenter.space))
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
