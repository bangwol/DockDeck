import Cocoa

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
