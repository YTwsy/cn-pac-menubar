import Foundation

public enum ProxyMode: String, Codable, CaseIterable, Sendable {
    case socks5
    case http
    case socks5AndHTTP

    public var displayName: String {
        switch self {
        case .socks5:
            return "SOCKS5"
        case .http:
            return "HTTP"
        case .socks5AndHTTP:
            return "SOCKS5 + HTTP"
        }
    }
}

public enum LauncherProfile: String, Codable, CaseIterable, Sendable {
    case environment
    case chromium
    case java
    case systemProxyPreferred

    public var displayName: String {
        switch self {
        case .environment:
            return "Environment"
        case .chromium:
            return "Chromium/Electron"
        case .java:
            return "Java"
        case .systemProxyPreferred:
            return "System PAC preferred"
        }
    }

    public var note: String? {
        switch self {
        case .environment:
            return nil
        case .chromium:
            return "Adds Chromium proxy flags."
        case .java:
            return "Adds JVM proxy options."
        case .systemProxyPreferred:
            return "This app may ignore launcher variables."
        }
    }
}

public struct CNPacSettings: Codable, Equatable, Sendable {
    public var pacPath: String?
    public var recentPACPaths: [String]
    public var pacServerPort: Int
    public var proxyHost: String
    public var socks5Port: Int
    public var httpPort: Int
    public var proxyMode: ProxyMode
    public var noProxy: String
    public var launchAtLogin: Bool
    public var refreshVersion: Int

    public init(
        pacPath: String? = nil,
        recentPACPaths: [String] = [],
        pacServerPort: Int = 8118,
        proxyHost: String = "127.0.0.1",
        socks5Port: Int = 1080,
        httpPort: Int = 8080,
        proxyMode: ProxyMode = .socks5AndHTTP,
        noProxy: String = "127.0.0.1,localhost,::1",
        launchAtLogin: Bool = false,
        refreshVersion: Int = 1
    ) {
        self.pacPath = pacPath
        self.recentPACPaths = recentPACPaths
        self.pacServerPort = pacServerPort
        self.proxyHost = proxyHost
        self.socks5Port = socks5Port
        self.httpPort = httpPort
        self.proxyMode = proxyMode
        self.noProxy = noProxy
        self.launchAtLogin = launchAtLogin
        self.refreshVersion = refreshVersion
    }

    public var pacURL: URL {
        pacURL(host: "127.0.0.1")
    }

    public func pacURL(host: String) -> URL {
        URL(string: "http://\(host):\(pacServerPort)/proxy.pac?v=\(refreshVersion)")!
    }

    public var httpProxyURL: String {
        "http://\(proxyHost):\(httpPort)"
    }

    public var proxyEndpointSummary: String {
        switch proxyMode {
        case .socks5:
            return "SOCKS5 \(proxyHost):\(socks5Port)"
        case .http:
            return "HTTP \(proxyHost):\(httpPort)"
        case .socks5AndHTTP:
            return "SOCKS5 \(proxyHost):\(socks5Port) + HTTP \(proxyHost):\(httpPort)"
        }
    }

    public var proxyCompactSummary: String {
        let hostPrefix = proxyHost == "127.0.0.1" || proxyHost == "localhost" ? "" : "\(proxyHost) "
        switch proxyMode {
        case .socks5:
            return "\(hostPrefix)SOCKS5:\(socks5Port)"
        case .http:
            return "\(hostPrefix)HTTP:\(httpPort)"
        case .socks5AndHTTP:
            return "\(hostPrefix)SOCKS5:\(socks5Port) + HTTP:\(httpPort)"
        }
    }

    public var proxyStatusBarSummary: String {
        let hostPrefix = proxyHost == "127.0.0.1" || proxyHost == "localhost" ? "" : "\(proxyHost) "
        switch proxyMode {
        case .socks5:
            return "\(hostPrefix)S5:\(socks5Port)"
        case .http:
            return "\(hostPrefix)H:\(httpPort)"
        case .socks5AndHTTP:
            return "\(hostPrefix)S5:\(socks5Port) H:\(httpPort)"
        }
    }

    public var pacProxyExpression: String {
        switch proxyMode {
        case .socks5:
            return "SOCKS5 \(proxyHost):\(socks5Port); DIRECT;"
        case .http:
            return "PROXY \(proxyHost):\(httpPort); DIRECT;"
        case .socks5AndHTTP:
            return "SOCKS5 \(proxyHost):\(socks5Port); PROXY \(proxyHost):\(httpPort); DIRECT;"
        }
    }

    public mutating func rememberPACPath(_ path: String) {
        pacPath = path
        recentPACPaths.removeAll { $0 == path }
        recentPACPaths.insert(path, at: 0)
        if recentPACPaths.count > 8 {
            recentPACPaths = Array(recentPACPaths.prefix(8))
        }
    }

    public mutating func bumpRefreshVersion() {
        refreshVersion += 1
        if refreshVersion > 999_999 {
            refreshVersion = 1
        }
    }
}

public struct LauncherRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var targetAppPath: String
    public var launcherAppPath: String
    public var bundleIdentifier: String?
    public var launcherProfile: LauncherProfile?
    public var createdAt: Date
    public var lastLaunchedAt: Date?
    public var managedByTool: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        targetAppPath: String,
        launcherAppPath: String,
        bundleIdentifier: String?,
        launcherProfile: LauncherProfile? = nil,
        createdAt: Date = Date(),
        lastLaunchedAt: Date? = nil,
        managedByTool: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.targetAppPath = targetAppPath
        self.launcherAppPath = launcherAppPath
        self.bundleIdentifier = bundleIdentifier
        self.launcherProfile = launcherProfile
        self.createdAt = createdAt
        self.lastLaunchedAt = lastLaunchedAt
        self.managedByTool = managedByTool
    }
}

public struct LauncherIndex: Codable, Equatable, Sendable {
    public var launchers: [LauncherRecord]

    public init(launchers: [LauncherRecord] = []) {
        self.launchers = launchers
    }

    public mutating func upsert(_ record: LauncherRecord) {
        if let index = launchers.firstIndex(where: { $0.launcherAppPath == record.launcherAppPath }) {
            launchers[index] = record
        } else {
            launchers.append(record)
        }
        launchers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public mutating func remove(path: String) {
        launchers.removeAll { $0.launcherAppPath == path }
    }
}
