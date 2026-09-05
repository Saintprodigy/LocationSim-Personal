import Foundation

/// Maintains the current RemotePairing endpoint plus ports that have completed a
/// full tunnel handshake in an earlier version of the app.
enum RemotePairingDiscovery {
    private static let cachedPortKey = "locationsim.personal.remote-pairing-port.v1"
    private static let cachedPortsKey = "locationsim.personal.remote-pairing-ports.v2"
    static let defaultPort: UInt16 = 49152

    /// The last port that completed the full RemotePairing/RSD handshake.
    /// Keeping this locally is what lets the next session start over cellular,
    /// where Bonjour advertisements are not always visible.
    static var cachedPort: UInt16? {
        if let first = cachedPorts.first { return first }
        guard let value = UserDefaults.standard.object(forKey: cachedPortKey) as? NSNumber else {
            return nil
        }
        let port = value.intValue
        guard (1...Int(UInt16.max)).contains(port) else { return nil }
        return UInt16(port)
    }

    static var hasOfflineReconnectPort: Bool { cachedPort != nil }

    static func rememberSuccessfulPort(_ port: UInt16) {
        var ports = cachedPorts.filter { $0 != port }
        ports.insert(port, at: 0)
        UserDefaults.standard.set(ports.prefix(5).map(Int.init), forKey: cachedPortsKey)
        UserDefaults.standard.set(Int(port), forKey: cachedPortKey)
    }

    /// Current upstream LocalDevVPN/StikDebug uses `10.7.0.1:49152` directly.
    /// Do not probe the socket first: a probe establishes and immediately drops
    /// a real RemotePairing connection, which can make iOS reset the handshake
    /// that follows. Previously successful nonstandard ports remain fallbacks.
    static func candidatePorts(deviceIP _: String) -> [UInt16] {
        unique([defaultPort] + cachedPorts)
    }

    private static func unique(_ ports: [UInt16]) -> [UInt16] {
        var seen = Set<UInt16>()
        return ports.filter { seen.insert($0).inserted }
    }

    private static var cachedPorts: [UInt16] {
        guard let values = UserDefaults.standard.array(forKey: cachedPortsKey) else {
            if let value = UserDefaults.standard.object(forKey: cachedPortKey) as? NSNumber,
               (1...Int(UInt16.max)).contains(value.intValue) {
                return [UInt16(value.intValue)]
            }
            return []
        }
        return values.compactMap { value in
            let number: Int?
            if let value = value as? NSNumber {
                number = value.intValue
            } else if let value = value as? Int {
                number = value
            } else {
                number = nil
            }
            guard let number, (1...Int(UInt16.max)).contains(number) else { return nil }
            return UInt16(number)
        }
    }
}
