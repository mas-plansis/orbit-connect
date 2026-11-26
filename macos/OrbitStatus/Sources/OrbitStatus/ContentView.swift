import SwiftUI

struct ContentView: View {
    @ObservedObject var model: OrbitStatusModel
    @State private var confirmingStaticExitDisable = false

    private let accent = OrbitConnectTheme.accent
    private let canvas = OrbitConnectTheme.canvas
    private let border = OrbitConnectTheme.border
    private let ink = OrbitConnectTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.isPaired {
                status
            } else {
                pairing
            }
            if !model.errorMessage.isEmpty {
                Label(model.errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(canvas)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .orbitAppearance()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                Circle()
                    .fill(Color(nsColor: model.state.color))
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Orbit Connect")
                        .font(OrbitConnectTheme.titleFont)
                        .foregroundStyle(ink)
                    Text("v\(model.currentVersion)")
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(canvas, in: Capsule())
                }
                Text(model.isPaired ? (model.status?.device ?? model.pairedDevice) : "Устройство не связано")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(border))
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Связать с Orbit", systemImage: "link")
                .font(OrbitConnectTheme.bodyFont)
                .foregroundStyle(ink)
            Text("В Orbit откройте Устройства, выберите меню устройства и нажмите «Связать по ключу».")
                .font(OrbitConnectTheme.compactFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PairingKeyField(text: $model.pairingKey) {
                guard !model.loading,
                      !model.pairingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                model.pair()
            }
            Button {
                model.pair()
            } label: {
                Text("Подключить")
                    .font(OrbitConnectTheme.bodyFont)
            }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(model.loading || model.pairingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .orbitCard(border: border)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.status?.trafficBlocked == true {
                staticExitProtection
            }

            compactSummary

            if !routeSteps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label(
                            "Маршрут",
                            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                        )
                        .font(OrbitConnectTheme.bodyFont)
                        .foregroundStyle(ink)

                        Spacer()

                        HStack(spacing: 5) {
                            Circle()
                                .fill(model.status?.trafficBlocked == true ? Color.red : accent)
                                .frame(width: 7, height: 7)
                            Text(model.status?.trafficBlocked == true ? "Остановлен" : "\(routeSteps.count) узла")
                                .font(OrbitConnectTheme.captionFont)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(routeSteps.enumerated()), id: \.offset) { index, step in
                            compactRouteRow(step)
                            if index < routeSteps.count - 1 {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 34, height: 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .orbitCard(border: border)
            }

            if model.status?.macChanged == true {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Wi-Fi адрес устройства изменился", systemImage: "wifi.exclamationmark")
                        .font(OrbitConnectTheme.bodyFont)
                    Text("Orbit автоматически переносит постоянный адрес и правило со старой записи на текущую.")
                        .font(OrbitConnectTheme.compactFont)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.24)))
            }

        }
    }

    private var staticExitProtection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Трафик приостановлен", systemImage: "exclamationmark.shield.fill")
                .font(OrbitConnectTheme.bodyFont)
                .foregroundStyle(.red)
            Text(model.status?.staticExitError ?? model.status?.statusDetail ?? "Статический выход не прошёл проверку")
                .font(OrbitConnectTheme.compactFont)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Прямые и локальные правила Orbit продолжают работать. Остальной трафик возобновится только после восстановления статического выхода.")
                .font(OrbitConnectTheme.captionFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Проверить снова") {
                    model.retryStaticExit()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(model.loading)

                Button("Открыть Orbit") {
                    model.openOrbit(path: "/servers")
                }
                .buttonStyle(.bordered)
            }
            Button("Отключить статический выход") {
                confirmingStaticExitDisable = true
            }
            .buttonStyle(.plain)
            .font(OrbitConnectTheme.captionFont)
            .foregroundStyle(.red)
            .disabled(model.loading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.22)))
        .confirmationDialog(
            "Отключить статический выход?",
            isPresented: $confirmingStaticExitDisable,
            titleVisibility: .visible
        ) {
            Button("Отключить статический выход", role: .destructive) {
                model.disableStaticExit()
            }
            Button("Отменить", role: .cancel) {}
        } message: {
            Text("Orbit вернётся к обычному маршруту через основной выход. Прямые и Geo-правила сохранятся.")
        }
    }

    private var routeSteps: [ClientRouteStep] {
        if let steps = model.status?.routeSteps, !steps.isEmpty {
            return steps
        }
        return (model.status?.chain ?? []).enumerated().map { index, label in
            let role: String
            if index == 0 {
                role = "device"
            } else if label == "Интернет" {
                role = "internet"
            } else if label == "Напрямую" {
                role = "direct"
            } else {
                role = "primary"
            }
            return ClientRouteStep(
                role: role,
                label: label,
                server: nil,
                protocol: nil,
                ip: nil,
                countryCode: nil
            )
        }
    }

    private func routeIcon(for role: String) -> String {
        switch role {
        case "device": return "laptopcomputer"
        case "primary": return "server.rack"
        case "static_exit": return "arrow.up.right.circle"
        case "blocked": return "hand.raised.fill"
        case "direct": return "arrow.right"
        case "internet": return "globe"
        default: return "circle"
        }
    }

    private func routeColor(for role: String) -> Color {
        switch role {
        case "static_exit": return Color(red: 0.44, green: 0.40, blue: 0.72)
        case "direct": return .green
        case "internet": return .green
        case "blocked": return .red
        default: return accent
        }
    }

    private func compactRouteRow(_ step: ClientRouteStep) -> some View {
        let server = step.server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let routeProtocol = step.protocol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ip = step.ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = [
            server.isEmpty ? nil : server,
            routeProtocol.isEmpty ? nil : routeProtocol,
            ip.isEmpty ? nil : ip,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let tint = routeColor(for: step.role)

        return HStack(spacing: 11) {
            Image(systemName: routeIcon(for: step.role))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(OrbitConnectTheme.compactFont.weight(.semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            if step.role == "static_exit" {
                Image(systemName: model.status?.trafficBlocked == true ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.status?.trafficBlocked == true ? Color.red : tint)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactSummary: some View {
        VStack(spacing: 0) {
            compactSummaryRow(
                title: "Конечный адрес",
                text: model.status?.finalIP ?? "Не определён",
                icon: "network",
                tint: accent
            )

            Divider()
                .overlay(border)
                .padding(.leading, 14)

            compactSummaryRow(
                title: "Регион",
                text: model.regionName,
                icon: "flag.fill",
                tint: Color(red: 0.44, green: 0.40, blue: 0.72)
            )
        }
        .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
    }

    private func compactSummaryRow(
        title: String,
        text: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(OrbitConnectTheme.bodyFont)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.10), in: Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appIcon: NSImage {
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }
}

private extension View {
    func orbitCard(border: Color) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(border))
    }
}
