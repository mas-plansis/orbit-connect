import Combine
import OrbitConnectPolicy
import SwiftUI

struct EgressControlSettingsView: View {
    @ObservedObject var model: OrbitStatusModel

    @State private var selectedSection: SettingsSection = .control
    @State private var destination = ""
    @State private var autostartEnabled = AutostartManager.isEnabled
    @State private var autostartError = ""
    @State private var isApplicationPickerPresented = false
    @AppStorage(
        OrbitAppearanceMode.storageKey,
        store: OrbitRuntime.defaults
    ) private var appearanceModeRawValue = OrbitAppearanceMode.system.rawValue
    private let initiallyExpandedApplicationIDs: Set<UUID>
    private let flowRefresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var control: EgressControlCoordinator { model.egressControl }

    init(
        model: OrbitStatusModel,
        initialSection: SettingsSection = .control,
        initiallyExpandedApplicationIDs: Set<UUID> = []
    ) {
        self.model = model
        self.initiallyExpandedApplicationIDs = initiallyExpandedApplicationIDs
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                let compactSidebar = geometry.size.width < 860

                HStack(spacing: 0) {
                    sidebar(compact: compactSidebar)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            sectionHeader
                            selectedSectionContent
                        }
                        .padding(22)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 620, idealHeight: 720)
        .background(OrbitConnectTheme.canvas)
        .orbitAppearance()
        .onReceive(flowRefresh) { _ in control.refreshFilterState() }
        .sheet(isPresented: $isApplicationPickerPresented) {
            ApplicationPickerView(control: control) {
                isApplicationPickerPresented = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(OrbitConnectTheme.accent)
                .frame(width: 44, height: 44)
                .background(OrbitConnectTheme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    OrbitRuntime.isDevelopment
                        ? "Настройки Orbit Connect Dev"
                        : "Настройки Orbit Connect"
                )
                    .font(.system(size: 22, weight: .semibold))
                Text("Безопасность, маршрутизация и поведение Connect")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(OrbitConnectTheme.card)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func sidebar(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 28 : 24) {
                navigationGroup(
                    "Контроль",
                    sections: [.control],
                    compact: compact
                )
                navigationGroup(
                    "Connect",
                    sections: [.application],
                    compact: compact
                )
                Spacer(minLength: 12)
            }
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, 24)
        }
        .frame(width: compact ? 72 : 276)
        .frame(maxHeight: .infinity)
        .background(OrbitConnectTheme.sidebar)
        .animation(.easeInOut(duration: 0.18), value: compact)
    }

    private func navigationGroup(
        _ title: String,
        sections: [SettingsSection],
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .tracking(1.6)
                    .padding(.horizontal, 12)
            }

            VStack(spacing: 4) {
                ForEach(sections) { section in
                    navigationItem(section, compact: compact)
                }
            }
        }
    }

    private func navigationItem(
        _ section: SettingsSection,
        compact: Bool
    ) -> some View {
        let isSelected = selectedSection == section

        return Button { selectedSection = section } label: {
            HStack(spacing: compact ? 0 : 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? OrbitConnectTheme.accent : .secondary)
                    .frame(width: compact ? 44 : 20, height: compact ? 44 : nil)
                if !compact {
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, compact ? 0 : 12)
            .frame(
                maxWidth: .infinity,
                minHeight: 44,
                alignment: compact ? .center : .leading
            )
            .background(
                isSelected ? OrbitConnectTheme.card : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(section.title)
        .shadow(
            color: isSelected ? Color.black.opacity(0.07) : .clear,
            radius: 11,
            y: 5
        )
    }

    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectedSection.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(OrbitConnectTheme.accent)
                .frame(width: 40, height: 40)
                .background(OrbitConnectTheme.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection.title)
                    .font(.system(size: 21, weight: .semibold))
                Text(selectedSection.subtitle)
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .control: controlSection
        case .application: applicationSection
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            protectionCard
            routeCard
        }
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Label("Только через доверенный выход", systemImage: "lock.shield")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { control.isEnabled },
                        set: { control.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OrbitConnectTheme.accent)
            }
            Text("Весь внешний трафик этого Mac разрешается только после подтверждения доверенного конечного публичного IP. При смене сети трафик сначала блокируется, затем Connect выполняет новую проверку.")
                .font(OrbitConnectTheme.compactFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(OrbitConnectTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(control.systemAgentTitle)
                        .font(OrbitConnectTheme.compactFont.weight(.semibold))
                    Text("Внутренний агент Orbit Connect управляет только собственным PF-якорем. Отдельного приложения и интерфейса нет.")
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                systemAgentAction
            }
            .padding(12)
            .background(OrbitConnectTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(control.statusTitle).font(OrbitConnectTheme.bodyFont)
                    Text(control.statusDetail)
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .settingsCard()
    }

    @ViewBuilder
    private var systemAgentAction: some View {
        switch control.filterState {
        case .requiresInstallation:
            Button("Установить") { control.promptToInstallSystemAgent() }
                .buttonStyle(.borderedProminent)
                .tint(OrbitConnectTheme.accent)
        case .disabled, .failed:
            if case .failed = control.filterState {
                Button("Повторить") { control.retrySystemAgent() }
                    .buttonStyle(.bordered)
            } else {
                Label("Готов", systemImage: "checkmark.circle.fill")
                    .font(OrbitConnectTheme.captionFont.weight(.semibold))
                    .foregroundStyle(.green)
            }
        case .installing:
            ProgressView().controlSize(.small)
        case .enabling, .enabled:
            EmptyView()
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            OrbitRouteSchemeView(
                nodes: controlRouteNodes,
                isBlocked: control.snapshot.state == .blocked
            )
            Text("При смене сети схема считается недоверенной, пока Connect не подтвердит тот же конечный адрес.")
                .font(OrbitConnectTheme.captionFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlRouteNodes: [OrbitRouteSchemeNode] {
        let routeSteps = model.status?.routeSteps?.filter {
            $0.role != "device" && $0.role != "internet"
        } ?? []

        if !routeSteps.isEmpty {
            return routeSteps.enumerated().map { index, step in
                let server = step.server?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
                let routeProtocol = step.protocol?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
                let ip = step.ip?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
                var details: [String] = []
                if !routeProtocol.isEmpty {
                    details.append("Протокол  \(routeProtocol)")
                }
                if !ip.isEmpty {
                    details.append(
                        step.role == "static_exit"
                            ? "Финальный IP  \(ip)"
                            : "IP выхода шага  \(ip)"
                    )
                }
                if details.isEmpty {
                    details.append(step.label)
                }

                return OrbitRouteSchemeNode(
                    id: "\(step.role)-\(index)",
                    title: server.isEmpty ? step.label : server,
                    details: details,
                    icon: routeIcon(for: step.role),
                    tint: routeTint(for: step.role)
                )
            }
        }

        let finalAddress = control.configuration.expectedFinalAddresses.first
        return [
            OrbitRouteSchemeNode(
                id: "static-exit",
                title: finalAddress ?? "Статический выход",
                details: [
                    finalAddress.map { "Финальный IP  \($0)" }
                        ?? "Orbit ещё не передал конечный адрес",
                    control.snapshot.state == .blocked
                        ? "Состояние  Маршрут остановлен"
                        : "Состояние  Маршрут подтверждён",
                ],
                icon: "arrow.up.right.circle",
                tint: control.snapshot.state == .blocked
                    ? .red
                    : Color(red: 0.44, green: 0.40, blue: 0.72)
            ),
        ]
    }

    private func routeIcon(for role: String) -> String {
        switch role {
        case "primary": return "server.rack"
        case "static_exit": return "arrow.up.right.circle"
        case "blocked": return "hand.raised.fill"
        case "direct": return "arrow.right"
        default: return "circle"
        }
    }

    private func routeTint(for role: String) -> Color {
        switch role {
        case "static_exit": return Color(red: 0.44, green: 0.40, blue: 0.72)
        case "direct": return .green
        case "blocked": return .red
        default: return OrbitConnectTheme.accent
        }
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("Настроено: \(control.configuration.applications.count)")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Добавить приложение") { isApplicationPickerPresented = true }
                    .buttonStyle(.borderedProminent)
                    .tint(OrbitConnectTheme.accent)
            }

            if control.configuration.applications.isEmpty {
                emptyRow("Добавьте приложение и выберите для него способ подключения.")
                    .settingsCard()
            } else {
                VStack(spacing: 0) {
                    applicationTableHeader
                    ForEach(Array(control.configuration.applications.enumerated()), id: \.element.id) { index, application in
                        if index > 0 { Divider().padding(.leading, 66) }
                        ApplicationRuleRow(
                            application: application,
                            events: events(for: application),
                            initiallyExpanded: initiallyExpandedApplicationIDs.contains(
                                application.id
                            ),
                            setRouteMode: {
                                control.setRouteMode($0, applicationID: application.id)
                            },
                            remove: { control.removeApplication(id: application.id) }
                        )
                    }
                }
                .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(OrbitConnectTheme.border))
            }
        }
    }

    private var applicationTableHeader: some View {
        HStack(spacing: 12) {
            Text("Приложение")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Подключение")
                .frame(width: 176, alignment: .leading)
            Color.clear.frame(width: 36)
        }
        .font(OrbitConnectTheme.captionFont.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(OrbitConnectTheme.canvas.opacity(0.58))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "globe.badge.chevron.backward")
                        .foregroundStyle(OrbitConnectTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(OrbitConnectTheme.accent.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Эталонный адрес выхода")
                            .font(OrbitConnectTheme.bodyFont.weight(.semibold))
                        Text(control.configuration.expectedFinalAddresses.first ?? "Orbit ещё не передал конечный адрес")
                            .font(OrbitConnectTheme.compactFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Получено из Orbit", systemImage: "lock.fill")
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(OrbitConnectTheme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(OrbitConnectTheme.accent.opacity(0.10), in: Capsule())
                }
                Text("Orbit передаёт Connect конечный адрес включённого статического выхода. Connect сравнивает с ним фактический адрес устройства. Изменить значение здесь нельзя.")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: 12) {
                Label("Адреса назначения", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 16, weight: .semibold))
                Text("Выбранные приложения могут обращаться к этим доменам и IP только после подтверждения конечного адреса Orbit. Это не прямые маршруты. Правила действуют только на этом Mac.")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)

                if control.configuration.destinations.isEmpty {
                    emptyRow("Локальных правил пока нет.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(control.configuration.destinations.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            destinationRow(item)
                        }
                    }
                    .background(OrbitConnectTheme.canvas, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(OrbitConnectTheme.border))
                }

                HStack(spacing: 8) {
                    TextField("example.com или 203.0.113.0/24", text: $destination)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDestination)
                    Button("Добавить правило", action: addDestination)
                        .buttonStyle(.bordered)
                }
                Text("Поддерживаются домены, маски вида *.example.com и IPv4-подсети в CIDR. Адреса из Orbit здесь не дублируются и не редактируются.")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            .settingsCard()
        }
    }

    private func destinationRow(_ item: ProtectedDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .foregroundStyle(OrbitConnectTheme.accent)
                .frame(width: 30, height: 30)
                .background(OrbitConnectTheme.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.value)
                    .font(OrbitConnectTheme.bodyFont.monospaced())
                    .lineLimit(1)
                Text("Локальное правило Connect, не изменяет Orbit")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("Только через Orbit", systemImage: "lock.shield")
                .font(OrbitConnectTheme.captionFont)
                .foregroundStyle(.secondary)
            Menu {
                Button("Удалить правило", role: .destructive) {
                    control.removeDestination(id: item.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(OrbitConnectTheme.card, in: Circle())
                    .overlay(Circle().stroke(OrbitConnectTheme.border))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var applicationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Оформление", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .semibold))
                Text("Используйте тему macOS или выберите постоянное оформление Connect.")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
                Picker("Тема", selection: $appearanceModeRawValue) {
                    ForEach(OrbitAppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Запускать при входе в систему", isOn: $autostartEnabled)
                    .toggleStyle(.switch)
                    .tint(OrbitConnectTheme.accent)
                    .onChange(of: autostartEnabled) { enabled in
                        do {
                            try AutostartManager.setEnabled(enabled)
                            autostartError = ""
                        } catch {
                            autostartError = "Не удалось изменить автозапуск. Проверьте системные разрешения."
                        }
                    }
                Text("При автозапуске Connect остаётся в строке меню и не открывает окно.")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
                if !autostartError.isEmpty {
                    Text(autostartError)
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.red)
                }
            }
            .settingsCard()
        }
    }

    private var statusColor: Color {
        if control.hasSystemControlProblem { return .red }
        switch control.snapshot.state {
        case .trusted: return .green
        case .blocked: return .red
        case .verifying: return .orange
        case .disabled: return .secondary
        }
    }

    private func events(for application: ProtectedApplication) -> [EgressFlowEvent] {
        control.flowEvents.filter {
            $0.applicationIdentifier == application.bundleIdentifier
                || $0.applicationIdentifier.hasPrefix(application.bundleIdentifier + ".")
        }
    }

    private func addDestination() {
        control.addDestination(destination)
        destination = ""
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(OrbitConnectTheme.compactFont)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitConnectTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
    }
}
enum SettingsSection: String, CaseIterable, Identifiable {
    case control
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control: return "Контроль выхода"
        case .application: return "Параметры Connect"
        }
    }

    var subtitle: String {
        switch self {
        case .control: return "Весь внешний трафик и доверенный конечный IP"
        case .application: return "Запуск и поведение приложения"
        }
    }

    var icon: String {
        switch self {
        case .control: return "lock.shield"
        case .application: return "gearshape"
        }
    }
}

