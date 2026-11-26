import Foundation
import Network

final class NetworkChangeMonitor {
    var onChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "orbit.connect.network-change")
    private var started = false
    private var receivedInitialPath = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            if !receivedInitialPath {
                receivedInitialPath = true
                return
            }
            onChange?()
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
