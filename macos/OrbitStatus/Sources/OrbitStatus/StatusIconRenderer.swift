import AppKit

enum StatusIconRenderer {
    static func image(state: OrbitStatusModel.ConnectionState) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let result = NSImage(size: size, flipped: false) { _ in
            let iconRect = NSRect(x: 1, y: 1, width: 17, height: 16)
            OrbitBrandIcon.image.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            NSColor.labelColor.setFill()
            let context = NSGraphicsContext.current
            let previousOperation = context?.compositingOperation
            context?.compositingOperation = .sourceAtop
            NSBezierPath(rect: iconRect).fill()
            if let previousOperation {
                context?.compositingOperation = previousOperation
            }

            let badgeRect = NSRect(x: 15, y: 1, width: 6, height: 6)
            state.color.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            return true
        }
        result.isTemplate = false
        return result
    }

}
