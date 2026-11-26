import CryptoKit
import Darwin
import Foundation
import OrbitConnectAgentProtocol

private final class PFController {
    enum PFError: LocalizedError {
        case command(String)

        var errorDescription: String? {
            switch self {
            case let .command(message): message
            }
        }
    }

    private let pfctl = URL(fileURLWithPath: "/sbin/pfctl")

    func setBlocked(_ blocked: Bool) throws {
        if blocked {
            try ensurePFEnabled()
            let rules = """
            pass out quick on lo0 all no state
            pass out quick inet to { 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4 } no state
            pass out quick inet6 to { ::1, fc00::/7, fe80::/10, ff00::/8 } no state
            pass out quick inet proto tcp to 1.1.1.1 port 443 no state
            pass out quick inet6 proto tcp to 2606:4700:4700::1111 port 443 no state
            block drop out quick inet all
            block drop out quick inet6 all
            """
            try run(
                ["-a", OrbitConnectAgentConstants.anchorName, "-f", "-"],
                input: rules + "\n"
            )
            // Existing PF states otherwise keep established public connections alive.
            try run(["-F", "states"])
        } else {
            _ = try run(
                ["-a", OrbitConnectAgentConstants.anchorName, "-F", "all"],
                acceptsFailure: true
            )
        }
    }

    private func ensurePFEnabled() throws {
        let info = try run(["-s", "info"], acceptsFailure: true)
        guard !info.contains("Status: Enabled") else { return }
        try run(["-e"])
    }

    @discardableResult
    private func run(
        _ arguments: [String],
        input: String? = nil,
        acceptsFailure: Bool = false
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = pfctl
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        if let input {
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(Data(input.utf8))
            try? pipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stdout = String(decoding: outputData, as: UTF8.self)
        let stderr = String(decoding: errorData, as: UTF8.self)
        guard process.terminationStatus == 0 || acceptsFailure else {
            throw PFError.command(
                stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "pfctl завершился с кодом \(process.terminationStatus)"
                    : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return stdout + stderr
    }
}

private final class AgentService: NSObject, OrbitConnectAgentXPCProtocol {
    private let queue = DispatchQueue(label: "io.orbit.connect.agent.policy")
    private let pf = PFController()
    private let policyURL = URL(
        fileURLWithPath: "/Library/Application Support/OrbitConnect/agent-policy.json"
    )
    private var policy: OrbitConnectAgentPolicy
    private var enforcement: OrbitConnectEnforcement = .disabled
    private var lastError: String?
    private var timer: DispatchSourceTimer?
    private var needsInitialReconcile = true

    override init() {
        let url = URL(
            fileURLWithPath: "/Library/Application Support/OrbitConnect/agent-policy.json"
        )
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(OrbitConnectAgentPolicy.self, from: data)
        {
            policy = saved
        } else {
            policy = OrbitConnectAgentPolicy(enabled: false)
        }
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.reconcile() }
        timer.resume()
        self.timer = timer
    }

    func status(withReply reply: @escaping (Data) -> Void) {
        queue.async { [self] in
            reply(encodeReply(status: currentStatus()))
        }
    }

    func apply(policy data: Data, withReply reply: @escaping (Data) -> Void) {
        queue.async { [self] in
            do {
                policy = try JSONDecoder().decode(OrbitConnectAgentPolicy.self, from: data)
                try persistPolicy()
                reconcile()
                if let lastError { throw PFController.PFError.command(lastError) }
                reply(encodeReply(status: currentStatus()))
            } catch {
                reply(encodeReply(error: error.localizedDescription))
            }
        }
    }

    private func reconcile() {
        let target = policy.enforcement()
        guard needsInitialReconcile || target != enforcement || lastError != nil else { return }
        do {
            try pf.setBlocked(target == .blocked)
            enforcement = target
            lastError = nil
            needsInitialReconcile = false
            persistStatus()
        } catch {
            lastError = error.localizedDescription
            persistStatus()
        }
    }

    private func currentStatus() -> OrbitConnectAgentStatus {
        OrbitConnectAgentStatus(
            enforcement: enforcement,
            trustedUntil: policy.trustedUntil,
            message: lastError
        )
    }

    private func persistPolicy() throws {
        try FileManager.default.createDirectory(
            at: policyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0,
            ]
        )
        try JSONEncoder().encode(policy).write(to: policyURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: policyURL.path
        )
    }

    private func persistStatus() {
        let status = currentStatus()
        guard let data = try? JSONEncoder().encode(status) else { return }
        let url = URL(fileURLWithPath: OrbitConnectAgentConstants.statusPath)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func encodeReply(
        status: OrbitConnectAgentStatus? = nil,
        error: String? = nil
    ) -> Data {
        (try? JSONEncoder().encode(OrbitConnectAgentReply(status: status, error: error))) ?? Data()
    }
}

private final class AgentDelegate: NSObject, NSXPCListenerDelegate {
    private let service = AgentService()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(
            connection.processIdentifier,
            &buffer,
            UInt32(buffer.count)
        )
        guard length > 0 else { return false }
        let path = String(cString: buffer)
        guard path == "/Applications/OrbitConnect.app/Contents/MacOS/OrbitStatus",
              let expected = try? String(
                  contentsOfFile: OrbitConnectAgentConstants.clientHashPath,
                  encoding: .utf8
              ).trimmingCharacters(in: .whitespacesAndNewlines),
              let executable = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return false }
        let actual = SHA256.hash(data: executable)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual == expected else { return false }
        connection.exportedInterface = NSXPCInterface(
            with: OrbitConnectAgentXPCProtocol.self
        )
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private let delegate = AgentDelegate()
private let listener = NSXPCListener(
    machServiceName: OrbitConnectAgentConstants.machServiceName
)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
