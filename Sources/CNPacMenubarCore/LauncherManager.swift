import Foundation

public struct LauncherBuildInput: Equatable, Sendable {
    public var targetAppPath: String
    public var targetExecutablePath: String
    public var settingsPath: String
    public var profile: LauncherProfile

    public init(targetAppPath: String, targetExecutablePath: String, settingsPath: String, profile: LauncherProfile = .environment) {
        self.targetAppPath = targetAppPath
        self.targetExecutablePath = targetExecutablePath
        self.settingsPath = settingsPath
        self.profile = profile
    }
}

public enum LauncherScriptBuilder {
    public static func script(input: LauncherBuildInput) -> String {
        """
        #!/bin/zsh
        set -u

        SETTINGS_FILE=\(input.settingsPath.zshSingleQuoted())
        TARGET_APP=\(input.targetAppPath.zshSingleQuoted())
        TARGET_EXECUTABLE=\(input.targetExecutablePath.zshSingleQuoted())
        LAUNCHER_PROFILE=\(input.profile.rawValue.zshSingleQuoted())

        read_json() {
          /usr/bin/plutil -extract "$1" raw -o - "$SETTINGS_FILE" 2>/dev/null || printf "%s" "$2"
        }

        proxy_host="$(read_json proxyHost "127.0.0.1")"
        socks5_port="$(read_json socks5Port "1080")"
        http_port="$(read_json httpPort "8080")"
        proxy_mode="$(read_json proxyMode "socks5AndHTTP")"
        no_proxy="$(read_json noProxy "127.0.0.1,localhost,::1")"

        http_proxy_url="http://${proxy_host}:${http_port}"
        socks_proxy_url="socks5h://${proxy_host}:${socks5_port}"

        case "$proxy_mode" in
          socks5)
            primary_proxy="$socks_proxy_url"
            all_proxy="$socks_proxy_url"
            chromium_proxy_url="socks5://${proxy_host}:${socks5_port}"
            ;;
          socks5AndHTTP)
            primary_proxy="$http_proxy_url"
            all_proxy="$socks_proxy_url"
            chromium_proxy_url="$http_proxy_url"
            ;;
          *)
            primary_proxy="$http_proxy_url"
            all_proxy="$http_proxy_url"
            chromium_proxy_url="$http_proxy_url"
            ;;
        esac

        export HTTP_PROXY="$primary_proxy"
        export HTTPS_PROXY="$HTTP_PROXY"
        export http_proxy="$HTTP_PROXY"
        export https_proxy="$HTTP_PROXY"
        export ALL_PROXY="$all_proxy"
        export all_proxy="$ALL_PROXY"
        export FTP_PROXY="$primary_proxy"
        export ftp_proxy="$FTP_PROXY"
        export grpc_proxy="$primary_proxy"
        export NO_PROXY="$no_proxy"
        export no_proxy="$NO_PROXY"

        args=("$@")
        case "$LAUNCHER_PROFILE" in
          chromium)
            chromium_bypass_list="$(printf "%s" "$no_proxy" | /usr/bin/sed 's/,/;/g')"
            args=("--proxy-server=${chromium_proxy_url}" "--proxy-bypass-list=${chromium_bypass_list}" "$@")
            ;;
          java)
            java_no_proxy="$(printf "%s" "$no_proxy" | /usr/bin/sed -e 's/[[:space:]]//g' -e 's/,/|/g')"
            if [ "$proxy_mode" = "socks5" ]; then
              java_proxy_options="-DsocksProxyHost=${proxy_host} -DsocksProxyPort=${socks5_port} -Dhttp.nonProxyHosts=${java_no_proxy}"
            else
              java_proxy_options="-Dhttp.proxyHost=${proxy_host} -Dhttp.proxyPort=${http_port} -Dhttps.proxyHost=${proxy_host} -Dhttps.proxyPort=${http_port} -Dhttp.nonProxyHosts=${java_no_proxy}"
            fi
            if [ -n "${JAVA_TOOL_OPTIONS:-}" ]; then
              export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} ${java_proxy_options}"
            else
              export JAVA_TOOL_OPTIONS="$java_proxy_options"
            fi
            ;;
        esac

        exec "$TARGET_EXECUTABLE" "${args[@]}"
        """
    }
}

