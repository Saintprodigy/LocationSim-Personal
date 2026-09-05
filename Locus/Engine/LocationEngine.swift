import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP
    case pairingRead
    case tunnelCreate
    case remoteServer
    case simulationCreate
    case locationSet
    case locationClear
    case notActive

    var errorDescription: String? {
        switch self {
        case .invalidIP: return "Tunnel IP is invalid. Check Settings → Tunnel IP (usually 10.7.0.1)."
        case .pairingRead: return "Could not read the RPPairing file. Generate one with idevice_pair in RPPairing mode."
        case .tunnelCreate: return "Could not open the developer tunnel. Connect LocalDevVPN, wait a few seconds after switching Wi‑Fi or cellular, then retry. After an iPhone restart, Wi‑Fi may be needed once to refresh Apple’s local service."
        case .remoteServer: return "Apple’s local developer service did not finish reconnecting. Reconnect LocalDevVPN and retry; after an iPhone restart, use Wi‑Fi once if needed to refresh the saved service."
        case .simulationCreate: return "Could not open Apple’s location simulation service."
        case .locationSet: return "Failed to set simulated coordinates."
        case .locationClear: return "Failed to clear simulated location."
        case .notActive: return "No active simulation session."
        }
    }

    static func from(code: Int32) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead
        case 3: return .tunnelCreate
        case 9: return .remoteServer
        case 10: return .simulationCreate
        case 11: return .locationSet
        case 12: return .locationClear
        default: return .locationSet
        }
    }
}

