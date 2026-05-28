import XCTest
import Network
@testable import CNPacMenubarCore

final class CNPacMenubarCoreTests: XCTestCase {
    func testProxyExpressions() {
        var settings = CNPacSettings(proxyHost: "192.168.1.103", socks5Port: 1080, httpPort: 8080, proxyMode: .socks5AndHTTP)
        XCTAssertEqual(settings.pacProxyExpression, "SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080")
        XCTAssertEqual(settings.proxyFailureBehaviorSummary, "No DIRECT fallback")

        settings.proxyMode = .http
        XCTAssertEqual(settings.pacProxyExpression, "PROXY 192.168.1.103:8080")

        settings.proxyMode = .socks5
        XCTAssertEqual(settings.pacProxyExpression, "SOCKS5 192.168.1.103:1080")
    }

    func testProxyExpressionsCanAllowDirectFallback() {
        var settings = CNPacSettings(
            proxyHost: "192.168.1.103",
            socks5Port: 1080,
            httpPort: 8080,
            proxyMode: .socks5AndHTTP,
            allowDirectFallback: true
        )
        XCTAssertEqual(settings.pacProxyExpression, "SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080; DIRECT")
        XCTAssertEqual(settings.proxyFailureBehaviorSummary, "DIRECT fallback allowed")

        settings.proxyMode = .http
        XCTAssertEqual(settings.pacProxyExpression, "PROXY 192.168.1.103:8080; DIRECT")

        settings.proxyMode = .socks5
        XCTAssertEqual(settings.pacProxyExpression, "SOCKS5 192.168.1.103:1080; DIRECT")
    }

    func testPACURLCanUseLoopbackOrLANHost() {
        let settings = CNPacSettings(pacServerPort: 8123, refreshVersion: 42)

        XCTAssertEqual(settings.pacURL.absoluteString, "http://127.0.0.1:8123/proxy.pac?v=42")
        XCTAssertEqual(settings.pacURL(host: "192.168.1.103").absoluteString, "http://192.168.1.103:8123/proxy.pac?v=42")
    }

    func testProxySummariesShowActiveProtocolAndPorts() {
        var settings = CNPacSettings(proxyHost: "127.0.0.1", socks5Port: 1080, httpPort: 8080, proxyMode: .socks5AndHTTP)
        XCTAssertEqual(settings.proxyEndpointSummary, "SOCKS5 127.0.0.1:1080 + HTTP 127.0.0.1:8080")
        XCTAssertEqual(settings.proxyCompactSummary, "SOCKS5:1080 + HTTP:8080")
        XCTAssertEqual(settings.proxyStatusBarSummary, "S5:1080 H:8080")

        settings.proxyMode = .http
        XCTAssertEqual(settings.proxyEndpointSummary, "HTTP 127.0.0.1:8080")
        XCTAssertEqual(settings.proxyStatusBarSummary, "H:8080")

        settings.proxyHost = "192.168.1.103"
        settings.proxyMode = .socks5
        XCTAssertEqual(settings.proxyCompactSummary, "192.168.1.103 SOCKS5:1080")
        XCTAssertEqual(settings.proxyStatusBarSummary, "192.168.1.103 S5:1080")
    }

    func testTerminalProxyCommandUsesConfiguredProxyMode() {
        var settings = CNPacSettings(
            proxyHost: "192.168.1.103",
            socks5Port: 1080,
            httpPort: 8080,
            proxyMode: .socks5AndHTTP,
            noProxy: "127.0.0.1,localhost,::1"
        )

        XCTAssertTrue(settings.terminalProxyCommand.contains("export HTTP_PROXY='http://192.168.1.103:8080'"))
        XCTAssertTrue(settings.terminalProxyCommand.contains("export ALL_PROXY='socks5h://192.168.1.103:1080'"))
        XCTAssertTrue(settings.terminalProxyCommand.contains("export no_proxy=\"$NO_PROXY\""))
        XCTAssertTrue(settings.terminalProxyCommand.contains("export NO_PROXY='127.0.0.1,localhost,::1'"))

        settings.proxyMode = .socks5
        XCTAssertTrue(settings.terminalProxyCommand.contains("export HTTP_PROXY='socks5h://192.168.1.103:1080'"))
        XCTAssertTrue(settings.terminalProxyCommand.contains("export ALL_PROXY='socks5h://192.168.1.103:1080'"))

        settings.proxyMode = .http
        XCTAssertTrue(settings.terminalProxyCommand.contains("export HTTP_PROXY='http://192.168.1.103:8080'"))
        XCTAssertTrue(settings.terminalProxyCommand.contains("export ALL_PROXY='http://192.168.1.103:8080'"))
    }