public struct ProxyLaunchConfiguration: Equatable, Sendable {
    public var environment: [String: String]
    public var arguments: [String]

    public init(
        settings: CNPacSettings,
        profile: LauncherProfile,
        baseEnvironment: [String: String] = [:]
    ) {
        let httpProxyURL = "http://\(settings.proxyHost):\(settings.httpPort)"
        let socksProxyURL = "socks5h://\(settings.proxyHost):\(settings.socks5Port)"

        let primaryProxy: String
        let allProxy: String
        let chromiumProxyURL: String
        switch settings.proxyMode {
        case .socks5:
            primaryProxy = socksProxyURL
            allProxy = socksProxyURL
            chromiumProxyURL = "socks5://\(settings.proxyHost):\(settings.socks5Port)"
        case .socks5AndHTTP:
            primaryProxy = httpProxyURL
            allProxy = socksProxyURL
            chromiumProxyURL = httpProxyURL
        case .http:
            primaryProxy = httpProxyURL
            allProxy = httpProxyURL
            chromiumProxyURL = httpProxyURL
        }

        var environment = baseEnvironment
        environment["HTTP_PROXY"] = primaryProxy
        environment["HTTPS_PROXY"] = primaryProxy
        environment["http_proxy"] = primaryProxy
        environment["https_proxy"] = primaryProxy
        environment["ALL_PROXY"] = allProxy
        environment["all_proxy"] = allProxy
        environment["FTP_PROXY"] = primaryProxy
        environment["ftp_proxy"] = primaryProxy
        environment["grpc_proxy"] = primaryProxy
        environment["NO_PROXY"] = settings.noProxy
        environment["no_proxy"] = settings.noProxy

        var arguments: [String] = []
        switch profile {
        case .chromium:
            let chromiumBypassList = settings.noProxy.replacingOccurrences(of: ",", with: ";")
            arguments = [
                "--proxy-server=\(chromiumProxyURL)",
                "--proxy-bypass-list=\(chromiumBypassList)"
            ]
        case .java:
            let javaNoProxy = settings.noProxy
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ",", with: "|")
            let javaProxyOptions: String
            if settings.proxyMode == .socks5 {
                javaProxyOptions = "-DsocksProxyHost=\(settings.proxyHost) -DsocksProxyPort=\(settings.socks5Port) -Dhttp.nonProxyHosts=\(javaNoProxy)"
            } else {
                javaProxyOptions = "-Dhttp.proxyHost=\(settings.proxyHost) -Dhttp.proxyPort=\(settings.httpPort) -Dhttps.proxyHost=\(settings.proxyHost) -Dhttps.proxyPort=\(settings.httpPort) -Dhttp.nonProxyHosts=\(javaNoProxy)"
            }
            if let existingOptions = environment["JAVA_TOOL_OPTIONS"], !existingOptions.isEmpty {
                environment["JAVA_TOOL_OPTIONS"] = "\(existingOptions) \(javaProxyOptions)"
            } else {
                environment["JAVA_TOOL_OPTIONS"] = javaProxyOptions
            }
        case .environment, .systemProxyPreferred:
            break
        }

        self.environment = environment
        self.arguments = arguments
    }
}

