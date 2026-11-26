import AppKit
import Foundation
import OrbitConnectPolicy

@MainActor
final class EgressControlCoordinator: ObservableObject {
    enum FilterState: Equatable {
        case disabled
        case requiresInstallation
        case enabling
        case enabled
        case failed(String)
    }

    @Published private(set) var configuration: EgressControlConfiguration
    @Published private(set) var snapshot: EgressTrustSnapshot
    @Published private(set) var filterState: FilterState = .disabled
    @Published private(set) var flowEvents: [EgressFlowEvent] = []

    private let store: EgressControlStore
    private let systemController: EgressControlSystemController

    init(
        store: EgressControlStore = EgressControlStore(),
        systemController: EgressControlSystemController = EgressControlSystemController()
    ) {
        self.store = store
        self.systemController = systemController
        configuration = store.loadConfiguration().normalized
        snapshot = store.loadSnapshot()
        flowEvents = store.loadFlowEvents()
        refreshFilterState()
    }

    var isEnabled: Bool { configuration.isEnabled }

    var hasSystemControlProblem: Bool {
        if case .failed = filterState { return true }
        guard configuration.isEnabled else { return false }
        switch filterState {
        case .enabled, .enabling:
            return false
        case .disabled, .requiresInstallation, .failed:
            return true
        }
    }

    var statusTitle: String {
        if case .failed = filterState { return "Сетевой фильтр не запущен" }
        guard configuration.isEnabled else { return "Контроль выключен" }
        switch filterState {
        case .requiresInstallation:
            return "Сетевой фильтр не установлен"
        case .disabled:
            return "Сетевой фильтр выключен"
        case .enabling:
            return "Включаем системный контроль"
        case .failed:
            return "Сетевой фильтр не запущен"
        case .enabled:
            break
        }
        switch snapshot.state {
        case .trusted: return "Доверенный выход подтверждён"
        case .verifying: return "Проверяем доверенный выход"
        case .blocked: return "Защищённый трафик остановлен"
        case .disabled: return "Контроль выключен"
        }
    }

    var statusDetail: String {
        if case let .failed(message) = filterState { return message }
        if configuration.isEnabled {
            switch filterState {
            case .requiresInstallation:
                return "Установите подписанный системный компонент Orbit Connect. До этого строгий контроль не действует."
            case .disabled:
                return "Разрешите сетевой фильтр Orbit Connect в настройках macOS."
            case .enabling:
                return "Ожидаем подтверждение macOS. До завершения выбранный трафик ещё не защищён."
            case .failed:
                break
            case .enabled:
                break
            }
        }
        if !snapshot.reason.isEmpty { return snapshot.reason }
        switch snapshot.state {
        case .trusted:
            return snapshot.finalAddress.map { "Конечный адрес: \($0)" }
                ?? "Маршрут подтверждён Orbit"
        case .verifying:
            return "До подтверждения Orbit выбранные соединения не выпускаются в сеть."
        case .blocked:
            return "Orbit не подтвердил заявленный статический выход."
        case .disabled:
            return "Выбранные приложения и адреса работают без дополнительной блокировки."
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard !configuration.expectedFinalAddresses.isEmpty else {
                filterState = .failed(
                    "Сначала включите и подтвердите статический выход в домашнем Orbit"
                )
                return
            }
            guard !configuration.applications.isEmpty || !configuration.destinations.isEmpty else {
                filterState = .failed("Выберите хотя бы одно приложение или адрес")
                return
            }
            configuration.isEnabled = true
            persistConfiguration()
            invalidate(reason: "Ожидаем подтверждение Orbit")
            enableSystemFilter()
        } else {
            disableSystemControl()
        }
    }

    func disableForApplicationTermination(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        disableSystemControl(completion: completion)
    }

    func addApplication(at url: URL) {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !identifier.isEmpty
        else {
            filterState = .failed("Не удалось определить приложение")
            return
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        addApplication(bundleIdentifier: identifier, displayName: name)
    }

    func addApplication(bundleIdentifier: String, displayName: String) {
        guard !bundleIdentifier.isEmpty else { return }
        configuration.applications.append(
            ProtectedApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName
            )
        )
        persistConfiguration()
    }

    func setTrafficDiscoveryEnabled(_ enabled: Bool) {
        store.setTrafficDiscoveryEnabled(enabled)
        if !enabled {
            flowEvents = store.loadFlowEvents()
        }
    }

    func removeApplication(id: UUID) {
        configuration.applications.removeAll { $0.id == id }
        persistConfiguration()
    }

    func setRouteMode(_ routeMode: ApplicationRouteMode, applicationID: UUID) {
        guard let index = configuration.applications.firstIndex(where: {
            $0.id == applicationID
        }) else { return }
        configuration.applications[index].routeMode = routeMode
        persistConfiguration()
    }

    func addDestination(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        configuration.destinations.append(ProtectedDestination(value: value))
        persistConfiguration()
    }

    func removeDestination(id: UUID) {
        configuration.destinations.removeAll { $0.id == id }
        persistConfiguration()
    }