    func testSettingsDecodeBackfillsVPNKeepaliveDefaults() throws {
        let data = """
        {
          "pacServerPort": 8123,
          "proxyHost": "192.168.1.103",
          "socks5Port": 1080,
          "httpPort": 8080,
          "proxyMode": "socks5AndHTTP",
          "noProxy": "127.0.0.1,localhost,::1",
          "launchAtLogin": true,
          "refreshVersion": 7
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CNPacSettings.self, from: data)

        XCTAssertEqual(settings.pacServerPort, 8123)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertFalse(settings.allowDirectFallback)
        XCTAssertFalse(settings.vpnKeepaliveEnabled)
        XCTAssertEqual(settings.vpnKeepaliveURL, CNPacSettings.defaultVPNKeepaliveURL)
        XCTAssertEqual(settings.vpnKeepaliveIntervalSeconds, 300)
        XCTAssertEqual(settings.vpnKeepaliveTimeoutSeconds, 10)
    }

    func testVPNKeepaliveConfigurationValidatesURLAndTiming() {
        var settings = CNPacSettings(
            pacPath: "/tmp/proxy.pac",
            vpnKeepaliveEnabled: true,
            vpnKeepaliveURL: " https://example.com/ping ",
            vpnKeepaliveIntervalSeconds: 5,
            vpnKeepaliveTimeoutSeconds: 999
        )

        let configuration = VPNKeepaliveConfiguration(settings: settings)
        XCTAssertEqual(configuration?.url.absoluteString, "https://example.com/ping")
        XCTAssertEqual(configuration?.pacPath, "/tmp/proxy.pac")
        XCTAssertEqual(configuration?.intervalSeconds, VPNKeepaliveConfiguration.minimumIntervalSeconds)
        XCTAssertEqual(configuration?.timeoutSeconds, VPNKeepaliveConfiguration.maximumTimeoutSeconds)

        settings.vpnKeepaliveURL = "ftp://example.com/ping"
        XCTAssertNil(VPNKeepaliveConfiguration(settings: settings))

        settings.vpnKeepaliveEnabled = false
        settings.vpnKeepaliveURL = CNPacSettings.defaultVPNKeepaliveURL
        XCTAssertNil(VPNKeepaliveConfiguration(settings: settings))
    }

    func testPACProxyResolverUsesFirstProxyDirectiveAndRejectsDirect() throws {
        let endpoint = try PACProxyResolver.firstProxy(from: "SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080; DIRECT;")

        XCTAssertEqual(endpoint, PACProxyEndpoint(kind: .socks5, host: "192.168.1.103", port: 1080))
        XCTAssertEqual(endpoint.displayName, "SOCKS5 192.168.1.103:1080")

        XCTAssertThrowsError(try PACProxyResolver.firstProxy(from: "DIRECT; PROXY 192.168.1.103:8080;")) { error in
            XCTAssertEqual(error as? PACProxyResolverError, .directSelected)
        }
    }

    func testPACProxyResolverEvaluatesSelectedPACForTargetURL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pacURL = root.appendingPathComponent("proxy.pac")
        try """
        function FindProxyForURL(url, host) {
          if (dnsDomainIs(host, "gstatic.com")) {
            return "SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080; DIRECT;";
          }
          return "DIRECT";
        }
        """.write(to: pacURL, atomically: true, encoding: .utf8)

        let googleURL = try XCTUnwrap(URL(string: "https://www.gstatic.com/generate_204"))
        let endpoint = try PACProxyResolver.firstProxy(for: googleURL, pacPath: pacURL.path)
        XCTAssertEqual(endpoint, PACProxyEndpoint(kind: .socks5, host: "192.168.1.103", port: 1080))

        let directURL = try XCTUnwrap(URL(string: "https://example.cn/"))
        XCTAssertThrowsError(try PACProxyResolver.firstProxy(for: directURL, pacPath: pacURL.path)) { error in
            XCTAssertEqual(error as? PACProxyResolverError, .directSelected)
        }
    }

    func testVPNKeepaliveStatusDetailShowsClockTimesWithoutStaleCountdown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 15,
            hour: 23,
            minute: 3,
            second: 9
        )))
        let nextRun = try XCTUnwrap(calendar.date(byAdding: .minute, value: 5, to: now))
        let status = VPNKeepaliveStatus(
            isEnabled: true,
            isRunning: false,
            nextRun: nextRun,
            lastResult: .success(completedAt: now, statusCode: 204, durationMilliseconds: 2351)
        )
        let running = VPNKeepaliveStatus(
            isEnabled: true,
            isRunning: true,
            lastStartedAt: now
        )

        XCTAssertEqual(status.detail, "HTTP 204 at 23:03:09 (2351 ms); next at 23:08:09")
        XCTAssertEqual(running.detail, "Request in progress since 23:03:09")
    }

    func testPACServerStateDetails() {
        XCTAssertFalse(PACServerState.stopped.isActive)
        XCTAssertEqual(PACServerState.stopped.detail, "Stopped")
        XCTAssertTrue(PACServerState.starting(port: 8118).isActive)
        XCTAssertFalse(PACServerState.starting(port: 8118).isRunning)
        XCTAssertTrue(PACServerState.running(port: 8118).isRunning)
        XCTAssertEqual(PACServerState.running(port: 8118).detail, "Running on all interfaces:8118")
        XCTAssertEqual(PACServerState.failed(port: 8118, message: "address in use").displayName, "Failed")
    }

    func testPACServerListenerParametersAllowLANAccess() {
        let parameters = PACServer.listenerParameters()

        XCTAssertNil(parameters.requiredLocalEndpoint)
        XCTAssertFalse(parameters.acceptLocalOnly)
    }

    func testPACRewriterReplacesGeneratedProxyReturns() {
        let pac = """
        function FindProxyForURL(url, host) {
          if (isProxyDomain(host)) {
            return "SOCKS5 127.0.0.1:%mixed-port%; PROXY 127.0.0.1:%mixed-port%; DIRECT;";
          }
          return "DIRECT";
        }
        """
        let settings = CNPacSettings(proxyHost: "192.168.1.103", socks5Port: 1080, httpPort: 8080, proxyMode: .socks5AndHTTP)
        let result = PACRewriter.rewrite(pac, settings: settings)
        XCTAssertTrue(result.changedProxyRules)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.content.contains("SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080"))
        XCTAssertFalse(result.content.contains("SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080; DIRECT"))
        XCTAssertFalse(result.content.contains("%mixed-port%"))
        XCTAssertTrue(result.content.contains("return \"DIRECT\";"))
    }

    func testPACRewriterCanKeepDirectFallbackWhenEnabled() {
        let pac = """
        function FindProxyForURL(url, host) {
          return "SOCKS5 127.0.0.1:%mixed-port%; PROXY 127.0.0.1:%mixed-port%; DIRECT;";
        }
        """
        let settings = CNPacSettings(
            proxyHost: "192.168.1.103",
            socks5Port: 1080,
            httpPort: 8080,
            proxyMode: .socks5AndHTTP,
            allowDirectFallback: true
        )
        let result = PACRewriter.rewrite(pac, settings: settings)

        XCTAssertTrue(result.changedProxyRules)
        XCTAssertTrue(result.content.contains("SOCKS5 192.168.1.103:1080; PROXY 192.168.1.103:8080; DIRECT"))
    }

    func testPACRewriterWarnsWhenNoSafeRuleFound() {
        let pac = "function FindProxyForURL(url, host) { return \"DIRECT\"; }"
        let result = PACRewriter.rewrite(pac, settings: CNPacSettings())
        XCTAssertFalse(result.changedProxyRules)
        XCTAssertEqual(result.content, pac)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testNetworkServiceParserSkipsHeaderAndDisabledServices() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        *Thunderbolt Bridge
        USB 10/100/1000 LAN

        """
        XCTAssertEqual(NetworkServiceParser.enabledServices(from: output), ["Wi-Fi", "USB 10/100/1000 LAN"])
    }

