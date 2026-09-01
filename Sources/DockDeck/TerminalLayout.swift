import Cocoa
import CoreText

enum TerminalLayout {
    static func contentFrame(in bounds: NSRect, font: NSFont) -> NSRect {
        let usableWidth = bounds.width - TerminalTheme.padding * 2
        let usableHeight = bounds.height - TerminalTheme.padding * 2
        let cellHeight = estimatedCellHeight(for: font)
        let rows = max(1, Int(usableHeight / cellHeight))
        let contentHeight = CGFloat(rows) * cellHeight
        let verticalSlack = (usableHeight - contentHeight) / 2
        return NSRect(
            x: bounds.minX + TerminalTheme.padding,
            y: bounds.minY + TerminalTheme.padding + verticalSlack,
            width: max(usableWidth, 0),
            height: max(contentHeight, 0)
        )
    }

    static func estimatedCellHeight(for font: NSFont) -> CGFloat {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return ceil(ascent + descent + leading)
    }
}
