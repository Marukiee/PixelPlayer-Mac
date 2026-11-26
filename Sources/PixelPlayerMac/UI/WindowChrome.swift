import AppKit
import SwiftUI

/// Spotify's band at the top is 64 px with 8 px around Home and the search field, at 48 pt in a window at 75%. Its
/// traffic lights sit in the middle of that band, level with back and forward, Home and the search field. macOS puts them
/// in a 28 pt title bar, so they are moved down, as Electron's trafficLightPosition does: the title bar's container is made
/// as tall as the band and the three buttons are placed in its middle. AppKit lays the title bar out again on a resize or
/// after full screen, so this is done again each time.
@MainActor
final class TrafficLights: NSObject {
    /// Spotify's band is 64 at 100%; with the zoom it grows and shrinks, the traffic lights stay as they are.
    static var band: CGFloat { TopBar.height * ZoomLevel.shared.value }

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var titleObservation: NSKeyValueObservation?
    private var watching = false
    private var pending = false

    init(window: NSWindow) {
        self.window = window
        super.init()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.place() }
            })
        }
        // A new title (Now Playing) makes AppKit lay the title bar out again, back to 28 pt.
        titleObservation = window.observe(\.title) { [weak self] _, _ in
            DispatchQueue.main.async { self?.schedule() }
        }
        place()
        // The first layout of the title bar can come after the window shows.
        DispatchQueue.main.async { [weak self] in self?.place() }
    }

    /// After AppKit's own layout pass, once, however many changes come in at a time.
    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending = false
            place()
        }
    }

    /// Whatever else lays the title bar out again (a sheet, a new appearance) moves the container or the buttons: follow it.
    private func watch(_ views: [NSView]) {
        guard !watching else { return }
        watching = true
        for view in views {
            view.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
    }

    func place() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview,
              let container = titlebar.superview else { return }
        watch([container, titlebar, close])
        let band = Self.band
        var frame = container.frame
        if frame.height != band || frame.maxY != window.frame.height {
            frame.size.height = band
            frame.origin.y = window.frame.height - band
            container.frame = frame
        }
        if titlebar.frame.height != band {
            titlebar.setFrameSize(NSSize(width: titlebar.frame.width, height: band))
        }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        for button in buttons {
            let y = ((band - button.frame.height) / 2).rounded()
            if button.frame.origin.y != y { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y)) }
        }
    }
}

/// Hands the window a view lives in to `TrafficLights`, once.
struct TrafficLightsPlacer: NSViewRepresentable {
    final class Holder: NSView {
        var lights: TrafficLights?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, lights == nil else { return }
            lights = TrafficLights(window: window)
        }
    }

    func makeNSView(context: Context) -> Holder { Holder() }
    func updateNSView(_ nsView: Holder, context: Context) { nsView.lights?.place() }
}