    func testPACServerPathIgnoresQuery() {
        let request = "GET /proxy.pac?v=12 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        XCTAssertEqual(PACServer.path(fromHTTPRequest: request), "/proxy.pac")
    }

    func testLauncherScriptReadsSharedSettingsAndAddsChromiumProxySupport() {
        let script = LauncherScriptBuilder.script(input: LauncherBuildInput(
            targetAppPath: "/Applications/Codex.app",
            targetExecutablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
            settingsPath: "/Users/wsy/Library/Application Support/cn-pac-menubar/settings.json",
            profile: .chromium
        ))
        XCTAssertTrue(script.contains("plutil -extract"))
        XCTAssertTrue(script.contains("HTTP_PROXY"))
        XCTAssertTrue(script.contains("ALL_PROXY"))
        XCTAssertTrue(script.contains("FTP_PROXY"))
        XCTAssertTrue(script.contains("grpc_proxy"))
        XCTAssertTrue(script.contains("--proxy-server=${chromium_proxy_url}"))
        XCTAssertTrue(script.contains("--proxy-bypass-list=${chromium_bypass_list}"))
        XCTAssertTrue(script.contains("exec \"$TARGET_EXECUTABLE\" \"${args[@]}\""))
        XCTAssertTrue(script.contains("Application Support"))
    }

