import SwiftUI

struct DockDeckMark: View {
    static let aspectRatio: CGFloat = 1

    private let cyan = Color(red: 0.11, green: 0.82, blue: 0.97)
    private let coral = Color(red: 1, green: 0.36, blue: 0.24)

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2)
            let strokeWidth = max(1, side * 0.065)

            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat)
                -> CGRect
            {
                CGRect(
                    x: origin.x + side * x,
                    y: origin.y + side * y,
                    width: side * width,
                    height: side * height)
            }

            let leftPanel = Path(
                roundedRect: rect(0.08, 0.1, 0.38, 0.78),
                cornerRadius: side * 0.09)
            let rightPanel = Path(
                roundedRect: rect(0.54, 0.1, 0.38, 0.78),
                cornerRadius: side * 0.09)
            context.stroke(leftPanel, with: .color(cyan), lineWidth: strokeWidth)
            context.stroke(rightPanel, with: .color(coral), lineWidth: strokeWidth)

            var prompt = Path()
            prompt.move(to: CGPoint(x: origin.x + side * 0.18, y: origin.y + side * 0.38))
            prompt.addLine(to: CGPoint(x: origin.x + side * 0.28, y: origin.y + side * 0.48))
            prompt.addLine(to: CGPoint(x: origin.x + side * 0.18, y: origin.y + side * 0.58))
            context.stroke(
                prompt,
                with: .color(cyan),
                style: StrokeStyle(
                    lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

            for (x, y, height) in [
                (0.63, 0.56, 0.12),
                (0.72, 0.47, 0.21),
                (0.81, 0.36, 0.32),
            ] {
                let bar = Path(
                    roundedRect: rect(x, y, 0.055, height),
                    cornerRadius: side * 0.03)
                context.fill(bar, with: .color(coral))
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
    }
}
