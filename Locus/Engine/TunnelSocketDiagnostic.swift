import Darwin
import Foundation

/// Developer diagnostic only. Records no pairing credentials or user locations.
enum TunnelSocketDiagnostic {
    static func run() -> [[String: String]] {
        var results = [probe(interface: nil), probe(interface: nil, host: "127.0.0.1")]
        var addresses: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addresses) == 0, let first = addresses {
            defer { freeifaddrs(first) }
            var current: UnsafeMutablePointer<ifaddrs>? = first
            var seen = Set<String>()
            while let entry = current {
                let name = String(cString: entry.pointee.ifa_name)
                if name.hasPrefix("utun"), seen.insert(name).inserted {
                    results.append(probe(interface: name))
                }
                current = entry.pointee.ifa_next
            }
        }
        return results
    }

    private static func probe(interface: String?, host: String = TunnelConfig.targetIP) -> [String: String] {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return ["error": String(errno)] }
        defer { close(fd) }
        var report = ["interface": interface ?? "automatic", "host": host]
        if let interface {
            var index = if_nametoindex(interface)
            if setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout.size(ofValue: index))) != 0 {
                report["bindError"] = String(cString: strerror(errno))
                return report
            }
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(49152).bigEndian
        _ = host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var socketError = result == 0 ? Int32(0) : errno
        if socketError == EINPROGRESS {
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, 2500)
            if ready > 0 {
                var size = socklen_t(MemoryLayout<Int32>.size)
                _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &size)
            } else {
                socketError = ready == 0 ? ETIMEDOUT : errno
            }
        }
        report["errno"] = String(socketError)
        report["result"] = socketError == 0 ? "connected" : String(cString: strerror(socketError))
        return report
    }
}
