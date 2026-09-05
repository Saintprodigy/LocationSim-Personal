import Foundation
import Network

extension Notification.Name {
    static let locusNetworkPathChanged = Notification.Name("locusNetworkPathChanged")
}

/// Watches Wi-Fi/cellular/offline handoffs. The LocalDevVPN interface can stay
/// marked connected while Apple's RSD socket behind it has been invalidated,
/// so an active simulation must rebuild its connection after a path change.
final class NetworkPathObserver {
    static let shared = NetworkPathObserver()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.saint.locationsim.network-path")
    private var started = false
    private var lastFingerprint: String?

    private init() {}

    var isCellularOnly: Bool {
        let path = monitor.currentPath
        return path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let fingerprint = Self.fingerprint(for: path)
            guard fingerprint != self.lastFingerprint else { return }
            let hadPreviousPath = self.lastFingerprint != nil
            self.lastFingerprint = fingerprint
            guard hadPreviousPath else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                NotificationCenter.default.post(
                    name: .locusNetworkPathChanged,
                    object: nil,
                    userInfo: ["path": fingerprint]
                )
            }
        }
        monitor.start(queue: queue)
    }

    private static func fingerprint(for path: NWPath) -> String {
        let state = path.status == .satisfied ? "up" : "down"
        let interface: String
        if path.usesInterfaceType(.wifi) {
            interface = "wifi"
        } else if path.usesInterfaceType(.cellular) {
            interface = "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = "wired"
        } else if path.usesInterfaceType(.other) {
            interface = "other"
        } else {
            interface = "offline"
        }
        return "\(state):\(interface)"
    }
}
