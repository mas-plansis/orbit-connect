import AppKit
import Foundation
import OrbitConnectPolicy

@MainActor
final class EgressControlCoordinator: ObservableObject {
    enum FilterState: Equatable {
        case disabled
        case requiresInstallation
        case installing
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
    private var trustExpirationTask: Task<Void, Never>?
    private var reconcileInProgress = false
    private var reconcilePending = false
    private var installationPromptVisible = false

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
        schedulePersistedTrustExpiration()
        if configuration.isEnabled,
           !systemController.isInstalled,
           !OrbitRuntime.isDemo
        {
            DispatchQueue.main.async { [weak self] in
                self?.promptToInstallSystemAgent()
            }
        }
    }

    var isEnabled: Bool { configuration.isEnabled }

    var hasSystemControlProblem: Bool {
        if case .failed = filterState { return true }
        guard configuration.isEnabled else { return false }
        return filterState != .enabled && filterState != .enabling
    }

    var statusTitle: String {
        if case .failed = filterState { return "Системный контроль недоступен" }
        guard configuration.isEnabled else { return "Контроль выключен" }
        switch filterState {
        case .requiresInstallation: return "Нужен системный агент Orbit Connect"
        case .installing: return "Устанавливаем системный агент"
        case .enabling: return "Включаем строгий контроль"
        case .disabled: return "Системный агент выключен"
        case .failed: return "Системный контроль недоступен"
        case .enabled: break
        }
        switch snapshot.state {
        case .trusted: return "Доверенный выход подтверждён"
        case .verifying: return "Проверяем доверенный выход"
        case .blocked: return "Внешний трафик остановлен"
        case .disabled: return "Контроль выключен"
        }
    }

    var statusDetail: String {
        if case let .failed(message) = filterState { return message }
        if configuration.isEnabled {
            switch filterState {
            case .requiresInstallation:
                return "Установите внутренний агент Orbit Connect. Потребуется пароль администратора macOS."
            case .installing:
                return "macOS устанавливает локальную службу Orbit Connect. Сторонние приложения не используются."
            case .enabling:
                return "Сначала закрываем внешний трафик, затем проверяем конечный публичный IP."
            case .disabled:
                return "Системный агент установлен, но не применил политику."
            case .failed, .enabled:
                break
            }
        }
        if !snapshot.reason.isEmpty { return snapshot.reason }
        switch snapshot.state {
        case .trusted:
            return snapshot.finalAddress.map { "Конечный адрес: \($0)" }
                ?? "Маршрут подтверждён"
        case .verifying:
            return "До подтверждения конечного IP внешний трафик заблокирован."
        case .blocked:
            return "Доступны только локальная сеть и служебная проверка публичного IP."
        case .disabled:
            return "Сеть работает без дополнительной блокировки."
        }
    }

    var systemAgentTitle: String {
        switch filterState {
        case .requiresInstallation: return "Системный агент не установлен"
        case .installing: return "Системный агент устанавливается"
        case .enabling: return "Системный агент применяет политику"
        case .disabled: return "Системный агент готов"
        case .enabled: return "Системный агент активен"
        case .failed: return "Системный агент не отвечает"
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
            configuration.isEnabled = true
            persistConfiguration()
            invalidate(reason: "Ожидаем проверку конечного публичного IP")
            guard systemController.isInstalled || OrbitRuntime.isDemo else {
                promptToInstallSystemAgent()
                return
            }
            enableSystemControl()
        } else {
            confirmDisablingSystemControl()
        }
    }

    func promptToInstallSystemAgent() {
        guard !OrbitRuntime.isDemo else { return }
        guard !installationPromptVisible, filterState != .installing else { return }
        installationPromptVisible = true
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Установить системный контроль Orbit Connect?"
        alert.informativeText = "Внутренний агент Orbit Connect управляет встроенным сетевым экраном macOS и закрывает весь внешний трафик, пока конечный публичный IP не совпадёт с доверенным. Сторонние программы не устанавливаются. macOS запросит пароль администратора."
        alert.addButton(withTitle: "Установить")
        alert.addButton(withTitle: "Отмена")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            installationPromptVisible = false
            configuration.isEnabled = false
            persistConfiguration()
            snapshot = .disabled
            try? store.saveSnapshot(snapshot)
            return
        }

