import Foundation
import UIKit

enum CompatibilityLevel {
    case good
    case attention
    case information
}

struct CompatibilityCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    let level: CompatibilityLevel
}

@MainActor
enum CompatibilityReport {
    static let ideviceRevision = "c65dfbf"

    static func checks(pairing: PairingStore) -> [CompatibilityCheck] {
        let systemVersion = UIDevice.current.systemVersion
        let majorVersion = Int(systemVersion.split(separator: ".").first ?? "0") ?? 0
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return [
            CompatibilityCheck(
                id: "app",
                title: "LocationSim Personal \(version) (\(build))",
                detail: "Private build using idevice revision \(ideviceRevision).",
                level: .information
            ),
            CompatibilityCheck(
                id: "ios",
                title: "iOS \(systemVersion)",
                detail: majorVersion >= 18 ? "Supported developer-service generation." : "This build requires iOS 18 or newer.",
                level: majorVersion >= 18 ? .good : .attention
            ),
            CompatibilityCheck(
                id: "vpn",
                title: LocalDevVPN.isConnected ? "LocalDevVPN connected" : "LocalDevVPN not connected",
                detail: LocalDevVPN.isConnected ? "The private developer route is present." : "Connect LocalDevVPN before teleporting or starting a trip.",
                level: LocalDevVPN.isConnected ? .good : .attention
            ),
            CompatibilityCheck(
                id: "pairing",
                title: pairing.hasPairingFile ? "Pairing credential installed" : "Pairing credential missing",
                detail: pairing.hasRemotePairingKeys
                    ? "RemotePairing keys required by modern iOS are present."
                    : (pairing.hasPairingFile ? "The file does not expose the expected RemotePairing key set; replace it if connections fail." : "Import a fresh RPPairing file."),
                level: pairing.hasRemotePairingKeys ? .good : .attention
            ),
            CompatibilityCheck(
                id: "offline",
                title: RemotePairingDiscovery.hasOfflineReconnectPort ? "Previous handshake saved" : "No successful handshake saved",
                detail: RemotePairingDiscovery.hasOfflineReconnectPort
                    ? "A port worked previously. This does not verify current cellular or offline availability."
                    : "Complete one successful Wi-Fi teleport before relying on offline reconnect.",
                level: RemotePairingDiscovery.hasOfflineReconnectPort ? .good : .attention
            ),
            CompatibilityCheck(
                id: "pairing-mode",
                title: majorVersion >= 27 ? "On-device pairing available" : "Imported pairing required",
                detail: majorVersion >= 27
                    ? "This iOS version can pair from Settings without a computer."
                    : "iOS 18–26 continues to use the imported RPPairing credential.",
                level: .information
            )
        ]
    }

    static func text(pairing: PairingStore) -> String {
        checks(pairing: pairing).map { "\($0.title): \($0.detail)" }.joined(separator: "\n")
    }
}
