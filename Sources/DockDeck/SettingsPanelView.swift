import Cocoa

final class SettingsPanelView: NSView {
    private let padding: CGFloat = 12
    private let rowGap: CGFloat = 11
    private let sectionGap: CGFloat = 16
    private let controlWidth: CGFloat = 220
    private let closeButtonSize: CGFloat = 14

    private let cornerRadiusSlider = NSSlider()
    private let tintOpacitySlider = NSSlider()
    private let focusWidthSlider = NSSlider()
    private let focusHeightSlider = NSSlider()
    private let usageFontSizeSlider = NSSlider()
    private let focusWidthLabel = NSTextField(labelWithString: "")
    private let focusHeightLabel = NSTextField(labelWithString: "")
    private let usageFontSizeLabel = NSTextField(labelWithString: "")
    private let terminalFontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let usageFontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let usageDisplayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let usageColorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let panelOrderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontNames: [String]
    private let usageDisplayModes = UsageDisplayMode.allCases
    private let usageColors = UsageTextColor.allCases
    private let panelOrders = PanelOrder.allCases

    var onCornerRadiusChange: ((CGFloat) -> Void)?
    var onTintOpacityChange: ((CGFloat) -> Void)?
    var onFocusSizeChange: ((CGFloat, CGFloat) -> Void)?
    var onTerminalFontChange: ((String) -> Void)?
    var onUsageFontChange: ((String) -> Void)?
    var onUsageFontSizeChange: ((CGFloat) -> Void)?
    var onUsageDisplayModeChange: ((UsageDisplayMode) -> Void)?
    var onUsageTextColorChange: ((UsageTextColor) -> Void)?
    var onPanelOrderChange: ((PanelOrder) -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?

    init(
        cornerRadius: CGFloat, tintOpacity: CGFloat,
        focusWidthMultiplier: CGFloat, focusHeightMultiplier: CGFloat,
        fontNames: [String], selectedTerminalFontName: String,
        selectedUsageFontName: String, usageFontSize: CGFloat,
        usageDisplayMode: UsageDisplayMode, usageTextColor: UsageTextColor,
        panelOrder: PanelOrder
    ) {
        self.fontNames = fontNames
        let width = controlWidth + padding * 2

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        var y: CGFloat = padding

        let title = Self.makeLabel("DockDeck Settings", size: 12, weight: .semibold, alpha: 0.88)
        title.frame = NSRect(
            x: padding, y: y, width: controlWidth - closeButtonSize - 6, height: 16)
        addSubview(title)

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
            target: self, action: #selector(closeTapped))
        closeButton.frame = NSRect(
            x: width - padding - closeButtonSize, y: y + 1,
            width: closeButtonSize, height: closeButtonSize)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        (closeButton.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
        addSubview(closeButton)
        y += 16 + sectionGap

        y = addSection("PANELS", at: y)

        y = addLabel("Placement", at: y)
        configurePopup(panelOrderPopup, action: #selector(panelOrderChanged))
        panelOrders.forEach { panelOrderPopup.addItem(withTitle: $0.title) }
        panelOrderPopup.frame = NSRect(x: padding, y: y, width: controlWidth, height: 22)
        select(panelOrder, in: panelOrders, popup: panelOrderPopup)
        addSubview(panelOrderPopup)
        y += 22 + rowGap

        y = addLabel("Corner radius", at: y)
        configureSlider(
            cornerRadiusSlider, min: 0, max: 24, value: cornerRadius,
            action: #selector(cornerRadiusChanged))
        cornerRadiusSlider.frame = NSRect(x: padding, y: y, width: controlWidth, height: 20)
        addSubview(cornerRadiusSlider)
        y += 20 + rowGap

        y = addLabel("Theme tint", at: y)
        configureSlider(
            tintOpacitySlider, min: 0.2, max: 1, value: tintOpacity,
            action: #selector(opacityChanged))
        tintOpacitySlider.frame = NSRect(x: padding, y: y, width: controlWidth, height: 20)
        addSubview(tintOpacitySlider)
        y += 20 + sectionGap

        y = addSection("TERMINAL", at: y)

        configureValueLabel(focusWidthLabel)
        focusWidthLabel.frame = NSRect(x: padding, y: y, width: controlWidth, height: 14)
        addSubview(focusWidthLabel)
        y += 18
        configureSlider(
            focusWidthSlider,
            min: DockPanelLayout.minimumFocusedWidthMultiplier,
            max: DockPanelLayout.maximumFocusedWidthMultiplier,
            value: focusWidthMultiplier, action: #selector(focusSizeChanged))
        focusWidthSlider.frame = NSRect(x: padding, y: y, width: controlWidth, height: 20)
        addSubview(focusWidthSlider)
        y += 20 + rowGap

        configureValueLabel(focusHeightLabel)
        focusHeightLabel.frame = NSRect(x: padding, y: y, width: controlWidth, height: 14)
        addSubview(focusHeightLabel)
        y += 18
        configureSlider(
            focusHeightSlider,
            min: DockPanelLayout.minimumFocusedHeightMultiplier,
            max: DockPanelLayout.maximumFocusedHeightMultiplier,
            value: focusHeightMultiplier, action: #selector(focusSizeChanged))
        focusHeightSlider.frame = NSRect(x: padding, y: y, width: controlWidth, height: 20)
        addSubview(focusHeightSlider)
        y += 20 + rowGap

        y = addLabel("Terminal font", at: y)
        configureFontPopup(
            terminalFontPopup, selectedName: selectedTerminalFontName,
            action: #selector(terminalFontChanged))
        terminalFontPopup.frame = NSRect(x: padding, y: y, width: controlWidth, height: 22)
        addSubview(terminalFontPopup)
        y += 22 + sectionGap

        y = addSection("USAGE", at: y)

        y = addLabel("Values", at: y)
        configurePopup(usageDisplayPopup, action: #selector(usageDisplayChanged))
        usageDisplayModes.forEach { usageDisplayPopup.addItem(withTitle: $0.title) }
        usageDisplayPopup.frame = NSRect(x: padding, y: y, width: controlWidth, height: 22)
        select(usageDisplayMode, in: usageDisplayModes, popup: usageDisplayPopup)
        addSubview(usageDisplayPopup)
        y += 22 + rowGap

        y = addLabel("Usage font", at: y)
        configureFontPopup(
            usageFontPopup, selectedName: selectedUsageFontName,
            action: #selector(usageFontChanged))
        usageFontPopup.frame = NSRect(x: padding, y: y, width: controlWidth, height: 22)
        addSubview(usageFontPopup)
        y += 22 + rowGap

        configureValueLabel(usageFontSizeLabel)
        usageFontSizeLabel.frame = NSRect(x: padding, y: y, width: controlWidth, height: 14)
        addSubview(usageFontSizeLabel)
        y += 18
        configureSlider(
            usageFontSizeSlider,
            min: PanelSettings.minimumUsageFontSize,
            max: PanelSettings.maximumUsageFontSize,
            value: usageFontSize, action: #selector(usageFontSizeChanged))
        usageFontSizeSlider.frame = NSRect(x: padding, y: y, width: controlWidth, height: 20)
        addSubview(usageFontSizeSlider)
        y += 20 + rowGap

        y = addLabel("Text color", at: y)
        configurePopup(usageColorPopup, action: #selector(usageColorChanged))
        usageColors.forEach { usageColorPopup.addItem(withTitle: $0.title) }
        usageColorPopup.frame = NSRect(x: padding, y: y, width: controlWidth, height: 22)
        select(usageTextColor, in: usageColors, popup: usageColorPopup)
        addSubview(usageColorPopup)
        y += 22 + sectionGap

        let resetButton = NSButton(
            title: "Reset to Defaults", target: self, action: #selector(resetTapped))
        resetButton.isBordered = false
        resetButton.contentTintColor = NSColor.white.withAlphaComponent(0.58)
        resetButton.font = NSFont.systemFont(ofSize: 10)
        resetButton.frame = NSRect(x: padding, y: y, width: controlWidth, height: 14)
        addSubview(resetButton)
        y += 14 + padding

        updateValueLabels()
        frame = NSRect(x: 0, y: 0, width: width, height: y)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    func setValues(
        cornerRadius: CGFloat, tintOpacity: CGFloat,
        focusWidthMultiplier: CGFloat, focusHeightMultiplier: CGFloat,
        terminalFontName: String, usageFontName: String, usageFontSize: CGFloat,
        usageDisplayMode: UsageDisplayMode, usageTextColor: UsageTextColor,
        panelOrder: PanelOrder
    ) {
        cornerRadiusSlider.doubleValue = Double(cornerRadius)
        tintOpacitySlider.doubleValue = Double(tintOpacity)
        focusWidthSlider.doubleValue = Double(focusWidthMultiplier)
        focusHeightSlider.doubleValue = Double(focusHeightMultiplier)
        usageFontSizeSlider.doubleValue = Double(usageFontSize)
        selectFont(terminalFontName, popup: terminalFontPopup)
        selectFont(usageFontName, popup: usageFontPopup)
        select(usageDisplayMode, in: usageDisplayModes, popup: usageDisplayPopup)
        select(usageTextColor, in: usageColors, popup: usageColorPopup)
        select(panelOrder, in: panelOrders, popup: panelOrderPopup)
        updateValueLabels()
    }

    @objc private func cornerRadiusChanged() {
        onCornerRadiusChange?(CGFloat(cornerRadiusSlider.doubleValue))
    }

    @objc private func opacityChanged() {
        onTintOpacityChange?(CGFloat(tintOpacitySlider.doubleValue))
    }

    @objc private func focusSizeChanged() {
        focusWidthSlider.doubleValue = (focusWidthSlider.doubleValue * 4).rounded() / 4
        focusHeightSlider.doubleValue = (focusHeightSlider.doubleValue * 4).rounded() / 4
        updateValueLabels()
        onFocusSizeChange?(
            CGFloat(focusWidthSlider.doubleValue), CGFloat(focusHeightSlider.doubleValue))
    }

    @objc private func terminalFontChanged() {
        guard let fontName = selectedFont(in: terminalFontPopup) else { return }
        onTerminalFontChange?(fontName)
    }

    @objc private func usageFontChanged() {
        guard let fontName = selectedFont(in: usageFontPopup) else { return }
        onUsageFontChange?(fontName)
    }

    @objc private func usageFontSizeChanged() {
        usageFontSizeSlider.doubleValue = (usageFontSizeSlider.doubleValue * 2).rounded() / 2
        updateValueLabels()
        onUsageFontSizeChange?(CGFloat(usageFontSizeSlider.doubleValue))
    }

    @objc private func usageDisplayChanged() {
        let index = usageDisplayPopup.indexOfSelectedItem
        guard usageDisplayModes.indices.contains(index) else { return }
        onUsageDisplayModeChange?(usageDisplayModes[index])
    }

    @objc private func usageColorChanged() {
        let index = usageColorPopup.indexOfSelectedItem
        guard usageColors.indices.contains(index) else { return }
        onUsageTextColorChange?(usageColors[index])
    }

    @objc private func panelOrderChanged() {
        let index = panelOrderPopup.indexOfSelectedItem
        guard panelOrders.indices.contains(index) else { return }
        onPanelOrderChange?(panelOrders[index])
    }

    @objc private func resetTapped() {
        onReset?()
    }

    @objc private func closeTapped() {
        onCancel?()
    }

    private func addSection(_ text: String, at y: CGFloat) -> CGFloat {
        let label = Self.makeLabel(text, size: 9, weight: .semibold, alpha: 0.38)
        label.frame = NSRect(x: padding, y: y, width: controlWidth, height: 12)
        addSubview(label)
        return y + 12 + 8
    }

    private func addLabel(_ text: String, at y: CGFloat) -> CGFloat {
        let label = Self.makeLabel(text)
        label.frame = NSRect(x: padding, y: y, width: controlWidth, height: 14)
        addSubview(label)
        return y + 18
    }

    private func configureSlider(
        _ slider: NSSlider, min: CGFloat, max: CGFloat, value: CGFloat, action: Selector
    ) {
        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.doubleValue = Double(value)
        slider.isContinuous = true
        slider.target = self
        slider.action = action
    }

    private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
        popup.target = self
        popup.action = action
    }

    private func configureFontPopup(
        _ popup: NSPopUpButton, selectedName: String, action: Selector
    ) {
        configurePopup(popup, action: action)
        fontNames.forEach {
            popup.addItem(withTitle: TerminalTheme.displayName(forFontName: $0))
        }
        selectFont(selectedName, popup: popup)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.52)
    }

    private func updateValueLabels() {
        focusWidthLabel.stringValue = String(
            format: "Click expansion width %.2g×", focusWidthSlider.doubleValue)
        focusHeightLabel.stringValue = String(
            format: "Click expansion height %.2g×", focusHeightSlider.doubleValue)
        usageFontSizeLabel.stringValue = String(
            format: "Usage font size %.1f pt", usageFontSizeSlider.doubleValue)
    }

    private func selectedFont(in popup: NSPopUpButton) -> String? {
        let index = popup.indexOfSelectedItem
        guard fontNames.indices.contains(index) else { return nil }
        return fontNames[index]
    }

    private func selectFont(_ name: String, popup: NSPopUpButton) {
        guard let index = fontNames.firstIndex(of: name) else { return }
        popup.selectItem(at: index)
    }

    private func select<Value: Equatable>(
        _ value: Value, in values: [Value], popup: NSPopUpButton
    ) {
        guard let index = values.firstIndex(of: value) else { return }
        popup.selectItem(at: index)
    }

    private static func makeLabel(
        _ text: String, size: CGFloat = 10, weight: NSFont.Weight = .medium,
        alpha: CGFloat = 0.52
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor.white.withAlphaComponent(alpha)
        return label
    }
}
