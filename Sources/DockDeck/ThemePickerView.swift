import Cocoa

final class ThemePickerView: NSView {
    private let themes: [Theme]
    private var selectedIndex: Int
    private let rowHeight: CGFloat = 22
    private let headerHeight: CGFloat = 18

    private struct Row {
        let theme: Theme?
        let header: String?
        let y: CGFloat
        let height: CGFloat
    }

    private let rows: [Row]

    var onCommit: ((Theme) -> Void)?
    var onCancel: (() -> Void)?

    init(themes: [Theme], selectedID: String) {
        self.themes = themes
        self.selectedIndex = themes.firstIndex { $0.id == selectedID } ?? 0

        var rows: [Row] = []
        var y: CGFloat = 4
        var lastIsDark: Bool?
        for theme in themes {
            if theme.isDark != lastIsDark {
                rows.append(
                    Row(
                        theme: nil, header: theme.isDark ? "DARK" : "LIGHT", y: y,
                        height: headerHeight))
                y += headerHeight
                lastIsDark = theme.isDark
            }
            rows.append(Row(theme: theme, header: nil, y: y, height: rowHeight))
            y += rowHeight
        }
        self.rows = rows

        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: y + 4))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let selectedID = themes[selectedIndex].id
        for row in rows {
            if let header = row.header {
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                    .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                ]
                let origin = NSPoint(x: 10, y: row.y + row.height - 13)
                header.draw(at: origin, withAttributes: attributes)
                continue
            }
            guard let theme = row.theme else { continue }
            let rowRect = NSRect(x: 4, y: row.y, width: bounds.width - 8, height: row.height)
            let isSelected = theme.id == selectedID
            if isSelected {
                NSColor.white.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
            ]
            let textSize = theme.name.size(withAttributes: attributes)
            let origin = NSPoint(
                x: rowRect.minX + 10, y: rowRect.minY + (rowRect.height - textSize.height) / 2)
            theme.name.draw(at: origin, withAttributes: attributes)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: move(-1)
        case 125: move(1)
        case 36, 76: onCommit?(themes[selectedIndex])
        case 53: onCancel?()
        default: break
        }
    }

    private func move(_ delta: Int) {
        selectedIndex = (selectedIndex + delta + themes.count) % themes.count
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard
            let row = rows.first(where: {
                guard $0.theme != nil else { return false }
                let rowRect = NSRect(x: 4, y: $0.y, width: bounds.width - 8, height: $0.height)
                return rowRect.contains(point)
            }),
            let theme = row.theme
        else { return }
        selectedIndex = themes.firstIndex { $0.id == theme.id } ?? selectedIndex
        needsDisplay = true
        onCommit?(theme)
    }
}