    func testLauncherScriptAddsJavaProxyOptions() {
        let script = LauncherScriptBuilder.script(input: LauncherBuildInput(
            targetAppPath: "/Applications/JavaTool.app",
            targetExecutablePath: "/Applications/JavaTool.app/Contents/MacOS/JavaTool",
            settingsPath: "/Users/wsy/Library/Application Support/cn-pac-menubar/settings.json",
            profile: .java
        ))

        XCTAssertTrue(script.contains("JAVA_TOOL_OPTIONS"))
        XCTAssertTrue(script.contains("-Dhttp.proxyHost=${proxy_host}"))
        XCTAssertTrue(script.contains("-DsocksProxyHost=${proxy_host}"))
    }

    func testManagedLauncherIdentificationReadsOnlyPlistMetadata() throws {
        let launcher = try makeTestApp(
            name: "Codex Proxy.app",
            info: [
                "CFBundleDisplayName": "Codex Proxy",
                "CFBundleExecutable": "launcher",
                "CFBundleIdentifier": "local.cn-pac-menubar.launcher.codex",
                "CNPacTargetAppPath": "/Applications/Codex.app",
                "CNPacLauncherProfile": "chromium"
            ]
        )
        defer { try? FileManager.default.removeItem(at: launcher.deletingLastPathComponent()) }

        let record = try XCTUnwrap(try LauncherManager.identifyManagedLauncher(at: launcher))
        XCTAssertEqual(record.displayName, "Codex Proxy")
        XCTAssertEqual(record.targetAppPath, "/Applications/Codex.app")
        XCTAssertEqual(record.launcherAppPath, launcher.path)
        XCTAssertEqual(record.bundleIdentifier, "local.cn-pac-menubar.launcher.codex")
        XCTAssertEqual(record.launcherProfile, .chromium)
        XCTAssertTrue(record.managedByTool)
    }

    func testLegacyScriptWrapperIsNotAutoIdentified() throws {
        let launcher = try makeTestApp(
            name: "Legacy Proxy.app",
            info: [
                "CFBundleExecutable": "launcher",
                "CFBundleIdentifier": "local.legacy.proxy"
            ]
        )
        defer { try? FileManager.default.removeItem(at: launcher.deletingLastPathComponent()) }

        let executableURL = launcher.appendingPathComponent("Contents/MacOS/launcher")
        try """
        #!/bin/zsh
        export HTTP_PROXY=http://192.168.1.103:8080
        exec /Applications/Codex.app/Contents/MacOS/Codex "$@"
        """.write(to: executableURL, atomically: true, encoding: .utf8)

        XCTAssertNil(try LauncherManager.identifyManagedLauncher(at: launcher))
    }