private struct ApplicationRuleRow: View {
    let application: ProtectedApplication
    let events: [EgressFlowEvent]
    let setRouteMode: (ApplicationRouteMode) -> Void
    let remove: () -> Void
    @State private var isExpanded: Bool

    init(
        application: ProtectedApplication,
        events: [EgressFlowEvent],
        initiallyExpanded: Bool = false,
        setRouteMode: @escaping (ApplicationRouteMode) -> Void,
        remove: @escaping () -> Void
    ) {
        self.application = application
        self.events = events
        self.setRouteMode = setRouteMode
        self.remove = remove
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(
                    nsImage: ApplicationCatalog.icon(
                        for: application.bundleIdentifier,
                        displayName: application.displayName
                    )
                )
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName.isEmpty ? application.bundleIdentifier : application.displayName)
                        .font(OrbitConnectTheme.bodyFont.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(application.bundleIdentifier)
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                routeModeMenu
                Menu {
                    Button("Удалить правило", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(OrbitConnectTheme.canvas, in: Circle())
                        .overlay(Circle().stroke(OrbitConnectTheme.border))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 9)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(OrbitConnectTheme.accent)
                    Text("Соединения")
                        .font(OrbitConnectTheme.captionFont.weight(.semibold))
                    activitySummary
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 11)

            if isExpanded {
                activityPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 13)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var activitySummary: some View {
        if events.isEmpty {
            Text("0")
                .font(OrbitConnectTheme.captionFont)
                .foregroundStyle(.secondary)
        } else {
            Text("\(events.count)")
                .font(OrbitConnectTheme.captionFont.monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(OrbitConnectTheme.accent.opacity(0.10), in: Capsule())
        }
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if events.isEmpty {
                Text("За время наблюдения соединений не обнаружено")
                    .font(OrbitConnectTheme.captionFont.weight(.semibold))
                Text("Оставьте приложение открытым. Connect покажет адреса и результат применения правила, не читая содержимое трафика.")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(events.prefix(6)) { event in
                    applicationEventRow(event)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitConnectTheme.canvas, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(OrbitConnectTheme.border))
    }

    private func applicationEventRow(_ event: EgressFlowEvent) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                eventStatus(event)
                Text(event.remoteHost)
                    .font(OrbitConnectTheme.captionFont.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(event.reason)
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(event.observedAt, style: .time)
                    .font(OrbitConnectTheme.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    eventStatus(event)
                    Text(event.remoteHost)
                        .font(OrbitConnectTheme.captionFont.monospaced())
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(event.observedAt, style: .time)
                        .font(OrbitConnectTheme.captionFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(event.reason)
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func eventStatus(_ event: EgressFlowEvent) -> some View {
        Circle()
            .fill(event.allowed ? Color.green : Color.red)
            .frame(width: 6, height: 6)
    }

    private var routeModeMenu: some View {
        Menu {
            Button("Напрямую") { setRouteMode(.direct) }
            Button("Через доверенный выход") { setRouteMode(.trustedExit) }
            Button("Через Orbit SOCKS") { setRouteMode(.orbitSOCKS) }
                .disabled(true)
            Divider()
            Button("Блокировать", role: .destructive) { setRouteMode(.blocked) }
        } label: {
            Label(routeModeTitle, systemImage: routeModeIcon)
                .font(OrbitConnectTheme.captionFont)
                .foregroundStyle(routeModeTint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(routeModeTint.opacity(0.10), in: Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    private var routeModeTitle: String {
        switch application.routeMode {
        case .direct: return "Напрямую"
        case .trustedExit: return "Доверенный выход"
        case .orbitSOCKS: return "Orbit SOCKS"
        case .blocked: return "Блокировать"
        }
    }

    private var routeModeIcon: String {
        switch application.routeMode {
        case .direct: return "arrow.right"
        case .trustedExit: return "lock.shield"
        case .orbitSOCKS: return "network"
        case .blocked: return "hand.raised.fill"
        }
    }

    private var routeModeTint: Color {
        switch application.routeMode {
        case .direct: return .green
        case .trustedExit: return OrbitConnectTheme.accent
        case .orbitSOCKS: return .blue
        case .blocked: return .red
        }
    }
}

extension View {
    func settingsCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(OrbitConnectTheme.border))
    }
}