/// Thin Swift wrapper around idevice’s DVT location simulation (injects into locationd).
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?
    private(set) static var lastDiagnostic: String?

    private static let ok: Int32 = 0
    private static let invalidIP: Int32 = 1
    private static let pairingRead: Int32 = 2
    private static let tunnelCreate: Int32 = 3
    private static let remoteServerCode: Int32 = 9
    private static let simulationCreate: Int32 = 10
    private static let locationSet: Int32 = 11
    private static let locationClear: Int32 = 12

    static var isSessionActive: Bool { queue.sync { locationSimulation != nil } }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        queue.sync {
            let code = setLocked(latitude: latitude, longitude: longitude, pairingPath: pairingPath, deviceIP: deviceIP)
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    static func clear(keepConnection: Bool = false) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            let code = clearLocked(keepConnection: keepConnection)
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    /// Discards all native handles so the next set creates a fresh RSD session.
    /// This is required after Wi-Fi/cellular handoffs because the old socket can
    /// remain non-nil even though iOS has already invalidated it.
    static func resetConnection() {
        queue.sync {
            cleanup()
            lastDiagnostic = nil
        }
    }

    static func userMessage(for error: LocationEngineError) -> String {
        guard let diagnostic = lastDiagnostic, !diagnostic.isEmpty else {
            return error.localizedDescription
        }

        let lowercased = diagnostic.lowercased()
        let recovery: String
        if lowercased.contains("pair") || lowercased.contains("verify") || lowercased.contains("auth") {
            recovery = "The saved RPPairing credential may need to be replaced. Open Settings → Pairing and create or import a fresh file."
        } else if lowercased.contains("refused") || lowercased.contains("unreachable") || lowercased.contains("no route") {
            recovery = "LocalDevVPN is present, but its route to 10.7.0.1 is not ready. Reconnect LocalDevVPN and retry."
        } else if lowercased.contains("reset") || lowercased.contains("closed") {
            recovery = "iOS closed the local service. Keep the phone unlocked, reconnect LocalDevVPN, and retry; if it repeats, refresh the pairing file."
        } else if lowercased.contains("timed out") || lowercased.contains("timeout") {
            recovery = "Apple's local developer service did not answer in time. Wake the phone, reconnect LocalDevVPN, and retry."
        } else {
            recovery = error.localizedDescription
        }
        return "\(recovery)\n\nTunnel details: \(diagnostic)"
    }

    private static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Int32 {
        lastDiagnostic = nil
        if let locationSimulation {
            if let err = location_simulation_set(locationSimulation, latitude, longitude) {
                lastDiagnostic = diagnostic(for: err, stage: "update location", port: nil)
                idevice_error_free(err)
                cleanup()
            } else {
                return ok
            }
        }

        var pairingHandle: OpaquePointer?
        if let pairingError = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            lastDiagnostic = diagnostic(for: pairingError, stage: "read pairing", port: nil)
            idevice_error_free(pairingError)
            return pairingRead
        }
        guard let pairingHandle else { return pairingRead }
        defer { rp_pairing_file_free(pairingHandle) }

        // Match the upstream tunnel engine's default. Three seconds proved too
        // aggressive on older phones immediately after a network handoff.
        idevice_set_global_timeout(5)

        let ports = RemotePairingDiscovery.candidatePorts(deviceIP: deviceIP)
        var lastConnectionError = tunnelCreate

        // A network handoff can make LocalDevVPN appear ready just before the
        // RSD endpoint is actually available. Retry the complete handshake once
        // rather than preserving a stale native handle.
        for round in 0..<2 {
            for port in ports {
                cleanup()

                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(port).bigEndian
                let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
                guard inetResult == 1 else { return invalidIP }

                let providerError = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        tunnel_create_rppairing(
                            $0,
                            socklen_t(MemoryLayout<sockaddr_in>.stride),
                            "LocusLocation",
                            pairingHandle,
                            nil,
                            nil,
                            &adapter,
                            &handshake
                        )
                    }
                }
                if let providerError {
                    lastDiagnostic = diagnostic(for: providerError, stage: "open \(deviceIP)", port: port)
                    idevice_error_free(providerError)
                    lastConnectionError = tunnelCreate
                    continue
                }

                if let remoteServerError = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
                    lastDiagnostic = diagnostic(for: remoteServerError, stage: "open developer service", port: port)
                    idevice_error_free(remoteServerError)
                    lastConnectionError = remoteServerCode
                    continue
                }

                if let simError = location_simulation_new(remoteServer, &locationSimulation) {
                    lastDiagnostic = diagnostic(for: simError, stage: "open location service", port: port)
                    idevice_error_free(simError)
                    lastConnectionError = simulationCreate
                    continue
                }
                // The FFI client BORROWS this server; it does not consume it.
                // Keep the owner until cleanup frees the simulation first, then the server.

                if let setError = location_simulation_set(locationSimulation, latitude, longitude) {
                    lastDiagnostic = diagnostic(for: setError, stage: "set coordinates", port: port)
                    idevice_error_free(setError)
                    lastConnectionError = locationSet
                    continue
                }

                RemotePairingDiscovery.rememberSuccessfulPort(port)
                lastDiagnostic = nil
                return ok
            }

            if round == 0 {
                Thread.sleep(forTimeInterval: 0.75)
            }
        }

        cleanup()
        return lastConnectionError
    }

    private static func clearLocked(keepConnection: Bool) -> Int32 {
        guard let locationSimulation else { return locationClear }
        let err = location_simulation_clear(locationSimulation)
        if let err {
            lastDiagnostic = diagnostic(for: err, stage: "clear location", port: nil)
            idevice_error_free(err)
            cleanup()
            return locationClear
        }
        // Clearing the simulated position does not require closing the tunnel.
        // Reuse it on the next set; setLocked rebuilds it if it has gone stale.
        if !keepConnection { cleanup() }
        lastDiagnostic = nil
        return ok
    }

    private static func diagnostic(
        for error: UnsafeMutablePointer<IdeviceFfiError>,
        stage: String,
        port: UInt16?
    ) -> String {
        let value = error.pointee
        let message: String
        if let pointer = value.message {
            message = String(cString: pointer)
        } else {
            message = "Unknown tunnel error"
        }
        let endpoint = port.map { " at \(TunnelConfig.targetIP):\($0)" } ?? ""
        return "\(stage)\(endpoint) — code \(value.code)/\(value.sub_code): \(message)"
    }
}