        filterState = .installing
        systemController.install { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.installationPromptVisible = false
                switch result {
                case .success:
                    self.enableSystemControl()
                case let .failure(error):
                    self.filterState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func retrySystemAgent() {
        if systemController.isInstalled {
            configuration.isEnabled ? enableSystemControl() : refreshFilterState()
        } else {
            promptToInstallSystemAgent()
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
        else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        addApplication(
            bundleIdentifier: identifier,
            displayName: name,
            applicationPath: url.path
        )
    }

    func addApplication(
        bundleIdentifier: String,
        displayName: String,
        applicationPath: String? = nil
    ) {
        guard !bundleIdentifier.isEmpty else { return }
        configuration.applications.append(
            ProtectedApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                applicationPath: applicationPath
            )
        )
        persistConfiguration()
    }

    func setTrafficDiscoveryEnabled(_ enabled: Bool) {
        store.setTrafficDiscoveryEnabled(enabled)
        if !enabled { flowEvents = store.loadFlowEvents() }
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
        guard configuration.isEnabled else { return }
        guard let status else { return }
        guard status.usingOrbit, !status.macChanged,
              status.staticExitEnabled == true,
              status.staticExitBlocked != true,
              status.trafficBlocked != true,
              let finalAddress = status.finalIP,
              configuration.expectedFinalAddresses.first == normalizedAddress(finalAddress)
        else {
            invalidate(reason: status.staticExitError ?? "Домашний Orbit не подтвердил доверенный выход")
            return
        }
        acceptTrust(finalAddress: finalAddress, reason: "Маршрут подтверждён домашним Orbit")
    }

    func update(observedFinalAddress: String) {
        guard configuration.isEnabled,
              let expectedAddress = configuration.expectedFinalAddresses.first
        else { return }
        let observedAddress = normalizedAddress(observedFinalAddress)
        guard observedAddress == expectedAddress else {
            invalidate(reason: "Текущий публичный IP не совпадает с доверенным")
            return
        }
        acceptTrust(
            finalAddress: observedAddress,
            reason: "Конечный публичный IP совпадает с доверенным"
        )
    }

    func invalidate(reason: String) {
        guard configuration.isEnabled else { return }
        trustExpirationTask?.cancel()
        snapshot = EgressTrustSnapshot(state: .blocked, reason: reason)
        try? store.saveSnapshot(snapshot)
        reconcilePolicy()
    }

    func refreshFilterState() {
        systemController.status { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.filterState = state
                if self.configuration.isEnabled,
                   state == .enabled || state == .disabled
                {
                    self.reconcilePolicy()
                }
            }
        }
        flowEvents = store.loadFlowEvents()
    }

    func loadDevelopmentDemo(force: Bool = false) {
        guard force || OrbitRuntime.isDemo else { return }
        configuration = EgressControlConfiguration(
            isEnabled: true,
            expectedFinalAddresses: ["203.0.113.42"]
        )
        snapshot = EgressTrustSnapshot(
            state: .trusted,
            finalAddress: "203.0.113.42",
            confirmedAt: Date(),
            reason: "Демонстрационный доверенный выход подтверждён"
        )
        filterState = .enabled
        flowEvents = []
    }

    private func acceptTrust(finalAddress: String, reason: String) {
        trustExpirationTask?.cancel()
        let confirmedAt = Date()
        snapshot = EgressTrustSnapshot(
            state: .trusted,
            finalAddress: normalizedAddress(finalAddress),
            confirmedAt: confirmedAt,
            reason: reason
        )
        try? store.saveSnapshot(snapshot)
        reconcilePolicy()
        scheduleExpiration(from: confirmedAt, after: configuration.confirmationLifetime)
    }

    private func schedulePersistedTrustExpiration() {
        guard configuration.isEnabled,
              snapshot.state == .trusted,
              let confirmedAt = snapshot.confirmedAt
        else { return }
        let remaining = configuration.confirmationLifetime - Date().timeIntervalSince(confirmedAt)
        guard remaining > 0 else {
            invalidate(reason: "Подтверждение доверенного выхода устарело")
            return
        }
        scheduleExpiration(from: confirmedAt, after: remaining)
    }

    private func scheduleExpiration(from confirmedAt: Date, after delay: TimeInterval) {
        trustExpirationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.configuration.isEnabled,
                      self.snapshot.confirmedAt == confirmedAt
                else { return }
                self.invalidate(reason: "Подтверждение доверенного выхода устарело")
            }
        }
    }

    private func enableSystemControl() {
        filterState = .enabling
        systemController.enable(configuration: configuration, snapshot: snapshot) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(state): self.filterState = state
                case let .failure(error): self.filterState = self.filterState(for: error)
                }
            }
        }
    }

    private func reconcilePolicy() {
        guard configuration.isEnabled, !OrbitRuntime.isDemo else { return }
        guard systemController.isInstalled else {
            filterState = .requiresInstallation
            return
        }
        guard !reconcileInProgress else {
            reconcilePending = true
            return
        }
        reconcileInProgress = true
        systemController.reconcile(configuration: configuration, snapshot: snapshot) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.reconcileInProgress = false
                switch result {
                case .success: self.filterState = .enabled
                case let .failure(error): self.filterState = self.filterState(for: error)
                }
                if self.reconcilePending {
                    self.reconcilePending = false
                    self.reconcilePolicy()
                }
            }
        }
    }

    private func disableSystemControl(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        trustExpirationTask?.cancel()
        systemController.disable { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case .success = result {
                    self.configuration.isEnabled = false
                    self.persistConfiguration()
                    self.snapshot = .disabled
                    try? self.store.saveSnapshot(self.snapshot)
                    self.filterState = .disabled
                } else if case let .failure(error) = result {
                    self.filterState = self.filterState(for: error)
                }
                completion?(result)
            }
        }
    }

    private func confirmDisablingSystemControl() {
        guard configuration.isEnabled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Выключить строгий контроль?"
        alert.informativeText = "Orbit Connect снимет свою блокировку внешнего трафика. Внутренний системный агент останется установленным для следующего включения."
        alert.addButton(withTitle: "Выключить")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { disableSystemControl() }
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

    private func persistConfiguration() {
        configuration = configuration.normalized
        do { try store.saveConfiguration(configuration) }
        catch { filterState = .failed("Не удалось сохранить настройки контроля") }
    }

    private func normalizedAddress(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func filterState(for error: Error) -> FilterState {
        guard let error = error as? EgressControlSystemController.ControllerError else {
            return .failed(error.localizedDescription)
        }
        switch error {
        case .missing: return .requiresInstallation
        case .unavailable, .commandFailed: return .failed(error.localizedDescription)
        }
    }
}
