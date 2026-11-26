import AppKit
import CryptoKit
import Foundation
import OrbitConnectAgentProtocol
import OrbitConnectPolicy

final class EgressControlSystemController {
    enum ControllerError: LocalizedError {
        case missing
        case unavailable(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missing:
                "Системный агент Orbit Connect не установлен"
            case let .unavailable(message), let .commandFailed(message):
                message
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isInstalled: Bool {
        guard fileManager.isExecutableFile(atPath: OrbitConnectAgentConstants.helperPath),
              fileManager.fileExists(atPath: OrbitConnectAgentConstants.launchDaemonPath),
              let expected = try? String(
                  contentsOfFile: OrbitConnectAgentConstants.clientHashPath,
                  encoding: .utf8
              ).trimmingCharacters(in: .whitespacesAndNewlines),
              let actual = currentClientHash()
        else { return false }
        return actual == expected
    }

    func install(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !OrbitRuntime.isDemo else {
            completion(.success(()))
            return
        }
        guard let helper = bundledResource("OrbitConnectAgent"),
              let daemon = bundledResource("io.orbit.connect.agent.plist")
        else {
            completion(.failure(ControllerError.missing))
            return
        }
        let temporaryHash = fileManager.temporaryDirectory
            .appendingPathComponent("orbit-connect-client-\(UUID().uuidString).sha256")
        do {
            guard let digest = currentClientHash() else {
                throw ControllerError.commandFailed("Не удалось определить бинарник Orbit Connect")
            }
            try Data((digest + "\n").utf8).write(to: temporaryHash, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryHash.path
            )
        } catch {
            completion(.failure(error))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? self.fileManager.removeItem(at: temporaryHash) }
            let command = [
                "/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools",
                "/usr/bin/install -d -o root -g wheel -m 700 '/Library/Application Support/OrbitConnect'",
                "/usr/bin/install -o root -g wheel -m 755 \(Self.shellQuote(helper.path)) \(Self.shellQuote(OrbitConnectAgentConstants.helperPath))",
                "/usr/bin/install -o root -g wheel -m 644 \(Self.shellQuote(daemon.path)) \(Self.shellQuote(OrbitConnectAgentConstants.launchDaemonPath))",
                "/usr/bin/install -o root -g wheel -m 644 \(Self.shellQuote(temporaryHash.path)) \(Self.shellQuote(OrbitConnectAgentConstants.clientHashPath))",
                "/bin/launchctl bootout system/\(OrbitConnectAgentConstants.machServiceName) >/dev/null 2>&1 || true",
                "/bin/launchctl bootstrap system \(Self.shellQuote(OrbitConnectAgentConstants.launchDaemonPath)) || true",
                "/bin/launchctl enable system/\(OrbitConnectAgentConstants.machServiceName) || true",
                "/bin/launchctl kickstart -k system/\(OrbitConnectAgentConstants.machServiceName) || true",
            ].joined(separator: "; ")
            let source = "do shell script \(Self.appleScriptQuote(command)) with administrator privileges"
            guard let script = NSAppleScript(source: source) else {
                completion(.failure(ControllerError.commandFailed("Не удалось подготовить установку агента")))
                return
            }
            var scriptError: NSDictionary?
            script.executeAndReturnError(&scriptError)
            if let scriptError {
                completion(.failure(ControllerError.commandFailed(
                    scriptError[NSAppleScript.errorMessage] as? String
                        ?? "Установка системного агента отменена"
                )))
            } else {
                completion(.success(()))
            }
        }
    }

    func status(completion: @escaping (EgressControlCoordinator.FilterState) -> Void) {
        if OrbitRuntime.isDemo {
            completion(.enabled)
            return
        }
        guard isInstalled else {
            completion(.requiresInstallation)
            return
        }
        requestStatus { result in
            switch result {
            case let .success(status):
                completion(status.enforcement == .disabled ? .disabled : .enabled)
            case let .failure(error):
                completion(.failed(error.localizedDescription))
            }
        }
    }

