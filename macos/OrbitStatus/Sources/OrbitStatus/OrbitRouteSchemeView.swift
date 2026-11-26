import SwiftUI

struct OrbitRouteSchemeNode: Identifiable {
    let id: String
    let title: String
    let details: [String]
    let icon: String
    let tint: Color
}

struct OrbitRouteSchemeView: View {
    let nodes: [OrbitRouteSchemeNode]
    let isBlocked: Bool
    var compact = false

    private let panel = Color(red: 0.018, green: 0.035, blue: 0.094)
    private let panelInk = Color(red: 0.91, green: 0.94, blue: 0.98)
    private let panelMuted = Color(red: 0.55, green: 0.60, blue: 0.70)
    private let panelBorder = Color.white.opacity(0.14)

    private var routeTint: Color {
        isBlocked ? .red : OrbitConnectTheme.accent
    }

    var body: some View {
        if compact {
            compactRouteContent
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalRouteContent
                    .frame(minWidth: horizontalMinimumWidth)
                verticalRouteContent(dense: false)
            }
        }
    }

    private var compactRouteContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("СХЕМА МАРШРУТА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(panelMuted)
                    .tracking(1.35)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    Circle()
                        .fill(routeTint)
                        .frame(width: 7, height: 7)
                    Text(isBlocked ? "Остановлен" : "\(nodes.count + 2) узла")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(panelInk.opacity(0.78))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.2), in: Capsule())
                .overlay(Capsule().stroke(panelBorder))
            }

            HStack(spacing: 0) {
                compactEndpoint(icon: "laptopcomputer", title: "Устройство")
                compactConnector

                if nodes.isEmpty {
                    compactEmptyNode
                    compactConnector
                } else {
                    ForEach(nodes) { node in
                        compactNode(node)
                        compactConnector
                    }
                }

                compactEndpoint(icon: "globe", title: "Интернет")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .routePanel(
            panel: panel,
            routeTint: routeTint,
            border: panelBorder,
            cornerRadius: 16
        )
    }

    private func compactEndpoint(icon: String, title: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(routeTint.opacity(0.12))
                Circle().stroke(routeTint.opacity(0.52), lineWidth: 2)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(routeTint)
            }
            .frame(width: 40, height: 40)
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(panelMuted)
                .lineLimit(1)
        }
        .frame(width: 48)
    }

    private func compactNode(_ node: OrbitRouteSchemeNode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: node.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(node.tint)
                    .frame(width: 24, height: 24)
                    .background(node.tint.opacity(0.22), in: Circle())
                Text(node.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(panelInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            Text(nodeSubtitle(node))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(panelMuted)
                .lineLimit(1)
            if let detail = node.details.first {
                Text(detail)
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(panelInk.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(9)
        .frame(minWidth: 70, maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(node.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(node.tint.opacity(0.55), lineWidth: 1)
        }
    }

    private var compactEmptyNode: some View {
        Text("Маршрут не определён")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(panelMuted)
            .frame(minWidth: 70, maxWidth: .infinity, minHeight: 78)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelBorder))
    }

    private var compactConnector: some View {
        ZStack {
            Rectangle()
                .fill(routeTint.opacity(0.5))
                .frame(height: 1)
            Image(systemName: isBlocked ? "xmark" : "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(routeTint)
                .frame(width: 16, height: 16)
                .background(panel, in: Circle())
                .overlay(Circle().stroke(routeTint.opacity(0.52)))
        }
        .frame(width: 18)
    }

    private var horizontalMinimumWidth: CGFloat {
        let nodeCount = max(nodes.count, 1)
        // The settings window has a sidebar, so its useful width is smaller
        // than the window profile used by screenshot tests. Keep the wide
        // route close to Orbit's proportions without forcing the mobile
        // layout while two route nodes still fit comfortably.
        return 286 + CGFloat(nodeCount) * 268
    }

    private var horizontalRouteContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            routeHeader(dense: false)

            HStack(spacing: 0) {
                endpoint(icon: "laptopcomputer", title: "Устройство", dense: false)
                horizontalConnector

                if nodes.isEmpty {
                    emptyRouteTile(
                        dense: false,
                        fillsWidth: false,
                        horizontal: true
                    )
                    horizontalConnector
                } else {
                    ForEach(nodes) { node in
                        routeTile(
                            node: node,
                            dense: false,
                            fillsWidth: false,
                            horizontal: true
                        )
                        horizontalConnector
                    }
                }

                endpoint(icon: "globe", title: "Интернет", dense: false)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .routePanel(
            panel: panel,
            routeTint: routeTint,
            border: panelBorder,
            cornerRadius: 20
        )
    }

    private func verticalRouteContent(dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: dense ? 16 : 22) {
            routeHeader(dense: dense)

            VStack(spacing: 0) {
                endpoint(icon: "laptopcomputer", title: "Устройство", dense: dense)
                verticalConnector(dense: dense)

                if nodes.isEmpty {
                    emptyRouteTile(
                        dense: dense,
                        fillsWidth: true,
                        horizontal: false
                    )
                    verticalConnector(dense: dense)
                } else {
                    ForEach(nodes) { node in
                        routeTile(
                            node: node,
                            dense: dense,
                            fillsWidth: true,
                            horizontal: false
                        )
                        verticalConnector(dense: dense)
                    }
                }

                endpoint(icon: "globe", title: "Интернет", dense: dense)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(dense ? 14 : 22)
        .routePanel(
            panel: panel,
            routeTint: routeTint,
            border: panelBorder,
            cornerRadius: dense ? 16 : 20
        )
    }

    private func routeHeader(dense: Bool) -> some View {
        Group {
            if dense {
                VStack(alignment: .leading, spacing: 10) {
                    routeHeading(dense: true)
                    statusCapsule(dense: true)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        routeHeading(dense: false)
                        Spacer(minLength: 16)
                        statusCapsule(dense: false)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        routeHeading(dense: false)
                        statusCapsule(dense: false)
                    }
                }
            }
        }
    }

    private func routeHeading(dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("СХЕМА МАРШРУТА")
                .font(.system(size: dense ? 11 : 12, weight: .bold))
                .foregroundStyle(panelMuted)
                .tracking(1.5)
            Text(
                isBlocked
                    ? "Трафик безопасно остановлен"
                    : "Трафик последовательно проходит все узлы"
            )
            .font(.system(size: dense ? 13 : 15, weight: .medium))
            .foregroundStyle(panelInk.opacity(0.76))
            .lineLimit(2)
        }
    }

    private func statusCapsule(dense: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(routeTint)
                .frame(width: 8, height: 8)
                .shadow(color: routeTint.opacity(0.8), radius: 5)
            Text(
                isBlocked
                    ? "Маршрут остановлен"
                    : "Активный маршрут · \(nodes.count + 2) узла"
            )
            .font(.system(size: dense ? 11 : 12, weight: .semibold))
            .foregroundStyle(panelInk.opacity(0.8))
        }
        .padding(.horizontal, dense ? 11 : 13)
        .padding(.vertical, dense ? 7 : 8)
        .background(Color.black.opacity(0.2), in: Capsule())
        .overlay(Capsule().stroke(panelBorder))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func routeTile(
        node: OrbitRouteSchemeNode,
        dense: Bool,
        fillsWidth: Bool,
        horizontal: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: dense ? 10 : 14) {
            if horizontal {
                HStack(alignment: .top, spacing: 11) {
                    nodeIcon(node, dense: dense)
                    Spacer(minLength: 8)
                    nodeStateBadge(node)
                }
                nodeHeading(node, dense: dense, lineLimit: 1)
            } else {
                HStack(alignment: .top, spacing: 11) {
                    nodeIcon(node, dense: dense)
                    nodeHeading(node, dense: dense, lineLimit: 2)
                    Spacer(minLength: 4)
                    nodeStateBadge(node)
                }
            }

            VStack(alignment: .leading, spacing: dense ? 6 : 8) {
                ForEach(node.details.prefix(3), id: \.self) { detail in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(node.tint)
                            .frame(width: 5, height: 5)
                        Text(detail)
                            .font(.system(size: dense ? 10 : 11).monospacedDigit())
                            .foregroundStyle(panelInk.opacity(0.74))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }
                }
            }
            .padding(dense ? 9 : 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelBorder))
        }
        .padding(dense ? 12 : 15)
        .frame(
            minWidth: horizontal ? 268 : nil,
            maxWidth: horizontal ? 268 : (fillsWidth ? 620 : 330),
            minHeight: dense ? 128 : 154,
            alignment: .leading
        )
        .background(node.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(node.tint.opacity(0.55), lineWidth: 1.2)
        }
    }

    private func nodeIcon(
        _ node: OrbitRouteSchemeNode,
        dense: Bool
    ) -> some View {
        Image(systemName: node.icon)
            .font(.system(size: dense ? 17 : 19, weight: .semibold))
            .foregroundStyle(node.tint)
            .frame(width: dense ? 38 : 44, height: dense ? 38 : 44)
            .background(node.tint.opacity(0.22), in: Circle())
            .overlay(Circle().stroke(node.tint.opacity(0.45)))
    }

    private func nodeHeading(
        _ node: OrbitRouteSchemeNode,
        dense: Bool,
        lineLimit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.title)
                .font(.system(size: dense ? 14 : 16, weight: .semibold))
                .foregroundStyle(panelInk)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.72)
            Text(nodeSubtitle(node))
                .font(.system(size: dense ? 10 : 11))
                .foregroundStyle(panelMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nodeStateBadge(_ node: OrbitRouteSchemeNode) -> some View {
        Text(isBlocked ? "СТОП" : "ДОВЕРЕН")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(isBlocked ? Color.red : node.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(node.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(node.tint.opacity(0.32)))
    }

    private func nodeSubtitle(_ node: OrbitRouteSchemeNode) -> String {
        if node.id.contains("static") {
            return "Статический выход"
        }
        if node.id.contains("direct") {
            return "Прямое подключение"
        }
        return "Основной выход"
    }

    private func emptyRouteTile(
        dense: Bool,
        fillsWidth: Bool,
        horizontal: Bool
    ) -> some View {
        Text("Маршрут не определён")
            .font(.system(size: dense ? 13 : 14, weight: .medium))
            .foregroundStyle(panelMuted)
            .frame(
                minWidth: horizontal ? 268 : nil,
                maxWidth: horizontal ? 268 : (fillsWidth ? 620 : 330),
                minHeight: dense ? 128 : 154
            )
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(panelBorder))
    }

    private func endpoint(icon: String, title: String, dense: Bool) -> some View {
        VStack(spacing: dense ? 6 : 9) {
            ZStack {
                Circle().fill(routeTint.opacity(0.12))
                Circle().stroke(routeTint.opacity(0.52), lineWidth: dense ? 2.5 : 3)
                Circle()
                    .stroke(
                        routeTint.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .padding(dense ? 7 : 9)
                Image(systemName: icon)
                    .font(.system(size: dense ? 22 : 27, weight: .medium))
                    .foregroundStyle(routeTint)
            }
            .frame(width: dense ? 68 : 82, height: dense ? 68 : 82)

            Text(title)
                .font(.system(size: dense ? 10 : 11, weight: .medium))
                .foregroundStyle(panelMuted)
                .lineLimit(1)
        }
        .frame(width: dense ? 80 : 92)
    }

    private var horizontalConnector: some View {
        ZStack {
            Rectangle()
                .fill(routeTint.opacity(0.5))
                .frame(height: 1)
            connectorIcon(systemName: isBlocked ? "xmark" : "arrow.right")
        }
        .frame(minWidth: 22, maxWidth: 32)
    }

    private func verticalConnector(dense: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(routeTint.opacity(0.5))
                .frame(width: 1)
            connectorIcon(systemName: isBlocked ? "xmark" : "arrow.down")
        }
        .frame(width: 28, height: dense ? 36 : 44)
    }

    private func connectorIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(routeTint)
            .frame(width: 24, height: 24)
            .background(panel, in: Circle())
            .overlay(Circle().stroke(routeTint.opacity(0.52)))
    }
}

private extension View {
    func routePanel(
        panel: Color,
        routeTint: Color,
        border: Color,
        cornerRadius: CGFloat
    ) -> some View {
        background {
            ZStack {
                panel
                RadialGradient(
                    colors: [routeTint.opacity(0.11), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: 420
                )
                OrbitRouteGrid()
                    .stroke(Color.white.opacity(0.045), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(border, lineWidth: 1)
        }
    }
}

private struct OrbitRouteGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 28

        for x in stride(from: CGFloat.zero, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for y in stride(from: CGFloat.zero, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}
