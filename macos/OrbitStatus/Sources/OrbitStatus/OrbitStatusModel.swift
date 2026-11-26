import AppKit
import Combine
import Foundation

@MainActor
final class OrbitStatusModel: ObservableObject {
    enum ConnectionState {
        case unknown
        case orbit
        case direct
        case blocked

        var color: NSColor {
            switch self {
            case .unknown: return .systemGray
            case .orbit: return .systemGreen
            case .direct: return .systemRed
            case .blocked: return .systemRed
            }
        }
    }

    @Published private(set) var baseURL: String {
        didSet { OrbitRuntime.defaults.set(baseURL, forKey: "orbit.baseURL") }
    }
    @Published var pairingKey = ""
    @Published private(set) var status: ClientStatus?
    @Published private(set) var pairedDevice = ""
    @Published private(set) var loading = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var checkingForUpdate = false
    @Published private(set) var availableUpdate: ConnectUpdate?

    let egressControl = EgressControlCoordinator()

    var onStateChange: ((ConnectionState) -> Void)?

    private let api = OrbitAPIClient()
    private let networkMonitor = NetworkChangeMonitor()
    private var token: String?
    private var pollingTask: Task<Void, Never>?
    private var refreshing = false
    private var verifyingEgress = false
    private var discoveryRetry = DiscoveryRetrySchedule()
    private var lastAutomaticRebindAttempt: Date?

    init(isDemo: Bool = OrbitRuntime.isDemo) {
        baseURL = OrbitRuntime.defaults.string(forKey: "orbit.baseURL") ?? "http://orbit.home"
        if isDemo {
            token = "development-demo"
            status = .developmentDemo
            pairedDevice = ClientStatus.developmentDemo.device
            egressControl.loadDevelopmentDemo(force: true)
            return
        }
        token = KeychainStore.loadToken()
        networkMonitor.onChange = { [weak self] in
            Task { @MainActor in
                self?.networkDidChange()
            }
        }
        networkMonitor.start()
        startPolling()
    }

