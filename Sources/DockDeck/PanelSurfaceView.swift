import Cocoa
import SwiftUI

enum CompactReadability {
    static let preferenceKey = "dockdeck.readablePanels"
    static func size(_ value: CGFloat, enabled: Bool) -> CGFloat { enabled ? max(value, 10) : value }
}

private struct CompactReadableKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var compactReadable: Bool {
        get { self[CompactReadableKey.self] }
        set { self[CompactReadableKey.self] = newValue }
    }
}

enum PanelPresentation {
    case compact
    case readable
}

enum PanelAppearance {
    static func tintOpacity(base: CGFloat, presentation: PanelPresentation) -> CGFloat {
        let bounded = min(max(base, 0), 1)
        switch presentation {
        case .compact:
            return min(max(bounded * 0.38, 0.16), 0.34)
        case .readable:
            return min(max(bounded + 0.16, 0.82), 0.94)
        }
    }
}

final class PanelSurfaceView: NSView {
    let contentContainer: NSView
    var onScrollWheel: ((NSEvent) -> Bool)?

    private let backdropView: NSView
    private let fallbackTintView: NSView?
    private let usesLiquidGlass: Bool
    private var currentTheme: Theme
    private var currentPresentation: PanelPresentation
    private var accessibilityObserver: NSObjectProtocol?

    init(
        frame: NSRect, theme: Theme, presentation: PanelPresentation = .compact
    ) {
        let contentContainer = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentContainer.autoresizingMask = [.width, .height]
        contentContainer.wantsLayer = true

        let backdropView: NSView
        let fallbackTintView: NSView?
        let usesLiquidGlass: Bool

        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            backdropView = glassType.init(frame: NSRect(origin: .zero, size: frame.size))
            fallbackTintView = nil
            usesLiquidGlass = true
        } else {
            let effectView = NSVisualEffectView(
                frame: NSRect(origin: .zero, size: frame.size))
            effectView.material = .menu
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.borderWidth = 1
            effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

            let tintView = NSView(frame: contentContainer.bounds)
            tintView.autoresizingMask = [.width, .height]
            tintView.wantsLayer = true
            contentContainer.addSubview(tintView)
            effectView.addSubview(contentContainer)

            backdropView = effectView
            fallbackTintView = tintView
            usesLiquidGlass = false
        }

        self.currentTheme = theme
        self.currentPresentation = presentation
        self.contentContainer = contentContainer
        self.backdropView = backdropView
        self.fallbackTintView = fallbackTintView
        self.usesLiquidGlass = usesLiquidGlass
        super.init(frame: frame)

        autoresizesSubviews = true
        backdropView.autoresizingMask = [.width, .height]
        addSubview(backdropView)

        if usesLiquidGlass {
            backdropView.setValue(contentContainer, forKey: "contentView")
        }

        applyCornerRadius()
        apply(theme: theme, presentation: presentation)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.apply(theme: self.currentTheme, presentation: self.currentPresentation)
        }
    }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        if onScrollWheel?(event) == true { return }
        super.scrollWheel(with: event)
    }

    func apply(theme: Theme, presentation: PanelPresentation) {
        currentTheme = theme
        currentPresentation = presentation
        let workspace = NSWorkspace.shared
        let opaque = workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
        contentContainer.layer?.backgroundColor = opaque
            ? theme.tintColor(opacity: 1).cgColor : nil
        let baseOpacity = PanelSettings.tintOpacity ?? theme.panelTintColor.alphaComponent
        let opacity = PanelAppearance.tintOpacity(
            base: baseOpacity, presentation: presentation)
        let tintColor = theme.tintColor(opacity: opacity)

        if usesLiquidGlass {
            backdropView.setValue(tintColor, forKey: "tintColor")
        } else {
            fallbackTintView?.layer?.backgroundColor = tintColor.cgColor
        }
    }

    func applyCornerRadius() {
        let radius = PanelSettings.cornerRadius
        contentContainer.layer?.cornerRadius = radius
        contentContainer.layer?.masksToBounds = true

        if usesLiquidGlass {
            backdropView.setValue(radius, forKey: "cornerRadius")
        } else {
            backdropView.layer?.cornerRadius = radius
            backdropView.layer?.masksToBounds = true
        }
    }
}

/// The thin progress track shared by compact panels: a faint capsule with a colored fill.
struct CapsuleMeter: View {
    let fraction: Double
    let color: Color
    let baseColor: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(baseColor.opacity(0.14))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(Self.clamped(fraction)))
            }
        }
        .frame(height: height)
    }

    static func clamped(_ fraction: Double) -> Double {
        fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }
}

/// One empty, loading, or error message for a compact panel.
struct CompactPlaceholder: View {
    @Environment(\.compactReadable) private var readable
    let text: String
    let symbol: String
    let baseColor: Color
    var isLoading = false

    var body: some View {
        HStack(spacing: 7) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
            }
            Text(text).lineLimit(2)
        }
        .font(.system(size: CompactReadability.size(9.5, enabled: readable), weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .minimumScaleFactor(readable ? 1 : 0.8)
        .padding(.horizontal, 9)
        .accessibilityElement(children: .combine)
    }
}

/// The small uppercase status chip ("NOW", "DUE") that leads a compact list row.
struct CompactBadge: View {
    @Environment(\.compactReadable) private var readable
    let text: String
    let color: Color
    let baseColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: CompactReadability.size(7.5, enabled: readable), weight: .bold, design: .rounded))
            .foregroundStyle(baseColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.24)))
    }
}
