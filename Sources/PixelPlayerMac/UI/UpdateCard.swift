import SwiftUI

/// The update card of all of Mark's apps (chosen in November 2026), in the Mac's own controls: a tonal card at the top of the
/// page with the new version and two lines of what is new, Later and Update together across the width. After Update, Later
/// shrinks away and Update grows into a progress bar over the whole card; once downloaded and checked it installs and
/// restarts by itself, without a second click.
struct UpdateCard: View {
    @LocalState private var updater = Updater.shared
    @LocalState private var release: Updater.Release?
    @AppStorage("updateDismissedVersion") private var dismissedVersion = ""

    private enum Phase: Equatable { case available, downloading(Double), installing, failed(String) }

    private var phase: Phase? {
        switch updater.state {
        case .available(let found) where found.version != dismissedVersion: .available
        case .downloading(_, let fraction): .downloading(fraction)
        case .installing: .installing
        case .failed(let message) where updater.installFailed: .failed(message)
        default: nil
        }
    }

    var body: some View {
        Group {
            if let phase, let release = shown {
                card(phase, release)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.panel, value: phase)
        .onChange(of: updater.state, initial: true) {
            if case .available(let found) = updater.state { release = found }
            if case .downloading(let found, _) = updater.state { release = found }
        }
    }

    private var shown: Updater.Release? {
        if case .available(let found) = updater.state { return found }
        if case .downloading(let found, _) = updater.state { return found }
        return release
    }

    private func card(_ phase: Phase, _ release: Updater.Release) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                icon(phase)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New version \(release.version)")
                        .font(.headline)
                    Text(subtitle(phase, release))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .id(subtitleKey(phase))
                        .transition(.push(from: .bottom))
                }
                .clipped()
                Spacer(minLength: 0)
            }
            if phase == .available {
                let lines = Updater.highlights(release.notes)
                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(lines, id: \.self) { Text($0).lineLimit(1) }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if case .failed = phase {
                wideButton("Try again") {
                    Task {
                        // The release is forgotten once it failed, so look again, then install what is there.
                        await updater.check(manual: true)
                        await updater.install()
                    }
                }
            } else {
                buttons(phase)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(PP.window)
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(PP.primaryContainer.opacity(0.6))
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private func subtitle(_ phase: Phase, _ release: Updater.Release) -> String {
        switch phase {
        case .available: "You have \(updater.currentVersion)"
        case .downloading(let fraction):
            release.size > 0 ? "\(Self.megabytes(Double(release.size) * fraction)) of \(Self.megabytes(Double(release.size))) MB" : "Downloading"
        case .installing: "PixelPlayer restarts in a moment"
        case .failed(let message): message
        }
    }

    /// The line only slides when its kind changes, not with every percent.
    private func subtitleKey(_ phase: Phase) -> String {
        switch phase {
        case .available: "available"
        case .downloading: "downloading"
        case .installing: "installing"
        case .failed: "failed"
        }
    }

    private func icon(_ phase: Phase) -> some View {
        ZStack {
            if phase == .installing {
                Circle().fill(Color.green)
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            } else if case .failed = phase {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.orange)
                Image(systemName: "exclamationmark").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(PP.primary)
                Image(systemName: "sparkles").font(.system(size: 20, weight: .semibold)).foregroundStyle(PP.onPrimary)
            }
        }
        .frame(width: 46, height: 46)
        .transition(.scale.combined(with: .opacity))
    }

    /// Later and Update across the width; after Update, Later shrinks to nothing and Update becomes the progress bar.
    private func buttons(_ phase: Phase) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 8
            let laterWidth = phase == .available ? (geo.size.width - gap) / 3 : 0
            HStack(spacing: laterWidth > 0 ? gap : 0) {
                Button { dismissedVersion = shown?.version ?? "" } label: {
                    Text("Later").frame(width: laterWidth, height: 34).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .opacity(laterWidth > 0 ? 1 : 0)
                .frame(width: laterWidth)
                .clipped()
                progressButton(phase)
            }
        }
        .frame(height: 34)
    }

    private func progressButton(_ phase: Phase) -> some View {
        let fraction: Double = switch phase {
        case .available: 1
        case .downloading(let value): value
        default: 1
        }
        return Button { if phase == .available { Task { await updater.install() } } } label: {
            ZStack {
                Capsule().fill(phase == .available ? PP.primary : PP.primary.opacity(0.25))
                GeometryReader { geo in
                    Capsule().fill(PP.primary).frame(width: max(34, geo.size.width * fraction))
                }
                .opacity(phase == .available ? 0 : 1)
                if phase == .installing { Shimmer().clipShape(Capsule()) }
                // The label in the bar's own colour over the empty part and in white over the filled part, so it reads at any point.
                label(phase).foregroundStyle(PP.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
                label(phase).foregroundStyle(PP.onPrimary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in Rectangle().frame(width: geo.size.width * fraction) }
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }

    private func label(_ phase: Phase) -> some View {
        Group {
            switch phase {
            case .available: Text("Update")
            case .downloading(let value): Text("\(Int((value * 100).rounded()))%").monospacedDigit().contentTransition(.numericText())
            default: Text("Installing…")
            }
        }
        .font(.body.weight(.semibold))
    }

    private func wideButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(PP.onPrimary)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(PP.primary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private static func megabytes(_ bytes: Double) -> String {
        String(format: "%.1f", bytes / 1_000_000)
    }
}

/// A soft light that runs over the full bar while it installs.
private struct Shimmer: View {
    @LocalState private var move = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.4)
                .offset(x: move ? geo.size.width : -geo.size.width * 0.4)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { move = true }
        }
        .allowsHitTesting(false)
    }
}