public final class LauncherManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let store: SettingsStore

    public init(store: SettingsStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public func createLauncher(targetAppURL: URL, destinationDirectory: URL) throws -> LauncherRecord {
        let targetExecutableURL = try Self.executableURL(forApp: targetAppURL)
        let profile = try Self.suggestedProfile(forApp: targetAppURL)
        let displayName = targetAppURL.deletingPathExtension().lastPathComponent
        let launcherName = "\(displayName) Proxy.app"
        let launcherURL = destinationDirectory.appendingPathComponent(launcherName, isDirectory: true)
        let contentsURL = launcherURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let launcherExecutableURL = macOSURL.appendingPathComponent("launcher")

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let iconFileName = try copyIconResource(fromApp: targetAppURL, to: resourcesURL)

        let script = LauncherScriptBuilder.script(input: LauncherBuildInput(
            targetAppPath: targetAppURL.path,
            targetExecutablePath: targetExecutableURL.path,
            settingsPath: store.settingsURL.path,
            profile: profile
        ))
        try script.write(to: launcherExecutableURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherExecutableURL.path)

        let bundleIdentifier = try Self.bundleIdentifier(forApp: targetAppURL)
        let info = makeInfoPlist(
            displayName: "\(displayName) Proxy",
            launcherExecutable: "launcher",
            bundleIdentifier: Self.launcherBundleIdentifier(targetBundleIdentifier: bundleIdentifier, launcherURL: launcherURL),
            targetAppPath: targetAppURL.path,
            profile: profile,
            iconFileName: iconFileName
        )
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"), options: [.atomic])

        return LauncherRecord(
            displayName: "\(displayName) Proxy",
            targetAppPath: targetAppURL.path,
            launcherAppPath: launcherURL.path,
            bundleIdentifier: bundleIdentifier,
            launcherProfile: profile,
            managedByTool: true
        )
    }

    public func refreshManagedLaunchers() throws -> LauncherIndex {
        var index = store.loadLauncherIndex()
        index.launchers = index.launchers.compactMap { record in
            guard fileManager.fileExists(atPath: record.launcherAppPath) else {
                return nil
            }

            let launcherURL = URL(fileURLWithPath: record.launcherAppPath, isDirectory: true)
            guard let managedRecord = try? Self.identifyManagedLauncher(at: launcherURL) else {
                return record
            }

            return LauncherRecord(
                id: record.id,
                displayName: managedRecord.displayName,
                targetAppPath: managedRecord.targetAppPath,
                launcherAppPath: managedRecord.launcherAppPath,
                bundleIdentifier: managedRecord.bundleIdentifier,
                launcherProfile: managedRecord.launcherProfile,
                createdAt: record.createdAt,
                lastLaunchedAt: record.lastLaunchedAt,
                managedByTool: managedRecord.managedByTool
            )
        }
        index.launchers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        try store.saveLauncherIndex(index)
        return index
    }

    public func removeFromIndex(launcherPath: String) throws -> LauncherIndex {
        var index = store.loadLauncherIndex()
        index.remove(path: launcherPath)
        try store.saveLauncherIndex(index)
        return index
    }

    public static func identifyManagedLauncher(at appURL: URL) throws -> LauncherRecord? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        guard let targetPath = info["CNPacTargetAppPath"] as? String else {
            return nil
        }
        let profile = (info["CNPacLauncherProfile"] as? String).flatMap(LauncherProfile.init(rawValue:))
        return LauncherRecord(
            displayName: name,
            targetAppPath: targetPath,
            launcherAppPath: appURL.path,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            launcherProfile: profile,
            managedByTool: true
        )
    }

    public static func suggestedProfile(forApp appURL: URL) throws -> LauncherProfile {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return .environment
        }

        let bundleIdentifier = (info["CFBundleIdentifier"] as? String)?.lowercased() ?? ""
        if bundleIdentifier == "com.apple.safari" || bundleIdentifier.hasPrefix("com.apple.") {
            return .systemProxyPreferred
        }

        if isChromiumFamily(appURL: appURL, info: info) {
            return .chromium
        }

        if isJavaApp(appURL: appURL, info: info) {
            return .java
        }

        return .environment
    }

    public static func executableURL(forApp appURL: URL) throws -> URL {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let executableName = info["CFBundleExecutable"] as? String else {
            throw LauncherError.missingExecutable(appURL.path)
        }
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw LauncherError.missingExecutable(executableURL.path)
        }
        return executableURL
    }

    public static func bundleIdentifier(forApp appURL: URL) throws -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }
        return info["CFBundleIdentifier"] as? String
    }

    private static func isChromiumFamily(appURL: URL, info: [String: Any]) -> Bool {
        if info["ElectronAsarIntegrity"] != nil {
            return true
        }

        let bundleIdentifier = (info["CFBundleIdentifier"] as? String)?.lowercased() ?? ""
        let executable = (info["CFBundleExecutable"] as? String)?.lowercased() ?? ""
        let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()
        let markers = ["electron", "chromium", "cef", "qtwebengine"]
        if markers.contains(where: { bundleIdentifier.contains($0) || executable.contains($0) || appName.contains($0) }) {
            return true
        }

        let markerPaths = [
            "Contents/Resources/app.asar",
            "Contents/Frameworks/Electron Framework.framework",
            "Contents/Frameworks/Chromium Embedded Framework.framework",
            "Contents/Frameworks/QtWebEngineCore.framework",
            "Contents/Frameworks/QtWebEngineWidgets.framework"
        ]
        return markerPaths.contains { FileManager.default.fileExists(atPath: appURL.appendingPathComponent($0).path) }
    }

    private static func isJavaApp(appURL: URL, info: [String: Any]) -> Bool {
        if info["JVMOptions"] != nil || info["JVMRuntime"] != nil || info["Java"] != nil {
            return true
        }

        let bundleIdentifier = (info["CFBundleIdentifier"] as? String)?.lowercased() ?? ""
        let executable = (info["CFBundleExecutable"] as? String)?.lowercased() ?? ""
        if bundleIdentifier.contains("jetbrains") || executable.contains("java") || executable.contains("jdk") {
            return true
        }

        let markerPaths = [
            "Contents/Info.plist/Java",
            "Contents/MacOS/JavaAppLauncher",
            "Contents/PlugIns/jre",
            "Contents/PlugIns/jdk",
            "Contents/runtime"
        ]
        return markerPaths.contains { FileManager.default.fileExists(atPath: appURL.appendingPathComponent($0).path) }
    }

    private func copyIconResource(fromApp appURL: URL, to resourcesURL: URL) throws -> String? {
        guard let iconURL = Self.iconResourceURL(forApp: appURL, fileManager: fileManager) else {
            return nil
        }

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let destinationURL = resourcesURL.appendingPathComponent(iconURL.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: iconURL, to: destinationURL)
        return destinationURL.lastPathComponent
    }

    private static func iconResourceURL(forApp appURL: URL, fileManager: FileManager) -> URL? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }

        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        for iconName in iconResourceCandidates(from: info) {
            for fileName in iconFileNameVariants(iconName) {
                let iconURL = resourcesURL.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: iconURL.path) {
                    return iconURL
                }
            }
        }
        return nil
    }

    private static func iconResourceCandidates(from info: [String: Any]) -> [String] {
        var candidates: [String] = []
        if let iconFile = info["CFBundleIconFile"] as? String {
            candidates.append(iconFile)
        }
        if let iconName = info["CFBundleIconName"] as? String {
            candidates.append(iconName)
        }
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: iconFiles.reversed())
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                return false
            }
            seen.insert(trimmed)
            return true
        }
    }

    private static func iconFileNameVariants(_ iconName: String) -> [String] {
        let fileName = URL(fileURLWithPath: iconName.trimmingCharacters(in: .whitespacesAndNewlines)).lastPathComponent
        guard !fileName.isEmpty else {
            return []
        }
        if (fileName as NSString).pathExtension.isEmpty {
            return ["\(fileName).icns", fileName]
        }
        return [fileName]
    }

    private func makeInfoPlist(displayName: String, launcherExecutable: String, bundleIdentifier: String, targetAppPath: String, profile: LauncherProfile, iconFileName: String?) -> [String: Any] {
        var info: [String: Any] = [
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": launcherExecutable,
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "13.0",
            "CNPacMenubarManaged": true,
            "CNPacTargetAppPath": targetAppPath,
            "CNPacLauncherProfile": profile.rawValue,
            "CNPacSettingsPath": store.settingsURL.path
        ]
        if let iconFileName {
            info["CFBundleIconFile"] = iconFileName
        }
        return info
    }

    private static func launcherBundleIdentifier(targetBundleIdentifier: String?, launcherURL: URL) -> String {
        let base = (targetBundleIdentifier ?? launcherURL.deletingPathExtension().lastPathComponent)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9.]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return "local.cn-pac-menubar.launcher.\(base).\(UUID().uuidString.prefix(8).lowercased())"
    }

}

public enum LauncherError: LocalizedError, Equatable {
    case missingExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable(let path):
            return "Unable to find app executable at \(path)."
        }
    }
}

extension String {
    func zshSingleQuoted() -> String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
