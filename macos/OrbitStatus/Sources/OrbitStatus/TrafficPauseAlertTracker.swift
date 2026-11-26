import AppKit

struct TrafficPauseAlertTracker {
    enum Action: Equatable {
        case none
        case present
        case dismiss
    }

    private(set) var episodeAcknowledged = false
    private(set) var isPresented = false

    mutating func update(isBlocked: Bool) -> Action {
        if isBlocked {
            guard !episodeAcknowledged else { return .none }
            episodeAcknowledged = true
            isPresented = true
            return .present
        }

        episodeAcknowledged = false
        guard isPresented else { return .none }
        isPresented = false
        return .dismiss
    }

    mutating func didDismiss() {
        isPresented = false
    }
}

enum TrafficPauseAlertFactory {
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = blockedIcon()
        alert.messageText = "Трафик приостановлен"
        alert.informativeText = "Статический выход недоступен. Orbit остановил трафик, чтобы исключить прямой выход. Когда выход заработает, доступ вернётся сам. Окно можно закрыть."
        alert.addButton(withTitle: "Закрыть")
        return alert
    }

    private static func blockedIcon() -> NSImage {
        let size = NSSize(width: 96, height: 96)
        let image = NSImage(size: size, flipped: false) { _ in
            OrbitBrandIcon.image.draw(
                in: NSRect(x: 8, y: 8, width: 76, height: 76),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            let badge = NSRect(x: 64, y: 16, width: 16, height: 16)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -2.5, dy: -2.5)).fill()
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: badge).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
