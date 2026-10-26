import SwiftUI
import LedgeDomain

public struct ShelfRootView: View {
    public let route: ShelfRoute
    public let dismiss: () -> Void
    public let expand: () -> Void
    public let actions: ActionResolution?
    public let performAction: ((ActionCandidate) -> Void)?

    public init(route: ShelfRoute, dismiss: @escaping () -> Void, expand: @escaping () -> Void) {
        self.init(route: route, actions: nil, dismiss: dismiss, expand: expand, performAction: nil)
    }

    public init(
        route: ShelfRoute,
        actions: ActionResolution,
        dismiss: @escaping () -> Void,
        expand: @escaping () -> Void,
        performAction: ((ActionCandidate) -> Void)? = nil
    ) {
        self.init(route: route, actions: Optional(actions), dismiss: dismiss, expand: expand, performAction: performAction)
    }

    private init(
        route: ShelfRoute,
        actions: ActionResolution?,
        dismiss: @escaping () -> Void,
        expand: @escaping () -> Void,
        performAction: ((ActionCandidate) -> Void)?
    ) {
        self.route = route; self.dismiss = dismiss; self.expand = expand
        self.actions = actions; self.performAction = performAction
    }

    public var body: some View {
        Group {
            if route == .home, let actions {
                resolvedActionsView(actions)
            } else {
                legacyRouteView
            }
        }
        .padding(route == .home ? 0 : 16)
        .frame(minWidth: route == .home ? 520 : 260, minHeight: route == .home ? 160 : 56)
        .background {
            if route != .home {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func resolvedActionsView(_ resolution: ActionResolution) -> some View {
        ShelfPillView(
            resolution: resolution,
            dismiss: dismiss,
            expand: expand,
            performAction: performAction,
            icon: icon(for:)
        )
    }

    private var legacyRouteView: some View {
        HStack(spacing: 12) {
            Text(title).accessibilityLabel(title)
            Spacer()
            if route == .home {
                Button("Open", action: expand).keyboardShortcut(.return, modifiers: [])
            }
            Button("Dismiss", action: dismiss).keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var title: String {
        switch route {
        case .home: "Ledge"
        case .meeting: "Meeting"
        case .quickCapture: "Quick Capture"
        case .searchClipboard: "Search Clipboard"
        case .audioControls: "Audio Controls"
        case .settings: "Settings"
        }
    }

    private func icon(for feature: FeatureID) -> String {
        switch feature {
        case .meetings: "video"
        case .handoff: "tray.and.arrow.down"
        case .quickCapture: "square.and.pencil"
        case .clipboard: "doc.on.clipboard"
        case .audio: "speaker.wave.2"
        case .screenshot: "camera"
        case .recovery: "gearshape"
        case .shell: "square.grid.2x2"
        }
    }
}

private struct ShelfPillView: View {
    let resolution: ActionResolution
    let dismiss: () -> Void
    let expand: () -> Void
    let performAction: ((ActionCandidate) -> Void)?
    let icon: (FeatureID) -> String
    @State private var isHovering = false

    private var primary: ActionCandidate? { resolution.primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("LEDGE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.54))
                    Text(primary?.title ?? "Ready when you are")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle = primary?.subtitle, !isHovering {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let primary {
                    Circle()
                        .fill(primary.urgency == .immediate ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(primary.urgency == .immediate ? "Immediate action" : "Available action")
                }

                ForEach(resolution.secondary) { candidate in
                    Button {
                        if let performAction { performAction(candidate) } else { expand() }
                    } label: {
                        Image(systemName: icon(candidate.feature))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.09), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(candidate.title)
                    .accessibilityIdentifier("shelf.secondary-action.\(candidate.id.uuidString)")
                    .accessibilityLabel(candidate.title)
                }

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.54))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("shelf.dismiss")
                .accessibilityLabel("Dismiss shelf")
            }

            if isHovering {
                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.vertical, 10)

                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Local only")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))

                    if let subtitle = primary?.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)
                    } else {
                        Text("The next useful action is one key away")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                    }

                    Spacer(minLength: 8)

                    if let primary {
                        Button {
                            if let performAction { performAction(primary) } else { expand() }
                        } label: {
                            Label("Open", systemImage: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityIdentifier("shelf.primary-action")
                        .accessibilityLabel(primary.title)
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(width: 500, height: isHovering ? 132 : 62, alignment: .top)
        .background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: isHovering ? 24 : 31, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isHovering ? 24 : 31, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .accessibilityElement(children: .contain)
    }
}