    var isPaired: Bool { token != nil }
    var state: ConnectionState {
        guard isPaired, let status else { return .unknown }
        if status.trafficBlocked == true || status.staticExitBlocked == true { return .blocked }
        return status.usingOrbit && !status.macChanged ? .orbit : .direct
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    var regionName: String {
        guard let code = status?.countryCode, !code.isEmpty else { return "Не определён" }
        return Locale(identifier: "ru_RU").localizedString(forRegionCode: code.uppercased()) ?? code
    }

    func pair() {
        let key = normalizePairingKey(pairingKey)
        guard !key.isEmpty else {
            errorMessage = "Введите одноразовый ключ"
            return
        }
        Task {
            await perform {
                let baseURL = try await self.resolveOrbit()
                let result = try await self.api.pair(baseURL: baseURL, key: key)
                do {
                    try KeychainStore.saveToken(result.token)
                } catch {
                    try? await self.api.revoke(baseURL: baseURL, token: result.token)
                    throw error
                }
                self.token = result.token
                self.pairedDevice = result.device
                self.pairingKey = ""
                do {
                    self.status = try await self.api.status(baseURL: baseURL, token: result.token)
                } catch {
                    self.status = nil
                }
            }
        }
    }

    func refresh() {
        if OrbitRuntime.isDemo {
            status = .developmentDemo
            pairedDevice = ClientStatus.developmentDemo.device
            updateState()
            return
        }
        verifyExternalEgress()
        guard let token else {
            status = nil
            updateState()
            return
        }
        guard !loading, !refreshing, discoveryRetry.canAttempt() else { return }
        Task {
            refreshing = true
            defer { refreshing = false }
            do {
                let baseURL = try await resolveOrbit()
                var latest = try await api.status(baseURL: baseURL, token: token)
                pairedDevice = latest.device
                status = latest
                if latest.macChanged, shouldAttemptAutomaticRebind() {
                    lastAutomaticRebindAttempt = Date()
                    latest = try await api.rebind(baseURL: baseURL, token: token)
                    status = latest
                    pairedDevice = latest.device
                }
                errorMessage = ""
            } catch OrbitAPIError.notFound {
                status = nil
                registerUnavailableNetwork()
            } catch {
                status = nil
                errorMessage = error.localizedDescription
            }
            updateState()
        }
    }

    func checkForUpdates(completion: ((Result<ConnectUpdate?, Error>) -> Void)? = nil) {
        guard !checkingForUpdate else { return }
        Task {
            checkingForUpdate = true
            do {
                availableUpdate = try await api.latestConnectUpdate(currentVersion: currentVersion)
                completion?(.success(availableUpdate))
            } catch {
                availableUpdate = nil
                completion?(.failure(error))
            }
            checkingForUpdate = false
        }
    }

    func downloadAvailableUpdate() {
        guard let url = availableUpdate?.downloadURL else {
            checkForUpdates()
            return
        }
        NSWorkspace.shared.open(url)
    }

    func rebind() {
        guard let token else { return }
        Task {
            await perform {
                let baseURL = try await self.resolveOrbit()
                self.status = try await self.api.rebind(baseURL: baseURL, token: token)
                self.pairedDevice = self.status?.device ?? self.pairedDevice
            }
        }
    }

    func retryStaticExit() {
        guard let token else { return }
        Task {
            await perform {
                let baseURL = try await self.resolveOrbit()
                self.status = try await self.api.retryStaticExit(baseURL: baseURL, token: token)
            }
        }
    }

    func disableStaticExit() {
        guard let token else { return }
        Task {
            await perform {
                let baseURL = try await self.resolveOrbit()
                self.status = try await self.api.disableStaticExit(baseURL: baseURL, token: token)
            }
        }
    }

    func deleteLink() {
        let previousToken = token
        KeychainStore.deleteToken()
        token = nil
        status = nil
        pairedDevice = ""
        pairingKey = ""
        errorMessage = ""
        discoveryRetry.reset()
        updateState()

        guard let previousToken else { return }
        Task {
            do {
                let baseURL = try await self.resolveOrbit()
                try await self.api.revoke(
                    baseURL: baseURL,
                    token: previousToken
                )
            } catch {
                // The local link is already removed. A subsequent successful
                // pairing replaces the stale router-side credential.
            }
        }
    }

    func openPrimaryServerSelection() {
        openOrbit(path: "/servers")
    }

    func openOrbit(path: String = "") {
        Task {
            do {
                let baseURL = try await resolveOrbit()
                guard let url = URL(string: baseURL + path) else { return }
                NSWorkspace.shared.open(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openKeeneticOS() {
        guard let url = api.keeneticURL(preferredURL: baseURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        loading = true
        errorMessage = ""
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
            status = nil
        }
        loading = false
        updateState()
    }

    private func resolveOrbit() async throws -> String {
        let resolved = try await api.discover(preferredURL: baseURL)
        discoveryRetry.reset()
        if resolved != baseURL {
            baseURL = resolved
        }
        return resolved
    }

    private func updateState() {
        egressControl.update(status: status)
        onStateChange?(state)
    }

    private func verifyExternalEgress() {
        guard egressControl.isEnabled, !verifyingEgress else { return }
        verifyingEgress = true
        Task {
            defer { verifyingEgress = false }
            do {
                let address = try await api.currentPublicIPAddress()
                egressControl.update(observedFinalAddress: address)
            } catch {
                egressControl.invalidate(reason: error.localizedDescription)
            }
        }
    }

    private func registerUnavailableNetwork() {
        guard let delay = discoveryRetry.recordFailure() else {
            errorMessage = "Ищем Orbit в локальной сети"
            return
        }
        errorMessage = "Orbit не найдена в локальной сети. Повторим поиск через \(delayDescription(delay))."
    }

    private func networkDidChange() {
        egressControl.invalidate(reason: "Сеть изменилась. Ожидаем проверку домашнего Orbit")
        status = nil
        updateState()
        discoveryRetry.reset()
        errorMessage = ""
        refresh()
    }

    private func delayDescription(_ delay: TimeInterval) -> String {
        let hours = Int(delay) / 3600
        if hours > 0 {
            return hours == 1 ? "1 час" : "\(hours) ч"
        }
        return "\(Int(delay) / 60) мин"
    }

    private func shouldAttemptAutomaticRebind() -> Bool {
        guard let lastAutomaticRebindAttempt else { return true }
        return Date().timeIntervalSince(lastAutomaticRebindAttempt) >= 300
    }

    private func normalizePairingKey(_ value: String) -> String {
        String(value.uppercased().unicodeScalars.filter { scalar in
            (scalar.value >= 48 && scalar.value <= 57) ||
                (scalar.value >= 65 && scalar.value <= 90)
        })
    }
}