    func testSuggestedProfileDetectsElectronAndSafari() throws {
        let electronApp = try makeTestApp(
            name: "Codex.app",
            info: [
                "CFBundleExecutable": "Codex",
                "CFBundleIdentifier": "com.openai.codex",
                "ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256"]]
            ]
        )
        defer { try? FileManager.default.removeItem(at: electronApp.deletingLastPathComponent()) }

        XCTAssertEqual(try LauncherManager.suggestedProfile(forApp: electronApp), .chromium)

        let safariApp = try makeTestApp(
            name: "Safari.app",
            info: [
                "CFBundleExecutable": "Safari",
                "CFBundleIdentifier": "com.apple.Safari"
            ]
        )
        defer { try? FileManager.default.removeItem(at: safariApp.deletingLastPathComponent()) }

        XCTAssertEqual(try LauncherManager.suggestedProfile(forApp: safariApp), .systemProxyPreferred)
    }

    func testSuggestedProfileDetectsJavaApps() throws {
        let javaApp = try makeTestApp(
            name: "JavaTool.app",
            info: [
                "CFBundleExecutable": "JavaTool",
                "CFBundleIdentifier": "com.example.JavaTool",
                "JVMOptions": ["-Xmx2g"]
            ]
        )
        defer { try? FileManager.default.removeItem(at: javaApp.deletingLastPathComponent()) }

        XCTAssertEqual(try LauncherManager.suggestedProfile(forApp: javaApp), .java)
    }

    func testCreateLauncherCopiesTargetAppIcon() throws {
        let app = try makeTestApp(
            name: "Iconic.app",
            info: [
                "CFBundleExecutable": "Iconic",
                "CFBundleIdentifier": "com.example.Iconic",
                "CFBundleIconFile": "IconicIcon"
            ]
        )
        let root = app.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }

        let resourcesURL = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let iconURL = resourcesURL.appendingPathComponent("IconicIcon.icns")
        try Data([0, 1, 2, 3]).write(to: iconURL)

        let store = try SettingsStore(appSupportDirectory: root.appendingPathComponent("Support", isDirectory: true))
        let manager = LauncherManager(store: store)
        let record = try manager.createLauncher(
            targetAppURL: app,
            destinationDirectory: root.appendingPathComponent("Launchers", isDirectory: true)
        )
        let launcherURL = URL(fileURLWithPath: record.launcherAppPath)
        let launcherIconURL = launcherURL.appendingPathComponent("Contents/Resources/IconicIcon.icns")
        let launcherInfoURL = launcherURL.appendingPathComponent("Contents/Info.plist")
        let launcherInfo = try XCTUnwrap(NSDictionary(contentsOf: launcherInfoURL) as? [String: Any])

        XCTAssertTrue(FileManager.default.fileExists(atPath: launcherIconURL.path))
        XCTAssertEqual(try Data(contentsOf: launcherIconURL), try Data(contentsOf: iconURL))
        XCTAssertEqual(launcherInfo["CFBundleIconFile"] as? String, "IconicIcon.icns")
    }

    func testRefreshManagedLaunchersDoesNotDiscoverUnindexedApps() throws {
        let launcher = try makeTestApp(
            name: "Unindexed Proxy.app",
            info: [
                "CFBundleDisplayName": "Unindexed Proxy",
                "CFBundleExecutable": "launcher",
                "CFBundleIdentifier": "local.cn-pac-menubar.launcher.unindexed",
                "CNPacTargetAppPath": "/Applications/Unindexed.app",
                "CNPacLauncherProfile": "environment"
            ]
        )
        let root = launcher.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try SettingsStore(appSupportDirectory: root.appendingPathComponent("Support", isDirectory: true))
        let manager = LauncherManager(store: store)

        XCTAssertTrue(try manager.refreshManagedLaunchers().launchers.isEmpty)
    }

    func testRefreshManagedLaunchersRemovesMissingAndUpdatesManagedMetadata() throws {
        let launcher = try makeTestApp(
            name: "Fresh Proxy.app",
            info: [
                "CFBundleDisplayName": "Fresh Proxy",
                "CFBundleExecutable": "launcher",
                "CFBundleIdentifier": "local.cn-pac-menubar.launcher.fresh",
                "CNPacTargetAppPath": "/Applications/Fresh.app",
                "CNPacLauncherProfile": "java"
            ]
        )
        let root = launcher.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try SettingsStore(appSupportDirectory: root.appendingPathComponent("Support", isDirectory: true))
        let manager = LauncherManager(store: store)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastLaunchedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let staleRecord = LauncherRecord(
            displayName: "Stale Proxy",
            targetAppPath: "/Applications/Stale.app",
            launcherAppPath: launcher.path,
            bundleIdentifier: nil,
            createdAt: createdAt,
            lastLaunchedAt: lastLaunchedAt,
            managedByTool: true
        )
        let missingRecord = LauncherRecord(
            displayName: "Missing Proxy",
            targetAppPath: "/Applications/Missing.app",
            launcherAppPath: root.appendingPathComponent("Missing Proxy.app", isDirectory: true).path,
            bundleIdentifier: nil,
            managedByTool: true
        )
        try store.saveLauncherIndex(LauncherIndex(launchers: [missingRecord, staleRecord]))

        let refreshed = try manager.refreshManagedLaunchers()
        let record = try XCTUnwrap(refreshed.launchers.first)

        XCTAssertEqual(refreshed.launchers.count, 1)
        XCTAssertEqual(record.id, staleRecord.id)
        XCTAssertEqual(record.displayName, "Fresh Proxy")
        XCTAssertEqual(record.targetAppPath, "/Applications/Fresh.app")
        XCTAssertEqual(record.launcherAppPath, launcher.path)
        XCTAssertEqual(record.bundleIdentifier, "local.cn-pac-menubar.launcher.fresh")
        XCTAssertEqual(record.launcherProfile, .java)
        XCTAssertEqual(record.createdAt, createdAt)
        XCTAssertEqual(record.lastLaunchedAt, lastLaunchedAt)
        XCTAssertTrue(record.managedByTool)
    }

    func testRefreshManagedLaunchersKeepsIndexedLegacyRecordsWithoutMetadata() throws {
        let launcher = try makeTestApp(
            name: "Legacy Proxy.app",
            info: [
                "CFBundleExecutable": "launcher",
                "CFBundleIdentifier": "local.legacy.proxy"
            ]
        )
        let root = launcher.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try SettingsStore(appSupportDirectory: root.appendingPathComponent("Support", isDirectory: true))
        let manager = LauncherManager(store: store)
        let record = LauncherRecord(
            displayName: "Legacy Proxy",
            targetAppPath: "/Applications/Codex.app",
            launcherAppPath: launcher.path,
            bundleIdentifier: "local.legacy.proxy",
            managedByTool: false
        )
        try store.saveLauncherIndex(LauncherIndex(launchers: [record]))

        let refreshed = try manager.refreshManagedLaunchers()
        let refreshedRecord = try XCTUnwrap(refreshed.launchers.first)

        XCTAssertEqual(refreshed.launchers.count, 1)
        XCTAssertEqual(refreshedRecord.id, record.id)
        XCTAssertEqual(refreshedRecord.displayName, record.displayName)
        XCTAssertEqual(refreshedRecord.targetAppPath, record.targetAppPath)
        XCTAssertEqual(refreshedRecord.launcherAppPath, record.launcherAppPath)
        XCTAssertEqual(refreshedRecord.bundleIdentifier, record.bundleIdentifier)
        XCTAssertEqual(refreshedRecord.launcherProfile, record.launcherProfile)
        XCTAssertEqual(refreshedRecord.createdAt.timeIntervalSince1970, record.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(refreshedRecord.lastLaunchedAt)
        XCTAssertFalse(refreshedRecord.managedByTool)
    }

    private func makeTestApp(name: String, info: [String: Any]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = root.appendingPathComponent(name, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        if let executableName = info["CFBundleExecutable"] as? String {
            let executableURL = macOSURL.appendingPathComponent(executableName)
            try "#!/bin/zsh\n".write(to: executableURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        }
        return appURL
    }
}
