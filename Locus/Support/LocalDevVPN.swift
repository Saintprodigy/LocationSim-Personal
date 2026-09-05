import Darwin
import Foundation
import UIKit

enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let detectURL = URL(string: "localdevvpn://")!

    /// Starts the tunnel, then returns to LocationSim Personal.
    static let enableURL = URL(string: "localdevvpn://enable?scheme=locationsim")!

    /// Stops a stale tunnel, then returns to LocationSim Personal so it can
    /// immediately request a clean tunnel on the phone's current network path.
    static let disableURL = URL(string: "localdevvpn://disable?scheme=locationsim")!

    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(detectURL)
    }

    /// LocalDevVPN's defaults are a local `10.7.1.1` utun address and a
    /// `10.7.0.1` peer. The peer address is not assigned to an iOS interface,
    /// so checking only the peer's /24 incorrectly reports a healthy VPN as off.
    static var isConnected: Bool {
        let interfaces = ipv4Interfaces()
        let target = TunnelConfig.targetIP
        if interfaces.contains(where: { $0.address == target }) { return true }

        let parts = target.split(separator: ".")
        guard parts.count == 4 else { return false }
        let privateTunnelPrefix = parts.prefix(2).joined(separator: ".") + "."
        return interfaces.contains {
            $0.name.hasPrefix("utun") && $0.address.hasPrefix(privateTunnelPrefix)
        }
    }

    static func openInstalled() {
        UIApplication.shared.open(enableURL)
    }

    static func disableThenReturn() {
        UIApplication.shared.open(disableURL)
    }

    static func enableThenReturn() {
        UIApplication.shared.open(enableURL)
    }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }

    /// Open LocalDevVPN to connect if installed; otherwise App Store.
    static func openOrInstall() {
        if isInstalled {
            openInstalled()
        } else {
            openAppStore()
        }
    }

    private static func ipv4Interfaces() -> [(name: String, address: String)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [(name: String, address: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let interface = current.pointee
            if let socketAddress = interface.ifa_addr,
               socketAddress.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let nameLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                if getnameinfo(
                    socketAddress,
                    nameLen,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    results.append((
                        name: String(cString: interface.ifa_name),
                        address: String(cString: host)
                    ))
                }
            }
            ptr = interface.ifa_next
        }
        return results
    }
}
