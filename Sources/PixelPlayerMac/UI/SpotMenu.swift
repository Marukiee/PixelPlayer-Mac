import AppKit
import SwiftUI

// Menus as Spotify draws them on the Mac, instead of the system's (Mark, 2026-11-26): a dark panel at the pointer, rows
// 32 high with an icon, the title and Spotify's letter on the right, a submenu beside its row. Measured on Spotify's
// song menu: panel #1F1F1F with 8 round and 8 inside, rows 8/12 inside with 12 between icon and title, title 14, icons
// 16 in #B3B3B3, letter 12 in #B3B3B3, under the pointer #2A2A2A with 6 round, lines 1 thick in white at 10% with 8
// around them, shadow 0 4 6 black at 30%. Unlike Spotify every row has an icon (Mark: rows without one look untidy),
// the same icons as SpotCopy on Android.

/// One line of a menu.
struct MenuEntry: Identifiable {
    enum Icon {
        /// SpotCopy's traced icon (Resources/Icons/sp_<name>.svg).
        case svg(String)
        /// The Liked Songs cover in colour, as Spotify's Add to and Remove from Liked Songs.
        case likedCover
        /// A drawn icon (the list and compact views).
        case custom(AnyView)
    }

    enum Kind {
        case action(() -> Void)
        case submenu(() -> [MenuEntry])
        case divider
        case header
    }

    let id = UUID()
    var title = ""
    var icon: Icon? = nil
    /// The icon in green, as Spotify's pin on something pinned.
    var green = false
    /// Spotify's letter on the right; it works while the menu is open ("⌥A" with Option).
    var shortcut: String? = nil
    var disabled = false
    /// The chosen one of a few (a sort order, a view): green with a check, as in Spotify.
    var checked = false
    var help: String? = nil
    var kind: Kind

    static func item(_ title: String, icon: Icon? = nil, green: Bool = false, shortcut: String? = nil, disabled: Bool = false,
                     checked: Bool = false, help: String? = nil, action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, icon: icon, green: green, shortcut: shortcut, disabled: disabled, checked: checked, help: help, kind: .action(action))
    }

    static func submenu(_ title: String, icon: Icon? = nil, shortcut: String? = nil, disabled: Bool = false, help: String? = nil,
                        _ entries: @escaping () -> [MenuEntry]) -> MenuEntry {
        MenuEntry(title: title, icon: icon, shortcut: shortcut, disabled: disabled, help: help, kind: .submenu(entries))
    }

    static var divider: MenuEntry { MenuEntry(kind: .divider) }
    static func header(_ title: String) -> MenuEntry { MenuEntry(title: title, kind: .header) }

    var selectable: Bool {
        switch kind {
        case .action, .submenu: !disabled
        case .divider, .header: false
        }
    }

    var opensSubmenu: Bool { if case .submenu = kind { true } else { false } }

    /// Whether a key press is this row's letter.
    func matches(_ event: NSEvent) -> Bool {
        guard var letter = shortcut?.lowercased() else { return false }
        let option = letter.hasPrefix("⌥")
        if option { letter.removeFirst() }
        return option == event.modifierFlags.contains(.option) && event.charactersIgnoringModifiers?.lowercased() == letter
    }
}

// MARK: Showing

/// The open menu: one at a time, with at most one submenu, drawn over the whole window by `MenuLayer`.
@MainActor @Observable
final class MenuPresenter {
    static let shared = MenuPresenter()
    /// The window's own coordinates before the zoom, which the menu layer and the pointer share.
    nonisolated static let space = "menu.window"

    struct Level {
        var entries: [MenuEntry]
        var highlighted: Int? = nil
    }

    private(set) var main: Level?
    private(set) var sub: Level?
    /// Where the menu opened, in `space`: the pointer, or the button it hangs under.
    private(set) var point: CGPoint = .zero
    private(set) var anchor: CGRect?
    /// The row of the main menu the submenu hangs beside, in `space`.
    private(set) var subRow: CGRect = .zero
    private(set) var subParent: Int?
    /// What the open menu belongs to: its row keeps its highlight while the menu is open, as in Spotify.
    private(set) var owner: String?
    /// The keys work in the submenu.
    private(set) var inSub = false

    /// The menus' frames and the main menu's rows, in `space`, as last laid out.
    @ObservationIgnored var frames: [Int: CGRect] = [:]
    @ObservationIgnored var rowFrames: [Int: CGRect] = [:]
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var isOpen: Bool { main != nil }

    /// Opens the menu at the pointer (or `point`, in `space`), or under the button `anchor` (in `space`).
    func show(_ entries: [MenuEntry], owner: String? = nil, at point: CGPoint? = nil, under anchor: CGRect? = nil, in window: NSWindow? = nil) {
        close()
        guard !entries.isEmpty, let point = point ?? anchor.map({ CGPoint(x: $0.minX, y: $0.maxY) }) ?? Self.pointer(in: window) else { return }
        self.point = point
        self.anchor = anchor
        self.owner = owner
        main = Level(entries: entries)
        install()
    }

