import Foundation

enum TunnelConfig {
    /// LocalDevVPN / SideStore-style loopback tunnel endpoint.
    static let defaultIP = "10.7.0.1"
    private static let localInterfaceIP = "10.7.1.1"
    static let defaultsKey = "locus.targetDeviceIP"

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        if stored == localInterfaceIP {
            // Earlier setup guidance could lead someone to copy LocalDevVPN's
            // own interface address. The developer service lives on the peer.
            UserDefaults.standard.set(defaultIP, forKey: defaultsKey)
            return defaultIP
        }
        return stored
    }

    static func setTargetIP(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty || trimmed == localInterfaceIP ? defaultIP : trimmed
        UserDefaults.standard.set(normalized, forKey: defaultsKey)
    }
}
