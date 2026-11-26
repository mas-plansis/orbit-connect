import AppKit
import SwiftUI

enum OrbitAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "orbit-connect-appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum OrbitConnectTheme {
    static let accent = Color(red: 0.12, green: 0.72, blue: 0.68)
    static let canvas = dynamicColor(
        light: NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.055, green: 0.075, blue: 0.105, alpha: 1)
    )
    static let sidebar = dynamicColor(
        light: NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.086, green: 0.118, blue: 0.153, alpha: 1)
    )
    static let border = dynamicColor(
        light: NSColor(srgbRed: 0.87, green: 0.90, blue: 0.94, alpha: 1),
        dark: NSColor(srgbRed: 0.18, green: 0.23, blue: 0.30, alpha: 1)
    )
    static let ink = Color(nsColor: .labelColor)
    static let card = dynamicColor(
        light: .white,
        dark: NSColor(srgbRed: 0.09, green: 0.12, blue: 0.16, alpha: 1)
    )

    static let titleFont = Font.system(size: 16, weight: .regular)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let compactFont = Font.system(size: 13, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let sectionFont = Font.system(size: 11, weight: .medium)

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        )
    }
}

private struct OrbitAppearanceModifier: ViewModifier {
    @AppStorage(
        OrbitAppearanceMode.storageKey,
        store: OrbitRuntime.defaults
    ) private var modeRawValue = OrbitAppearanceMode.system.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(
            OrbitAppearanceMode(rawValue: modeRawValue)?.colorScheme
        )
    }
}

extension View {
    func orbitAppearance() -> some View {
        modifier(OrbitAppearanceModifier())
    }
}