    func close() {
        guard main != nil || !monitors.isEmpty else { return }
        main = nil
        sub = nil
        subParent = nil
        anchor = nil
        owner = nil
        inSub = false
        frames = [:]
        rowFrames = [:]
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Where an event happened, in `space`.
    static func point(of event: NSEvent) -> CGPoint? {
        guard let content = event.window?.contentView else { return nil }
        let zoom = ZoomLevel.shared.value
        return CGPoint(x: event.locationInWindow.x / zoom, y: (content.bounds.height - event.locationInWindow.y) / zoom)
    }

    /// The pointer in `space`: the window's content from its top left, divided by the zoom.
    static func pointer(in window: NSWindow? = nil) -> CGPoint? {
        guard let window = window ?? NSApp.currentEvent?.window ?? NSApp.keyWindow ?? Debug.mainWindow(), let content = window.contentView else { return nil }
        let location = window.mouseLocationOutsideOfEventStream
        let zoom = ZoomLevel.shared.value
        return CGPoint(x: location.x / zoom, y: (content.bounds.height - location.y) / zoom)
    }

    // MARK: Pointer and keys

    /// The pointer on a row (or off the menu, `index` nil).
    func hover(level: Int, index: Int?) {
        if level == 0 {
            guard let main else { return }
            guard let index else {
                // Off the menu: the row that opened the submenu stays lit.
                self.main?.highlighted = subParent
                return
            }
            self.main?.highlighted = index
            inSub = false
            let entry = main.entries[index]
            if entry.opensSubmenu && !entry.disabled {
                if subParent != index { openSub(index) }
            } else {
                closeSub()
            }
        } else {
            sub?.highlighted = index
            if index != nil { inSub = true; main?.highlighted = subParent }
        }
    }

    func activate(level: Int, index: Int) {
        guard let entry = (level == 0 ? main : sub)?.entries[safe: index], entry.selectable else { return }
        switch entry.kind {
        case .action(let run):
            close()
            // After the menu is gone, so what it opens (the share menu, a prompt) comes at the pointer on a quiet window.
            DispatchQueue.main.async { run() }
        case .submenu:
            guard level == 0 else { return }
            if subParent != index { openSub(index) }
            inSub = true
            sub?.highlighted = sub?.entries.firstIndex(where: \.selectable)
        case .divider, .header:
            break
        }
    }

    private func openSub(_ index: Int) {
        guard case .submenu(let make)? = main?.entries[safe: index]?.kind else { return }
        let entries = make()
        guard !entries.isEmpty else { closeSub(); return }
        subParent = index
        subRow = rowFrames[index] ?? CGRect(origin: point, size: CGSize(width: 200, height: 32))
        sub = Level(entries: entries)
        frames[1] = nil
    }

    private func closeSub() {
        sub = nil
        subParent = nil
        inSub = false
        frames[1] = nil
    }

    private func move(_ step: Int) {
        let level = inSub ? sub : main
        guard let entries = level?.entries else { return }
        let rows = entries.indices.filter { entries[$0].selectable }
        guard !rows.isEmpty else { return }
        let current = level?.highlighted.flatMap { rows.firstIndex(of: $0) }
        let next = current.map { (($0 + step) % rows.count + rows.count) % rows.count } ?? (step > 0 ? 0 : rows.count - 1)
        if inSub { sub?.highlighted = rows[next] } else { main?.highlighted = rows[next]; closeSub() }
    }

    /// Handles a key while the menu is open; true lets it through.
    private func key(_ event: NSEvent) -> Bool {
        guard main != nil else { return true }
        if event.modifierFlags.contains(.command) { close(); return true }
        let level = inSub ? 1 : 0
        let highlighted = (inSub ? sub : main)?.highlighted
        switch event.keyCode {
        case 53: // Esc: the submenu first, as in Spotify.
            if sub != nil { closeSub() } else { close() }
        case 125: move(1)
        case 126: move(-1)
        case 124: // Right opens the submenu.
            if !inSub, let highlighted, main?.entries[highlighted].opensSubmenu == true { activate(level: 0, index: highlighted) }
        case 123: // Left goes back.
            if inSub { closeSub() }
        case 36, 76, 49:
            if let highlighted { activate(level: level, index: highlighted) }
        default:
            let entries = (inSub ? sub : main)?.entries ?? []
            if let index = entries.firstIndex(where: { $0.selectable && $0.matches(event) }) { activate(level: level, index: index) }
        }
        return false
    }

    /// Handles a click while the menu is open; true lets it through.
    private func mouseDown(_ event: NSEvent) -> Bool {
        guard main != nil else { return true }
        guard let window = event.window, window === Debug.mainWindow() || window === NSApp.mainWindow else {
            close()
            return true
        }
        if isOnMenu(event) { return true }
        close()
        // A click outside only closes the menu, as a menu does; a right click opens the next one where it lands.
        return event.type == .rightMouseDown || event.modifierFlags.contains(.control)
    }

    private func isOnMenu(_ event: NSEvent) -> Bool {
        guard let point = Self.point(of: event) else { return false }
        return frames.values.contains { $0.contains(point) }
    }

    private func install() {
        let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDown(event) ?? true } ? event : nil
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.key(event) ?? true } ? event : nil
        }
        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Scrolling the list closes the menu; scrolling in a long submenu scrolls it.
            MainActor.assumeIsolated { if let self, !self.isOnMenu(event) { self.close() } }
            return event
        }
        monitors = [clicks, keys, scroll].compactMap { $0 }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResizeNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: Drawing

