import Darwin
import Foundation

public enum NetworkInterface {
    public static func primaryLANIPv4Address() -> String? {
        allLANIPv4Addresses().first
    }

    public static func allLANIPv4Addresses() -> [String] {
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacesPointer) == 0, let firstInterface = interfacesPointer else {
            return []
        }
        defer { freeifaddrs(interfacesPointer) }

        var addresses: [(name: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }

            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET),
                  isUsableLANInterface(interface) else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let address = String(cString: host)
            guard !address.hasPrefix("127."), !address.hasPrefix("169.254.") else {
                continue
            }
            addresses.append((name: String(cString: interface.ifa_name), address: address))
        }

        return addresses
            .sorted { lhs, rhs in
                interfaceRank(lhs.name) < interfaceRank(rhs.name)
            }
            .map(\.address)
    }

    private static func isUsableLANInterface(_ interface: ifaddrs) -> Bool {
        let flags = Int32(interface.ifa_flags)
        let name = String(cString: interface.ifa_name)
        return flags & IFF_UP != 0
            && flags & IFF_LOOPBACK == 0
            && flags & IFF_RUNNING != 0
            && !name.hasPrefix("utun")
            && !name.hasPrefix("awdl")
            && !name.hasPrefix("llw")
    }

    private static func interfaceRank(_ name: String) -> Int {
        if name.hasPrefix("en") {
            return 0
        }
        if name.hasPrefix("bridge") {
            return 1
        }
        return 2
    }
}
