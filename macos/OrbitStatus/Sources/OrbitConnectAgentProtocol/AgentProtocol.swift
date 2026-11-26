import Foundation

public enum OrbitConnectAgentConstants {
    public static let machServiceName = "io.orbit.connect.agent"
    public static let helperPath = "/Library/PrivilegedHelperTools/io.orbit.connect.agent"
    public static let launchDaemonPath = "/Library/LaunchDaemons/io.orbit.connect.agent.plist"
    public static let clientHashPath = "/Library/PrivilegedHelperTools/io.orbit.connect.agent.client.sha256"
    public static let statusPath = "/Library/Application Support/OrbitConnect/agent-status.json"
    public static let anchorName = "com.apple/orbit-connect"
}

public enum OrbitConnectEnforcement: String, Codable, Sendable {
    case disabled
    case blocked
    case trusted
}

public struct OrbitConnectAgentPolicy: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var expectedAddress: String?
    public var observedAddress: String?
    public var trustedUntil: Date?

    public init(
        enabled: Bool,
        expectedAddress: String? = nil,
        observedAddress: String? = nil,
        trustedUntil: Date? = nil
    ) {
        self.enabled = enabled
        self.expectedAddress = expectedAddress
        self.observedAddress = observedAddress
        self.trustedUntil = trustedUntil
    }

    public func enforcement(at now: Date = Date()) -> OrbitConnectEnforcement {
        guard enabled else { return .disabled }
        let expected = normalized(expectedAddress)
        let observed = normalized(observedAddress)
        guard !expected.isEmpty,
              expected == observed,
              (trustedUntil ?? .distantPast) > now
        else { return .blocked }
        return .trusted
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct OrbitConnectAgentStatus: Codable, Equatable, Sendable {
    public var enforcement: OrbitConnectEnforcement
    public var trustedUntil: Date?
    public var message: String?

    public init(
        enforcement: OrbitConnectEnforcement,
        trustedUntil: Date? = nil,
        message: String? = nil
    ) {
        self.enforcement = enforcement
        self.trustedUntil = trustedUntil
        self.message = message
    }
}

public struct OrbitConnectAgentReply: Codable, Sendable {
    public var status: OrbitConnectAgentStatus?
    public var error: String?

    public init(status: OrbitConnectAgentStatus? = nil, error: String? = nil) {
        self.status = status
        self.error = error
    }
}

@objc public protocol OrbitConnectAgentXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func apply(policy: Data, withReply reply: @escaping (Data) -> Void)
}