/// The open menu over everything in the window. Empty and let through while no menu is open.
struct MenuLayer: View {
    var body: some View {
        let menus = MenuPresenter.shared
        GeometryReader { geo in
            let origin = geo.frame(in: .named(MenuPresenter.space)).origin
            if let main = menus.main {
                ZStack(alignment: .topLeading) {
                    MenuPlacement(point: CGPoint(x: menus.point.x - origin.x, y: menus.point.y - origin.y),
                                  under: menus.anchor?.offsetBy(dx: -origin.x, dy: -origin.y)) {
                        MenuPanel(depth: 0, menu: main)
                    }
                    if let sub = menus.sub {
                        MenuPlacement(beside: menus.subRow.offsetBy(dx: -origin.x, dy: -origin.y)) {
                            MenuPanel(depth: 1, menu: sub)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(menus.isOpen)
    }
}

/// Puts a menu at the pointer, to its left or above it where there is no room, as Spotify; a submenu beside its row, on
/// the right or else the left. Never past the window's edge.
struct MenuPlacement: Layout {
    var point: CGPoint = .zero
    /// A button's menu hangs under it, from its left edge (its right where there is no room), else above it.
    var under: CGRect? = nil
    var beside: CGRect? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let menu = subviews.first else { return }
        let margin: CGFloat = 8
        let ideal = menu.sizeThatFits(.unspecified)
        let size = CGSize(width: min(ideal.width, bounds.width - 2 * margin), height: min(ideal.height, bounds.height - 2 * margin))
        var x: CGFloat, y: CGFloat
        if let row = beside {
            // The submenu's edge against the menu's (the row has the menu's 8 around it), its first row level with the row.
            x = row.maxX + 8
            if x + size.width > bounds.width - margin { x = row.minX - 8 - size.width }
            y = row.minY - 8
        } else if let button = under {
            x = button.minX
            if x + size.width > bounds.width - margin { x = button.maxX - size.width }
            y = button.maxY + 4
            if y + size.height > bounds.height - margin { y = button.minY - 4 - size.height }
        } else {
            x = point.x
            y = point.y
            if x + size.width > bounds.width - margin { x = point.x - size.width }
            if y + size.height > bounds.height - margin { y = point.y - size.height }
        }
        x = min(max(x, margin), bounds.width - margin - size.width)
        y = min(max(y, margin), bounds.height - margin - size.height)
        menu.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

/// One menu: the dark panel with its rows.
struct MenuPanel: View {
    let level: Int
    let entries: [MenuEntry]
    let highlighted: Int?

    init(depth: Int, menu: MenuPresenter.Level) {
        level = depth
        entries = menu.entries
        highlighted = menu.highlighted
    }

    var body: some View {
        let menus = MenuPresenter.shared
        // Room for icons in front of every title where most rows have one; otherwise only the rows with one show it
        // (Spotify's list of playlists under New playlist).
        let selectable = entries.filter { $0.selectable || $0.disabled }
        let roomForIcons = selectable.filter { $0.icon != nil }.count * 2 > selectable.count
        let height = entries.reduce(CGFloat(16)) { total, entry in
            switch entry.kind {
            case .divider: total + 17
            case .header: total + 32.5
            default: total + 32
            }
        }
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                switch entry.kind {
                case .divider:
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(8)
                case .header:
                    Text(entry.title).font(.mix(12, .bold)).foregroundStyle(PP.subdued)
                        .frame(maxWidth: .infinity, minHeight: 32.5, alignment: .leading)
                        .padding(.horizontal, 8)
                default:
                    MenuRow(level: level, index: index, entry: entry, roomForIcon: roomForIcons, lit: highlighted == index)
                }
            }
        }
        .padding(8)
        Group {
            if entries.count > 14 {
                ScrollView { rows }
                    .scrollIndicators(.automatic)
                    .frame(minHeight: 0, idealHeight: height, maxHeight: height)
            } else {
                rows
            }
        }
        .frame(minWidth: 160, maxWidth: 350, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PP.menu))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 4)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MenuPresenter.space)) } action: { menus.frames[level] = $0 }
        .onHover { inside in if !inside { menus.hover(level: level, index: nil) } }
        .environment(\.font, .mix(14))
    }
}