    func enable(
        configuration: EgressControlConfiguration,
        snapshot: EgressTrustSnapshot,
        completion: @escaping (Result<EgressControlCoordinator.FilterState, Error>) -> Void
    ) {
        apply(configuration: configuration, snapshot: snapshot) { result in
            completion(result.map { .enabled })
        }
    }

    func reconcile(
        configuration: EgressControlConfiguration,
        snapshot: EgressTrustSnapshot,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        apply(configuration: configuration, snapshot: snapshot, completion: completion)
    }

    func disable(completion: @escaping (Result<Void, Error>) -> Void) {
        send(policy: OrbitConnectAgentPolicy(enabled: false), completion: completion)
    }

    private func apply(
        configuration: EgressControlConfiguration,
        snapshot: EgressTrustSnapshot,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard isInstalled else {
            completion(.failure(ControllerError.missing))
            return
        }
        let trustedUntil: Date? = {
            guard snapshot.state == .trusted, let confirmedAt = snapshot.confirmedAt else {
                return nil
            }
            return confirmedAt.addingTimeInterval(configuration.confirmationLifetime)
        }()
        send(
            policy: OrbitConnectAgentPolicy(
                enabled: configuration.isEnabled,
                expectedAddress: configuration.expectedFinalAddresses.first,
                observedAddress: snapshot.finalAddress,
                trustedUntil: trustedUntil
            ),
            completion: completion
        )
    }

    private func requestStatus(
        completion: @escaping (Result<OrbitConnectAgentStatus, Error>) -> Void
    ) {
        let connection = makeConnection(errorHandler: { completion(.failure($0)) })
        guard let proxy = connection.remoteObjectProxy as? OrbitConnectAgentXPCProtocol else {
            connection.invalidate()
            completion(.failure(ControllerError.unavailable("Не удалось подключиться к системному агенту")))
            return
        }
        proxy.status { data in
            connection.invalidate()
            Self.decode(data, completion: completion)
        }
    }

    private func send(
        policy: OrbitConnectAgentPolicy,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let data = try? JSONEncoder().encode(policy) else {
            completion(.failure(ControllerError.commandFailed("Не удалось сформировать политику")))
            return
        }
        let connection = makeConnection(errorHandler: { completion(.failure($0)) })
        guard let proxy = connection.remoteObjectProxy as? OrbitConnectAgentXPCProtocol else {
            connection.invalidate()
            completion(.failure(ControllerError.unavailable("Не удалось подключиться к системному агенту")))
            return
        }
        proxy.apply(policy: data) { replyData in
            connection.invalidate()
            Self.decode(replyData) { (result: Result<OrbitConnectAgentStatus, Error>) in
                completion(result.map { _ in () })
            }
        }
    }

    private func makeConnection(errorHandler: @escaping (Error) -> Void) -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: OrbitConnectAgentConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: OrbitConnectAgentXPCProtocol.self
        )
        connection.interruptionHandler = {
            errorHandler(ControllerError.unavailable("Связь с системным агентом прервана"))
        }
        connection.resume()
        return connection
    }

    private static func decode(
        _ data: Data,
        completion: @escaping (Result<OrbitConnectAgentStatus, Error>) -> Void
    ) {
        do {
            let reply = try JSONDecoder().decode(OrbitConnectAgentReply.self, from: data)
            if let error = reply.error { throw ControllerError.commandFailed(error) }
            guard let status = reply.status else {
                throw ControllerError.unavailable("Системный агент вернул пустой ответ")
            }
            completion(.success(status))
        } catch {
            completion(.failure(error))
        }
    }

    private func bundledResource(_ name: String) -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func currentClientHash() -> String? {
        guard let executableURL = Bundle.main.executableURL,
              let data = try? Data(contentsOf: executableURL)
        else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
