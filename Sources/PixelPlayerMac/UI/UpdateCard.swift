import SwiftUI

/// A new version, as a small glass popup at the top right of the page, over it rather than pushing it down. One line says
/// which version, What's new opens the changes, and Update turns into a small progress bar in place; once downloaded and
/// checked it installs and restarts by itself, without a second click.
struct UpdateCard: View {
    @LocalState private var updater = Updater.shared
    @LocalState private var release: Updater.Release?
    @LocalState private var showNotes = false
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
                popup(phase, release)
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

    private func popup(_ phase: Phase, _ release: Updater.Release) -> some View {
        HStack(spacing: 12) {
            icon(phase)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(phase, release)).font(.mix(14, .bold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle(phase, release))
                        .monospacedDigit()
                        .lineLimit(1)
                        .id(subtitleKey(phase))
                        .transition(.push(from: .bottom))
                    if phase == .available, !Updater.highlights(release.notes).isEmpty {
                        ShowAllButton(title: "What's new") { showNotes.toggle() }
                            .popover(isPresented: $showNotes, arrowEdge: .bottom) { notes(release) }
                    }
                }
                .font(.mix(12))
                .foregroundStyle(PP.subdued)
                .clipped()
            }
            Spacer(minLength: 8)
            actions(phase)
        }
        .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 10)
        .frame(width: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // As far from the top of the window as from its right side.
        .padding(.top, 20)
        .padding(.trailing, 20)
    }

    private func title(_ phase: Phase, _ release: Updater.Release) -> String {
        if case .failed = phase { return "The update did not work" }
        return "PixelPlayer \(release.version)"
    }

    private func subtitle(_ phase: Phase, _ release: Updater.Release) -> String {
        switch phase {
        case .available: "You have \(updater.currentVersion)"
        case .downloading(let fraction):
            release.size > 0 ? "\(Self.megabytes(Double(release.size) * fraction)) of \(Self.megabytes(Double(release.size))) MB" : "Downloading"
        case .installing: "Restarts in a moment"
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
            switch phase {
            case .installing:
                Circle().fill(Color.green)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            case .failed:
                Circle().fill(Color.orange)
                Image(systemName: "exclamationmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            default:
                Circle().fill(PP.primary)
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .bold)).foregroundStyle(PP.onPrimary)
            }
        }
        .frame(width: 32, height: 32)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder private func actions(_ phase: Phase) -> some View {
        switch phase {
        case .available:
            HStack(spacing: 6) {
                Button("Later") { dismissedVersion = shown?.version ?? "" }
                    .buttonStyle(.plain)
                    .foregroundStyle(PP.subdued)
                    .padding(.horizontal, 8)
                Button { Task { await updater.install() } } label: { pill(Text("Update")) }
                    .buttonStyle(PressStyle())
                    .help("Download, install and restart")
            }
        case .downloading(let fraction):
            progress(fraction, Text("\(Int((fraction * 100).rounded()))%").monospacedDigit())
        case .installing:
            progress(1, Text("Installing")).overlay { Shimmer().clipShape(Capsule()) }
        case .failed:
            Button {
                Task {
                    // The release is forgotten once it failed, so look again, then install what is there.
                    await updater.check(manual: true)
                    await updater.install()
                }
            } label: { pill(Text("Try again")) }
            .buttonStyle(PressStyle())
        }
    }

    /// The accent capsule; Update and the progress bar have one size, so the one turns into the other in place.
    private func pill(_ label: Text) -> some View {
        label
            .font(.mix(12, .bold))
            .foregroundStyle(PP.onPrimary)
            .frame(width: 96, height: 30)
            .background(PP.primary, in: Capsule())
            .contentShape(Capsule())
    }

    private func progress(_ fraction: Double, _ label: Text) -> some View {
        ZStack {
            Capsule().fill(PP.primary.opacity(0.25))
            Capsule().fill(PP.primary)
                .frame(width: max(30, 96 * fraction))
                .frame(maxWidth: .infinity, alignment: .leading)
            label.font(.mix(12, .bold)).foregroundStyle(PP.onPrimary)
        }
        .frame(width: 96, height: 30)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }

    private func notes(_ release: Updater.Release) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's new in \(release.version)").font(.mix(14, .bold))
            ForEach(release.notes.components(separatedBy: .newlines).filter { $0.hasPrefix("\u{2022} ") }, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.tint)
                    Text(String(line.dropFirst(2))).font(.mix(13)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
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