/// A row of a menu.
struct MenuRow: View {
    let level: Int
    let index: Int
    let entry: MenuEntry
    let roomForIcon: Bool
    let lit: Bool

    var body: some View {
        let menus = MenuPresenter.shared
        HStack(spacing: 12) {
            if entry.icon != nil || roomForIcon {
                // The chosen one's icon goes green with its title, as in Spotify.
                MenuIcon(icon: entry.icon, green: entry.green || entry.checked).frame(width: 16, height: 16)
            }
            Text(entry.title).font(.mix(14)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(entry.checked ? AnyShapeStyle(PP.primary) : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
            if entry.shortcut != nil || entry.opensSubmenu || entry.checked {
                HStack(spacing: 8) {
                    if let shortcut = entry.shortcut {
                        Text(shortcut).font(.mix(12)).foregroundStyle(PP.subdued).frame(minWidth: 16)
                    }
                    if entry.opensSubmenu {
                        SubmenuTriangle().fill(PP.subdued).frame(width: 6, height: 12).frame(width: 16, height: 16)
                    }
                    if entry.checked {
                        SpotCheck().stroke(PP.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .miter)).frame(width: 16, height: 16)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(lit && !entry.disabled ? PP.menuHover : Color.clear))
        .opacity(entry.disabled ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { inside in if inside { menus.hover(level: level, index: index) } }
        .onTapGesture { menus.activate(level: level, index: index) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MenuPresenter.space)) } action: { frame in
            if level == 0 { menus.rowFrames[index] = frame }
        }
        .help(entry.help ?? "")
    }
}

/// A row's icon: grey as Spotify's, green where it says something is on.
struct MenuIcon: View {
    let icon: MenuEntry.Icon?
    var green = false

    var body: some View {
        switch icon {
        case .svg(let name):
            // The play triangle is solid, so a little smaller to weigh the same as the outlines.
            SpotifyIcon(name: name).fill(green ? PP.primary : PP.subdued, style: FillStyle(eoFill: true)).padding(name == "play" ? 2.5 : 0.5)
        case .likedCover:
            ArtworkView(art: .liked, radius: 2)
        case .custom(let view):
            view.foregroundStyle(green ? PP.primary : PP.subdued)
        case nil:
            Color.clear
        }
    }
}

/// Spotify's check in a menu, measured on its icon (16 box): a line 1.5 thick from (1, 9.19) through (4.91, 13.09) to
/// (15, 3), round at the ends and sharp in the corner. Drawn here, not copied.
struct SpotCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 16
        let origin = CGPoint(x: rect.midX - 8 * unit, y: rect.midY - 8 * unit)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }
        var path = Path()
        path.move(to: p(1, 9.186))
        path.addLine(to: p(4.907, 13.093))
        path.addLine(to: p(15, 3))
        return path
    }
}

/// Spotify's small solid triangle that marks a submenu.
struct SubmenuTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Opening

/// Catches a right click (or a Control-click) on what it lies over and lets every other click, scroll and hover through.
struct RightClickArea: NSViewRepresentable {
    let action: @MainActor (NSEvent) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: (@MainActor (NSEvent) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let right = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action?(event) }
        override func mouseDown(with event: NSEvent) { if event.modifierFlags.contains(.control) { action?(event) } }
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}

extension View {
    /// Spotify's menu on a right click. `owner` names the row, which stays lit while its menu is open.
    func spotContextMenu(owner: String? = nil, _ entries: @escaping () -> [MenuEntry]) -> some View {
        // Left out in a picture drawn off screen, which cannot draw the AppKit view that catches the right click.
        overlay(Debug.offscreen ? nil : RightClickArea { event in MenuPresenter.shared.show(entries(), owner: owner, at: MenuPresenter.point(of: event), in: event.window) })
    }
}

/// A button that opens Spotify's menu under it: the three dots and the other small menus.
struct MenuButton<Label: View>: View {
    var owner: String? = nil
    let entries: () -> [MenuEntry]
    @ViewBuilder var label: Label
    @State private var frame: CGRect = .zero

    var body: some View {
        Button { MenuPresenter.shared.show(entries(), owner: owner, under: frame) } label: { label }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MenuPresenter.space)) } action: { frame = $0 }
    }
}
