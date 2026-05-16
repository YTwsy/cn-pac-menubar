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
    public static let defaultVPNKeepaliveURL = "https://www.gstatic.com/generate_204"

    public var pacPath: String?
    public var recentPACPaths: [String]
    public var pacServerPort: Int
    public var proxyHost: String
    public var socks5Port: Int
    public var httpPort: Int
    public var proxyMode: ProxyMode
    public var allowDirectFallback: Bool
    public var noProxy: String
    public var launchAtLogin: Bool
    public var vpnKeepaliveEnabled: Bool
    public var vpnKeepaliveURL: String
    public var vpnKeepaliveIntervalSeconds: Int
    public var vpnKeepaliveTimeoutSeconds: Int
    public var refreshVersion: Int

    public init(
        pacPath: String? = nil,
        recentPACPaths: [String] = [],
        pacServerPort: Int = 8118,
        proxyHost: String = "127.0.0.1",
        socks5Port: Int = 1080,
        httpPort: Int = 8080,
        proxyMode: ProxyMode = .socks5AndHTTP,
        allowDirectFallback: Bool = false,
        noProxy: String = "127.0.0.1,localhost,::1",
        launchAtLogin: Bool = false,
        vpnKeepaliveEnabled: Bool = false,
        vpnKeepaliveURL: String = CNPacSettings.defaultVPNKeepaliveURL,
        vpnKeepaliveIntervalSeconds: Int = 300,
        vpnKeepaliveTimeoutSeconds: Int = 10,
        refreshVersion: Int = 1
    ) {
        self.pacPath = pacPath
        self.recentPACPaths = recentPACPaths
        self.pacServerPort = pacServerPort
        self.proxyHost = proxyHost
        self.socks5Port = socks5Port
        self.httpPort = httpPort
        self.proxyMode = proxyMode
        self.allowDirectFallback = allowDirectFallback
        self.noProxy = noProxy
        self.launchAtLogin = launchAtLogin
        self.vpnKeepaliveEnabled = vpnKeepaliveEnabled
        self.vpnKeepaliveURL = vpnKeepaliveURL
        self.vpnKeepaliveIntervalSeconds = vpnKeepaliveIntervalSeconds
        self.vpnKeepaliveTimeoutSeconds = vpnKeepaliveTimeoutSeconds
        self.refreshVersion = refreshVersion
    }

    private enum CodingKeys: String, CodingKey {
        case pacPath
        case recentPACPaths
        case pacServerPort
        case proxyHost
        case socks5Port
        case httpPort
        case proxyMode
        case allowDirectFallback
        case noProxy
        case launchAtLogin
        case vpnKeepaliveEnabled
        case vpnKeepaliveURL
        case vpnKeepaliveIntervalSeconds
        case vpnKeepaliveTimeoutSeconds
        case refreshVersion
    }

    public init(from decoder: Decoder) throws {
        let defaults = CNPacSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pacPath: try container.decodeIfPresent(String.self, forKey: .pacPath),
            recentPACPaths: try container.decodeIfPresent([String].self, forKey: .recentPACPaths) ?? defaults.recentPACPaths,
            pacServerPort: try container.decodeIfPresent(Int.self, forKey: .pacServerPort) ?? defaults.pacServerPort,
            proxyHost: try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? defaults.proxyHost,
            socks5Port: try container.decodeIfPresent(Int.self, forKey: .socks5Port) ?? defaults.socks5Port,
            httpPort: try container.decodeIfPresent(Int.self, forKey: .httpPort) ?? defaults.httpPort,
            proxyMode: try container.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) ?? defaults.proxyMode,
            allowDirectFallback: try container.decodeIfPresent(Bool.self, forKey: .allowDirectFallback) ?? defaults.allowDirectFallback,
            noProxy: try container.decodeIfPresent(String.self, forKey: .noProxy) ?? defaults.noProxy,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin,
            vpnKeepaliveEnabled: try container.decodeIfPresent(Bool.self, forKey: .vpnKeepaliveEnabled) ?? defaults.vpnKeepaliveEnabled,
            vpnKeepaliveURL: try container.decodeIfPresent(String.self, forKey: .vpnKeepaliveURL) ?? defaults.vpnKeepaliveURL,
            vpnKeepaliveIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .vpnKeepaliveIntervalSeconds) ?? defaults.vpnKeepaliveIntervalSeconds,
            vpnKeepaliveTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .vpnKeepaliveTimeoutSeconds) ?? defaults.vpnKeepaliveTimeoutSeconds,
            refreshVersion: try container.decodeIfPresent(Int.self, forKey: .refreshVersion) ?? defaults.refreshVersion
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(pacPath, forKey: .pacPath)
        try container.encode(recentPACPaths, forKey: .recentPACPaths)
        try container.encode(pacServerPort, forKey: .pacServerPort)
        try container.encode(proxyHost, forKey: .proxyHost)
        try container.encode(socks5Port, forKey: .socks5Port)
        try container.encode(httpPort, forKey: .httpPort)
        try container.encode(proxyMode, forKey: .proxyMode)
        try container.encode(allowDirectFallback, forKey: .allowDirectFallback)
        try container.encode(noProxy, forKey: .noProxy)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(vpnKeepaliveEnabled, forKey: .vpnKeepaliveEnabled)
        try container.encode(vpnKeepaliveURL, forKey: .vpnKeepaliveURL)
        try container.encode(vpnKeepaliveIntervalSeconds, forKey: .vpnKeepaliveIntervalSeconds)
        try container.encode(vpnKeepaliveTimeoutSeconds, forKey: .vpnKeepaliveTimeoutSeconds)
        try container.encode(refreshVersion, forKey: .refreshVersion)
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

    public var terminalProxyCommand: String {
        let primaryProxy = terminalPrimaryProxyURL.zshSingleQuoted()
        let allProxy = terminalAllProxyURL.zshSingleQuoted()
        let noProxyValue = noProxy.zshSingleQuoted()
        return [
            "export HTTP_PROXY=\(primaryProxy)",
            "export HTTPS_PROXY=\"$HTTP_PROXY\"",
            "export http_proxy=\"$HTTP_PROXY\"",
            "export https_proxy=\"$HTTP_PROXY\"",
            "export ALL_PROXY=\(allProxy)",
            "export all_proxy=\"$ALL_PROXY\"",
            "export FTP_PROXY=\"$HTTP_PROXY\"",
            "export ftp_proxy=\"$FTP_PROXY\"",
            "export grpc_proxy=\"$HTTP_PROXY\"",
            "export NO_PROXY=\(noProxyValue)",
            "export no_proxy=\"$NO_PROXY\""
        ].joined(separator: "\n")
    }

    private var terminalPrimaryProxyURL: String {
        switch proxyMode {
        case .socks5:
            return socksProxyURL
        case .http, .socks5AndHTTP:
            return httpProxyURL
        }
    }

    private var terminalAllProxyURL: String {
        switch proxyMode {
        case .socks5, .socks5AndHTTP:
            return socksProxyURL
        case .http:
            return httpProxyURL
        }
    }

    private var socksProxyURL: String {
        "socks5h://\(proxyHost):\(socks5Port)"
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

    public var proxyFailureBehaviorSummary: String {
        allowDirectFallback ? "DIRECT fallback allowed" : "No DIRECT fallback"
    }

    public var pacProxyExpression: String {
        var rules: [String]
        switch proxyMode {
        case .socks5:
            rules = ["SOCKS5 \(proxyHost):\(socks5Port)"]
        case .http:
            rules = ["PROXY \(proxyHost):\(httpPort)"]
        case .socks5AndHTTP:
            rules = [
                "SOCKS5 \(proxyHost):\(socks5Port)",
                "PROXY \(proxyHost):\(httpPort)"
            ]
        }
        if allowDirectFallback {
            rules.append("DIRECT")
        }
        return rules.joined(separator: "; ")
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
