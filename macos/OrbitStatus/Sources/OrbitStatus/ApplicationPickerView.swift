import Combine
import OrbitConnectPolicy
import SwiftUI

struct ApplicationPickerView: View {
    @ObservedObject var control: EgressControlCoordinator
    let close: () -> Void

    @State private var applications: [InstalledApplication] = []
    @State private var selectedIdentifiers: Set<String> = []
    @State private var expandedIdentifiers: Set<String> = []
    @State private var search = ""
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(
        control: EgressControlCoordinator,
        initialApplications: [InstalledApplication] = [],
        initialExpandedIdentifiers: Set<String> = [],
        initialSearch: String = "",
        close: @escaping () -> Void
    ) {
        self.control = control
        self.close = close
        _applications = State(initialValue: initialApplications)
        _expandedIdentifiers = State(initialValue: initialExpandedIdentifiers)
        _search = State(initialValue: initialSearch)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 14) {
                searchField
                observationNotice
                applicationsList
                footer
            }
            .padding(20)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 640)
        .background(OrbitConnectTheme.canvas)
        .onAppear {
            control.setTrafficDiscoveryEnabled(true)
            reload()
        }
        .onDisappear {
            control.setTrafficDiscoveryEnabled(false)
        }
        .onReceive(refresh) { _ in
            control.refreshFilterState()
            reload()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(OrbitConnectTheme.accent)
                .frame(width: 44, height: 44)
                .background(OrbitConnectTheme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Выбор приложений")
                    .font(.system(size: 22, weight: .semibold))
                Text("Connect наблюдает только адреса соединений, пока это окно открыто")
                    .font(OrbitConnectTheme.compactFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(OrbitConnectTheme.card, in: Circle())
            .overlay(Circle().stroke(OrbitConnectTheme.border))
        }
        .padding(20)
        .background(OrbitConnectTheme.card)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Название или идентификатор приложения", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OrbitConnectTheme.border))
    }

    private var observationNotice: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Наблюдение включено")
                    .font(OrbitConnectTheme.compactFont.weight(.semibold))
                Text("Откройте нужное приложение. Его последние адреса появятся в раскрываемой строке, содержимое трафика не читается.")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var applicationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredApplications.isEmpty {
                    Text("Подходящие приложения не найдены")
                        .font(OrbitConnectTheme.compactFont)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(filteredApplications) { application in
                        applicationRow(application)
                        if application.id != filteredApplications.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(OrbitConnectTheme.border))
    }

    private func applicationRow(_ application: InstalledApplication) -> some View {
        let applicationEvents = events(for: application.bundleIdentifier)
        let isConfigured = control.configuration.applications.contains {
            $0.bundleIdentifier == application.bundleIdentifier
        }

        let isSelected = selectedIdentifiers.contains(application.bundleIdentifier)
        let isExpanded = expandedIdentifiers.contains(application.id)

        return VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: application.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                    Image(systemName: isSelected || isConfigured ? "checkmark" : "plus")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(
                                isSelected || isConfigured
                                    ? Color.white
                                    : OrbitConnectTheme.accent
                            )
                            .frame(width: 14, height: 14)
                            .background(
                                isSelected || isConfigured
                                    ? OrbitConnectTheme.accent
                                    : OrbitConnectTheme.card,
                                in: Circle()
                            )
                            .overlay(Circle().stroke(OrbitConnectTheme.card, lineWidth: 2))
                            .offset(x: 3, y: 3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(application.displayName)
                            .font(OrbitConnectTheme.bodyFont.weight(.medium))
                            .foregroundStyle(.primary)
                        if isConfigured {
                            Text("Уже настроено")
                                .font(OrbitConnectTheme.captionFont)
                                .foregroundStyle(OrbitConnectTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(OrbitConnectTheme.accent.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(application.bundleIdentifier)
                        .font(OrbitConnectTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        setExpanded(!isExpanded, applicationID: application.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                        Text("\(applicationEvents.count)")
                            .font(OrbitConnectTheme.captionFont.monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(OrbitConnectTheme.canvas, in: Capsule())
                    .overlay(Capsule().stroke(OrbitConnectTheme.border))
                }
                .buttonStyle(.plain)
                .help("Показать сетевую активность")
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSelection(application.bundleIdentifier, configured: isConfigured)
            }

            if isExpanded {
                activityPanel(applicationEvents)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 11)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            isSelected ? OrbitConnectTheme.accent.opacity(0.07) : Color.clear
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(OrbitConnectTheme.accent)
                    .frame(width: 3)
            }
        }
    }

    private func activityPanel(_ events: [EgressFlowEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сетевая активность")
                .font(OrbitConnectTheme.captionFont.weight(.semibold))
                .foregroundStyle(.secondary)

            if events.isEmpty {
                Text("За время наблюдения соединений не обнаружено. Оставьте приложение открытым, не закрывая это окно.")
                    .font(OrbitConnectTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(events.prefix(8)) { event in
                    activityEventRow(event)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitConnectTheme.canvas, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(OrbitConnectTheme.border))
    }

    private func activityEventRow(_ event: EgressFlowEvent) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                activityStatus(event)
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
                    activityStatus(event)
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

    private func activityStatus(_ event: EgressFlowEvent) -> some View {
        Circle()
            .fill(event.allowed ? Color.green : Color.red)
            .frame(width: 6, height: 6)
    }

    private var footer: some View {
        HStack {
            Text(selectedIdentifiers.isEmpty
                ? "Выберите одно или несколько приложений"
                : "Выбрано: \(selectedIdentifiers.count)")
                .font(OrbitConnectTheme.captionFont)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Отмена", action: close)
                .buttonStyle(.bordered)
            Button("Добавить") {
                addSelectedApplications()
            }
            .buttonStyle(.borderedProminent)
            .tint(OrbitConnectTheme.accent)
            .disabled(selectedIdentifiers.isEmpty)
        }
    }

    private var filteredApplications: [InstalledApplication] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return applications }
        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private func events(for bundleIdentifier: String) -> [EgressFlowEvent] {
        control.flowEvents.filter {
            $0.applicationIdentifier == bundleIdentifier
                || $0.applicationIdentifier.hasPrefix(bundleIdentifier + ".")
        }
    }

    private func reload() {
        applications = ApplicationCatalog.load(
            configuredApplications: control.configuration.applications,
            observedApplicationIdentifiers: control.flowEvents.map(\.applicationIdentifier)
        )
    }

    private func toggleSelection(_ identifier: String, configured: Bool) {
        guard !configured else { return }
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }

    private func setExpanded(_ expanded: Bool, applicationID: String) {
        if expanded {
            expandedIdentifiers.insert(applicationID)
        } else {
            expandedIdentifiers.remove(applicationID)
        }
    }

    private func addSelectedApplications() {
        for application in applications where selectedIdentifiers.contains(application.bundleIdentifier) {
            control.addApplication(
                bundleIdentifier: application.bundleIdentifier,
                displayName: application.displayName,
                applicationPath: application.url?.path
            )
        }
        close()
    }
}
