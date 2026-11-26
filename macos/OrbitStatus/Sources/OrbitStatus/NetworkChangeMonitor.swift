import Darwin
import Foundation
import Network

final class NetworkChangeMonitor {
    var onChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "orbit.connect.network-change")
    private var started = false
    private var lastSignature: NetworkSignature?

    private struct NetworkSignature: Equatable {
        let interfaces: [String]
        let addresses: [String]
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            // PF blocking can temporarily make NWPath unsatisfied. That is not
            // a physical network change and must not invalidate trust again.
            guard let signature = Self.signature(for: path) else { return }
            guard let previous = lastSignature else {
                lastSignature = signature
                return
            }
            guard signature != previous else { return }
            lastSignature = signature
            onChange?()
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private static func signature(for path: NWPath) -> NetworkSignature? {
        guard path.status == .satisfied else { return nil }
        let interfaces = path.availableInterfaces
            .filter {
                $0.type == .wifi
                    || $0.type == .wiredEthernet
                    || $0.type == .cellular
            }
            .map(\.name)
            .sorted()
        guard !interfaces.isEmpty else { return nil }

        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return NetworkSignature(
                interfaces: interfaces,
                addresses: []
            )
        }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            let name = String(cString: item.pointee.ifa_name)
            guard interfaces.contains(name), let address = item.pointee.ifa_addr else {
                continue
            }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            addresses.append(String(cString: host))
        }
        return NetworkSignature(
            interfaces: interfaces,
            addresses: addresses.sorted()
        )
    }
}
