import NetworkExtension
import OrbitConnectPolicy
import Security

public final class FilterDataProvider: NEFilterDataProvider {
    private let store = EgressControlStore()
    private let flowLock = NSLock()
    private var protectedFlows: [UUID: ProtectedFlow] = [:]

    public override func startFilter(
        completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(nil)
    }

    public override func stopFilter(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    public override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let descriptor = EgressFlowDescriptor(
            // macOS does not expose NEFilterFlow.sourceAppIdentifier. Resolve
            // the signed bundle identifier from the audit token instead.
            sourceApplicationIdentifier: SourceApplicationResolver.bundleIdentifier(
                auditToken: flow.sourceAppAuditToken
            ),
            remoteHost: Self.remoteHost(for: flow)
        )
        let configuration = store.loadConfiguration()
        guard EgressControlEvaluator.isProtected(
            configuration: configuration,
            flow: descriptor
        ) else {
            if store.isTrafficDiscoveryEnabled(),
               descriptor.sourceApplicationIdentifier != nil
            {
                record(
                    descriptor: descriptor,
                    routeMode: .direct,
                    decision: .allow,
                    reasonOverride: "Замечено во время выбора приложения"
                )
            }
            return .allow()
        }
        let decision = EgressControlEvaluator.decision(
            configuration: configuration,
            snapshot: store.loadSnapshot(),
            flow: descriptor
        )
        record(
            descriptor: descriptor,
            routeMode: EgressControlEvaluator.routeMode(
                configuration: configuration,
                flow: descriptor
            ) ?? .trustedExit,
            decision: decision
        )
        switch decision {
        case .allow:
            remember(descriptor, for: flow.identifier)
            return .filterDataVerdict(
                withFilterInbound: true,
                peekInboundBytes: 1,
                filterOutbound: true,
                peekOutboundBytes: 1
            )
        case .drop:
            return .drop()
        }
    }

    public override func handleOutboundData(
        from flow: NEFilterFlow,
        readBytesStartOffset offset: Int,
        readBytes: Data
    ) -> NEFilterDataVerdict {
        dataVerdict(for: flow, byteCount: readBytes.count)
    }

    public override func handleInboundData(
        from flow: NEFilterFlow,
        readBytesStartOffset offset: Int,
        readBytes: Data
    ) -> NEFilterDataVerdict {
        dataVerdict(for: flow, byteCount: readBytes.count)
    }

    public override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        let verdict = currentVerdict(for: flow)
        markComplete(flow.identifier, direction: .outbound)
        return verdict
    }

    public override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        let verdict = currentVerdict(for: flow)
        markComplete(flow.identifier, direction: .inbound)
        return verdict
    }

    private func dataVerdict(for flow: NEFilterFlow, byteCount: Int) -> NEFilterDataVerdict {
        guard let descriptor = descriptor(for: flow.identifier) else {
            return .drop()
        }
        let decision = EgressControlEvaluator.decision(
            configuration: store.loadConfiguration(),
            snapshot: store.loadSnapshot(),
            flow: descriptor
        )
        switch decision {
        case .allow:
            return NEFilterDataVerdict(
                passBytes: byteCount,
                peekBytes: 1
            )
        case .drop:
            forget(flow.identifier)
            return .drop()
        }
    }

    private func currentVerdict(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        guard let descriptor = descriptor(for: flow.identifier) else { return .drop() }
        let decision = EgressControlEvaluator.decision(
            configuration: store.loadConfiguration(),
            snapshot: store.loadSnapshot(),
            flow: descriptor
        )
        if case .allow = decision { return .allow() }
        forget(flow.identifier)
        return .drop()
    }

    private static func remoteHost(for flow: NEFilterFlow) -> String? {
        guard let socketFlow = flow as? NEFilterSocketFlow else { return nil }
        return socketFlow.remoteHostname
            ?? (socketFlow.remoteEndpoint as? NWHostEndpoint)?.hostname
    }

    private func remember(_ descriptor: EgressFlowDescriptor, for identifier: UUID) {
        flowLock.lock()
        protectedFlows[identifier] = ProtectedFlow(descriptor: descriptor)
        flowLock.unlock()
    }

    private func descriptor(for identifier: UUID) -> EgressFlowDescriptor? {
        flowLock.lock()
        defer { flowLock.unlock() }
        return protectedFlows[identifier]?.descriptor
    }

    private func markComplete(_ identifier: UUID, direction: FlowDirection) {
        flowLock.lock()
        defer { flowLock.unlock() }
        guard var flow = protectedFlows[identifier] else { return }
        switch direction {
        case .inbound: flow.inboundComplete = true
        case .outbound: flow.outboundComplete = true
        }
        if flow.inboundComplete && flow.outboundComplete {
            protectedFlows.removeValue(forKey: identifier)
        } else {
            protectedFlows[identifier] = flow
        }
    }

    private func forget(_ identifier: UUID) {
        flowLock.lock()
        protectedFlows.removeValue(forKey: identifier)
        flowLock.unlock()
    }

    private func record(
        descriptor: EgressFlowDescriptor,
        routeMode: ApplicationRouteMode,
        decision: EgressControlDecision,
        reasonOverride: String? = nil
    ) {
        let allowed: Bool
        let reason: String
        switch decision {
        case .allow:
            allowed = true
            reason = reasonOverride ?? (routeMode == .direct
                ? "Разрешено прямым правилом"
                : "Доверенный выход подтверждён")
        case let .drop(message):
            allowed = false
            reason = message
        }
        let event = EgressFlowEvent(
            applicationIdentifier: descriptor.sourceApplicationIdentifier ?? "Не определено",
            remoteHost: descriptor.remoteHost ?? "Адрес не определён",
            routeMode: routeMode,
            allowed: allowed,
            reason: reason
        )
        flowLock.lock()
        defer { flowLock.unlock() }
        try? store.recordFlowEvent(event)
    }
}

private struct ProtectedFlow {
    let descriptor: EgressFlowDescriptor
    var inboundComplete = false
    var outboundComplete = false
}

private enum FlowDirection {
    case inbound
    case outbound
}

private enum SourceApplicationResolver {
    static func bundleIdentifier(auditToken: Data?) -> String? {
        guard let auditToken else { return nil }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let values = information as? [CFString: Any]
        else { return nil }
        return values[kSecCodeInfoIdentifier] as? String
    }
}
