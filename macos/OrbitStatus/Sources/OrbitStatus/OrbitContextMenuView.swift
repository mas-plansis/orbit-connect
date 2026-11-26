import AppKit
import SwiftUI

struct OrbitContextMenuView: View {
    @ObservedObject var model: OrbitStatusModel
    let openKeeneticOS: () -> Void
    let openOrbit: () -> Void
    let restart: () -> Void
    let checkForUpdates: () -> Void
    let settings: () -> Void
    let unlink: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("KEENETICOS")
            action("Открыть KeeneticOS", icon: "wifi.router", action: openKeeneticOS)

            Divider()
                .overlay(OrbitConnectTheme.border)
                .padding(.vertical, 4)

            sectionTitle("ORBIT")
            action("Открыть Orbit", image: OrbitBrandIcon.image, action: openOrbit)
            action("Настройки", icon: "gearshape", action: settings)
            action("Перезапустить Orbit Connect", icon: "arrow.clockwise", action: restart)
            action(
                model.checkingForUpdate ? "Проверяем обновления…" : "Проверить обновления",
                icon: "arrow.triangle.2.circlepath",
                disabled: model.checkingForUpdate,
                action: checkForUpdates
            )

            if model.isPaired {
                action(
                    "Разорвать связь",
                    icon: "link",
                    color: .orange,
                    action: unlink
                )
            }

            Divider()
                .overlay(OrbitConnectTheme.border)
                .padding(.vertical, 4)

            action("Закрыть", icon: "rectangle.portrait.and.arrow.right", color: .red, action: close)
        }
        .padding(6)
        .frame(width: 300)
        .background(OrbitConnectTheme.canvas)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(OrbitConnectTheme.sectionFont)
            .tracking(1.3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func action(
        _ title: String,
        icon: String? = nil,
        image: NSImage? = nil,
        color: Color = OrbitConnectTheme.accent,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .regular))
                    }
                }
                .frame(width: 18, height: 18)
                .foregroundStyle(disabled ? Color.secondary : color)
                Text(title)
                    .font(OrbitConnectTheme.bodyFont)
                    .foregroundStyle(disabled ? Color.secondary : OrbitConnectTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(OrbitMenuButtonStyle())
        .disabled(disabled)
    }

}

private struct OrbitMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitMenuButtonBody(configuration: configuration)
    }
}

private struct OrbitMenuButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(
                isHovering || configuration.isPressed
                    ? OrbitConnectTheme.accent.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .onHover { isHovering = $0 }
    }
}