    func update(status: ClientStatus?) {
        synchronizeTrustedFinalAddress(from: status)
        guard configuration.isEnabled else {
            if snapshot.state != .disabled {
                snapshot = .disabled
                try? store.saveSnapshot(snapshot)
            }
            return
        }
        // Outside the home network Orbit is expected to be unavailable. The
        // independent public-address probe renews or rejects trust there;
        // absence of a LAN status must not overwrite a successful probe.
        guard let status else { return }
        guard status.usingOrbit, !status.macChanged else {
            invalidate(reason: "Текущая сеть не подтверждена домашним Orbit")
            return
        }
        guard status.staticExitEnabled == true else {
            invalidate(reason: "Статический выход домашнего Orbit выключен")
            return
        }
        guard status.staticExitBlocked != true, status.trafficBlocked != true else {
            invalidate(reason: status.staticExitError ?? "Статический выход недоступен")
            return
        }
        guard let finalAddress = status.finalIP,
              configuration.expectedFinalAddresses.first
                  == normalizedAddress(finalAddress)
        else {
            invalidate(reason: "Конечный адрес не совпадает с доверенным")
            return
        }
        snapshot = EgressTrustSnapshot(
            state: .trusted,
            finalAddress: finalAddress,
            confirmedAt: Date(),
            reason: "Маршрут подтверждён домашним Orbit"
        )
        try? store.saveSnapshot(snapshot)
    }

    func update(observedFinalAddress: String) {
        guard configuration.isEnabled,
              let expectedAddress = configuration.expectedFinalAddresses.first
        else { return }

        let observedAddress = normalizedAddress(observedFinalAddress)
        guard observedAddress == expectedAddress else {
            invalidate(reason: "Текущий конечный адрес не совпадает с домашним Orbit")
            return
        }

        snapshot = EgressTrustSnapshot(
            state: .trusted,
            finalAddress: observedAddress,
            confirmedAt: Date(),
            reason: "Конечный адрес совпадает с домашним Orbit"
        )
        try? store.saveSnapshot(snapshot)
    }

    func invalidate(reason: String) {
        guard configuration.isEnabled else { return }
        snapshot = EgressTrustSnapshot(state: .blocked, reason: reason)
        try? store.saveSnapshot(snapshot)
    }

    func refreshFilterState() {
        systemController.status { [weak self] state in
            Task { @MainActor in self?.filterState = state }
        }
        flowEvents = store.loadFlowEvents()
    }

    func loadDevelopmentDemo(force: Bool = false) {
        guard force || OrbitRuntime.isDemo else { return }
        configuration = EgressControlConfiguration(
            isEnabled: true,
            expectedFinalAddresses: ["203.0.113.42"],
            applications: [
                ProtectedApplication(
                    bundleIdentifier: "ru.yandex.desktop.telemost",
                    displayName: "Телемост",
                    routeMode: .direct
                ),
                ProtectedApplication(
                    bundleIdentifier: "com.openai.codex",
                    displayName: "Codex",
                    routeMode: .trustedExit
                ),
                ProtectedApplication(
                    bundleIdentifier: "com.anthropic.claudefordesktop",
                    displayName: "Claude",
                    routeMode: .trustedExit
                ),
            ],
            destinations: [
                ProtectedDestination(value: "service.example"),
            ]
        )
        snapshot = EgressTrustSnapshot(
            state: .trusted,
            finalAddress: "203.0.113.42",
            confirmedAt: Date(),
            reason: "Демонстрационный доверенный выход подтверждён"
        )
        filterState = .enabled
        flowEvents = [
            EgressFlowEvent(
                applicationIdentifier: "ru.yandex.desktop.telemost",
                remoteHost: "conference.example",
                routeMode: .direct,
                allowed: true,
                reason: "Разрешено прямым правилом",
                observedAt: Date().addingTimeInterval(-4)
            ),
            EgressFlowEvent(
                applicationIdentifier: "com.openai.codex",
                remoteHost: "api.example",
                routeMode: .trustedExit,
                allowed: true,
                reason: "Доверенный выход подтверждён",
                observedAt: Date().addingTimeInterval(-9)
            ),
        ]
    }

    private func persistConfiguration() {
        configuration = configuration.normalized
        do {
            try store.saveConfiguration(configuration)
        } catch {
            filterState = .failed("Не удалось сохранить настройки контроля")
        }
    }

    private func disableSystemControl(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        configuration.isEnabled = false
        persistConfiguration()
        snapshot = .disabled
        try? store.saveSnapshot(snapshot)
        systemController.disable { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.filterState = .disabled
                case let .failure(error):
                    self?.filterState = .failed(error.localizedDescription)
                }
                completion?(result)
            }
        }
    }

    private func synchronizeTrustedFinalAddress(from status: ClientStatus?) {
        guard let status,
              status.usingOrbit,
              !status.macChanged,
              status.staticExitEnabled == true,
              status.staticExitBlocked != true,
              status.trafficBlocked != true,
              let finalAddress = status.finalIP
        else { return }

        let trustedAddress = normalizedAddress(finalAddress)
        guard !trustedAddress.isEmpty,
              configuration.expectedFinalAddresses != [trustedAddress]
        else { return }

        configuration.expectedFinalAddresses = [trustedAddress]
        persistConfiguration()
    }

    private func normalizedAddress(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func enableSystemFilter() {
        filterState = .enabling
        systemController.enable { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success: self?.filterState = .enabled
                case let .failure(error):
                    guard let self else { return }
                    self.configuration.isEnabled = false
                    self.persistConfiguration()
                    self.snapshot = .disabled
                    try? self.store.saveSnapshot(self.snapshot)
                    self.filterState = .failed(error.localizedDescription)
                }
            }
        }
    }
}
