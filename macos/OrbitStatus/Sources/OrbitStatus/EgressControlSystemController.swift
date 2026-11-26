import Foundation
import NetworkExtension
import SystemExtensions

final class EgressControlSystemController: NSObject {
    static let extensionIdentifier = "io.orbit.status.network-filter"

    enum ControllerError: LocalizedError {
        case extensionMissing
        case activationFailed(String)

        var errorDescription: String? {
            switch self {
            case .extensionMissing:
                return "Компонент сетевого контроля не установлен"
            case let .activationFailed(message):
                return message
            }
        }
    }

    private var activationCompletion: ((Result<Void, Error>) -> Void)?

    func status(completion: @escaping (EgressControlCoordinator.FilterState) -> Void) {
        guard !OrbitRuntime.isDevelopment else {
            completion(.requiresInstallation)
            return
        }
        guard bundledExtensionURL != nil else {
            completion(.requiresInstallation)
            return
        }
        NEFilterManager.shared().loadFromPreferences { error in
            if let error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(NEFilterManager.shared().isEnabled ? .enabled : .disabled)
            }
        }
    }

    func enable(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !OrbitRuntime.isDevelopment else {
            completion(.failure(ControllerError.extensionMissing))
            return
        }
        guard bundledExtensionURL != nil else {
            completion(.failure(ControllerError.extensionMissing))
            return
        }
        activationCompletion = completion
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func disable(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !OrbitRuntime.isDevelopment else {
            completion(.success(()))
            return
        }
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            if let error {
                completion(.failure(error))
                return
            }
            manager.isEnabled = false
            manager.saveToPreferences { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private var bundledExtensionURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true)
            .appendingPathComponent("\(Self.extensionIdentifier).systemextension", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func configureFilter(completion: @escaping (Result<Void, Error>) -> Void) {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            if let error {
                completion(.failure(error))
                return
            }
            manager.localizedDescription = "Orbit Connect: доверенный выход"
            let providerConfiguration = NEFilterProviderConfiguration()
            providerConfiguration.filterDataProviderBundleIdentifier = Self.extensionIdentifier
            providerConfiguration.filterSockets = true
            manager.providerConfiguration = providerConfiguration
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}

extension EgressControlSystemController: OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {}

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        guard result == .completed else {
            activationCompletion?(
                .failure(
                    ControllerError.activationFailed(
                        "macOS завершит установку сетевого фильтра после перезагрузки"
                    )
                )
            )
            activationCompletion = nil
            return
        }
        configureFilter { [weak self] result in
            self?.activationCompletion?(result)
            self?.activationCompletion = nil
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        activationCompletion?(.failure(error))
        activationCompletion = nil
    }
}
