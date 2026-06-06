import AppKit
import CNPacMenubarCore
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var store: SettingsStore!
    private var settings = CNPacSettings()
    private var launcherIndex = LauncherIndex()
    private var pacServer: PACServer!
    private let proxyManager = SystemProxyManager()
    private var launcherManager: LauncherManager!
    private var keepaliveService: VPNKeepaliveService!
    private var lastPACWarnings: [String] = []
    private weak var proxyModePopup: NSPopUpButton?
    private weak var proxyHostField: NSTextField?
    private weak var socks5PortField: NSTextField?
    private weak var httpPortField: NSTextField?
    private weak var allowDirectFallbackCheckbox: NSButton?
    private var statusMenuOpenDepth = 0
    private weak var menuVPNKeepaliveSummaryItem: NSMenuItem?
    private weak var menuVPNKeepaliveParentItem: NSMenuItem?
    private weak var menuVPNKeepaliveStatusItem: NSMenuItem?
    private weak var menuVPNKeepaliveCheckButton: NSButton?
    private weak var menuVPNKeepaliveFailureIndicatorItem: NSMenuItem?
    private let statusBarIconProvider = StatusBarIconProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try SettingsStore()
            settings = store.loadSettings()
            launcherManager = LauncherManager(store: store)
            launcherIndex = store.loadLauncherIndex()
            try store.saveSettings(settings)
        } catch {
            showError(error)
            NSApp.terminate(nil)
            return
        }

        pacServer = PACServer { [weak self] in
            guard let self else { throw AppError.missingPAC }
            return try self.loadPACContent()
        }
        pacServer.onStateChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshUI()
            }
        }
        keepaliveService = VPNKeepaliveService()
        keepaliveService.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshUI()
            }
        }
        keepaliveService.apply(settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
        }
        refreshUI()
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pacServer?.stop()
        keepaliveService?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }
        sender.orderOut(nil)
        hideDockIcon()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === mainWindow else { return }
        DispatchQueue.main.async {
            if NSApp.windows.allSatisfy({ !$0.isVisible }) {
                self.hideDockIcon()
            }
        }
    }

    private func refreshUI() {
        updateStatusItem()
        if isStatusMenuOpen {
            updateOpenMenuKeepaliveItems()
        } else {
            rebuildMenu()
        }
        if let mainWindow, mainWindow.isVisible {
            updateMainWindow(mainWindow)
        }
    }

    private var isStatusMenuOpen: Bool {
        statusMenuOpenDepth > 0
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        statusItem.length = NSStatusItem.squareLength
        button.title = ""
        button.toolTip = "CN PAC Menubar"
        button.image = statusBarIconProvider.image(
            for: currentStatusBarIconState,
            appearance: button.effectiveAppearance
        ) ?? fallbackStatusBarImage()
        button.imagePosition = .imageOnly
    }

    private var currentStatusBarIconState: StatusBarIconProvider.State {
        let status = keepaliveService.status
        guard status.isEnabled, let lastResult = status.lastResult else {
            return .normal
        }
        if lastResult.isSuccess {
            return .healthy
        }
        return settings.vpnKeepaliveFailureIndicatorEnabled ? .failure : .normal
    }

    private func fallbackStatusBarImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "CN PAC")
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "CN PAC")
            ?? NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "CN PAC")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let lanURL = currentLANPACURL()

        addDisabled("CN PAC Menubar", to: menu)
        addDisabled("PAC: \(settings.pacPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")", to: menu)
        addDisabled("Server: \(pacServer.state.detail)", to: menu)
        addDisabled("Local PAC URL: \(settings.pacURL.absoluteString)", to: menu)
        addDisabled("LAN PAC URL: \(lanURL?.absoluteString ?? "No LAN IPv4 found")", to: menu)
        addDisabled("Proxy: \(settings.proxyEndpointSummary)", to: menu)
        menuVPNKeepaliveSummaryItem = addDisabled("VPN Keepalive: \(keepaliveService.status.detail)", to: menu)
        if !lastPACWarnings.isEmpty {
            addDisabled("PAC warning: \(lastPACWarnings.joined(separator: " "))", to: menu)
        }
        menu.addItem(.separator())

        menu.addItem(actionItem("Show Main Window", #selector(showMainWindow)))
        menu.addItem(actionItem("Choose PAC...", #selector(choosePAC)))
        menu.addItem(recentPACsItem())
        menu.addItem(actionItem("Open PAC Folder", #selector(openPACFolder), enabled: settings.pacPath != nil))
        menu.addItem(.separator())

        menu.addItem(actionItem(pacServer.state.isActive ? "Stop PAC Server" : "Start PAC Server", #selector(togglePACServer), enabled: settings.pacPath != nil))
        menu.addItem(actionItem("Set PAC Server Port...", #selector(configureServerPort)))
        menu.addItem(actionItem("Copy Local PAC URL", #selector(copyPACURL)))
        menu.addItem(actionItem("Copy LAN PAC URL", #selector(copyLANPACURL), enabled: lanURL != nil))
        menu.addItem(actionItem("Copy Terminal Proxy Command", #selector(copyTerminalProxyCommand)))
        menu.addItem(.separator())

        menu.addItem(actionItem("Apply Auto Proxy", #selector(applyAutoProxy), enabled: settings.pacPath != nil))
        menu.addItem(actionItem("Disable Auto Proxy", #selector(disableAutoProxy)))
        menu.addItem(actionItem("Refresh PAC", #selector(refreshPACFromMenu), enabled: settings.pacPath != nil))
        menu.addItem(actionItem("Show System Proxy Status", #selector(showSystemProxyStatus)))
        menu.addItem(.separator())

        menu.addItem(proxyRuleItem())
        menu.addItem(vpnKeepaliveItem())
        menu.addItem(launchersItem())
        menu.addItem(.separator())

        let loginItem = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(actionItem("Settings...", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", #selector(quit)))

        statusItem.menu = menu
    }

    private func recentPACsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Recent PACs", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if settings.recentPACPaths.isEmpty {
            addDisabled("No recent PACs", to: submenu)
        } else {
            for path in settings.recentPACPaths {
                let title = URL(fileURLWithPath: path).lastPathComponent
                let menuItem = actionItem(title, #selector(selectRecentPAC(_:)))
                menuItem.representedObject = path
                submenu.addItem(menuItem)
            }
        }
        item.submenu = submenu
        return item
    }

    private func proxyRuleItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Proxy: \(settings.proxyCompactSummary)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        addDisabled("Host: \(settings.proxyHost)", to: submenu)
        addDisabled("SOCKS5: \(settings.socks5Port) · HTTP: \(settings.httpPort)", to: submenu)
        addDisabled("Fallback: \(settings.proxyFailureBehaviorSummary)", to: submenu)
        addDisabled("PAC Rule: \(settings.pacProxyExpression)", to: submenu)
        submenu.addItem(.separator())
        for mode in ProxyMode.allCases {
            let modeItem = actionItem("Use \(mode.displayName)", #selector(setProxyMode(_:)))
            modeItem.representedObject = mode.rawValue
            modeItem.state = settings.proxyMode == mode ? .on : .off
            submenu.addItem(modeItem)
        }
        submenu.addItem(.separator())
        let directFallbackItem = actionItem("Allow DIRECT Fallback", #selector(toggleDirectFallback))
        directFallbackItem.state = settings.allowDirectFallback ? .on : .off
        submenu.addItem(directFallbackItem)
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Set SOCKS5 Port...", #selector(configureSocks5Port)))
        submenu.addItem(actionItem("Set HTTP Port...", #selector(configureHTTPPort)))
        submenu.addItem(actionItem("Set Proxy Host...", #selector(configureProxyHost)))
        submenu.addItem(actionItem("Configure Proxy Rule...", #selector(configureProxyRule)))
        item.submenu = submenu
        return item
    }

    private func vpnKeepaliveItem() -> NSMenuItem {
        let status = keepaliveService.status
        let item = NSMenuItem(title: "Google VPN Keepalive: \(status.displayName)", action: nil, keyEquivalent: "")
        menuVPNKeepaliveParentItem = item
        let submenu = NSMenu()
        menuVPNKeepaliveStatusItem = addDisabled("Status: \(status.detail)", to: submenu)
        addDisabled("Target: \(settings.vpnKeepaliveURL)", to: submenu)
        addDisabled("Interval: \(settings.vpnKeepaliveIntervalSeconds)s · Timeout: \(settings.vpnKeepaliveTimeoutSeconds)s", to: submenu)
        submenu.addItem(.separator())

        let toggle = actionItem(settings.vpnKeepaliveEnabled ? "Disable Keepalive" : "Enable Keepalive", #selector(toggleVPNKeepalive))
        toggle.state = settings.vpnKeepaliveEnabled ? .on : .off
        submenu.addItem(toggle)
        submenu.addItem(keepaliveCheckNowItem(enabled: settings.vpnKeepaliveEnabled))
        let failureIndicator = actionItem("Show Failure Dot in Menu Bar Icon", #selector(toggleVPNKeepaliveFailureIndicator))
        failureIndicator.state = settings.vpnKeepaliveFailureIndicatorEnabled ? .on : .off
        menuVPNKeepaliveFailureIndicatorItem = failureIndicator
        submenu.addItem(failureIndicator)
        submenu.addItem(actionItem("Keepalive Settings...", #selector(configureVPNKeepalive)))

        item.submenu = submenu
        return item
    }

    private func keepaliveCheckNowItem(enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 34))

        let button = NSButton(title: "Check Now", target: self, action: #selector(runVPNKeepaliveNow))
        button.bezelStyle = .rounded
        button.isEnabled = enabled
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        menuVPNKeepaliveCheckButton = button
        item.view = row
        return item
    }

    private func launchersItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Launchers", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(actionItem("Create Launcher...", #selector(createLauncher)))
        submenu.addItem(actionItem("Refresh Managed Launchers", #selector(refreshLaunchers)))
        submenu.addItem(.separator())

        if launcherIndex.launchers.isEmpty {
            addDisabled("No launchers found", to: submenu)
        } else {
            for launcher in launcherIndex.launchers {
                let launcherItem = NSMenuItem(title: launcher.displayName, action: nil, keyEquivalent: "")
                let launcherMenu = NSMenu()
                let launch = actionItem("Launch", #selector(launchLauncher(_:)))
                launch.representedObject = launcher.launcherAppPath
                launcherMenu.addItem(launch)
                let reveal = actionItem("Reveal Launcher", #selector(revealLauncher(_:)))
                reveal.representedObject = launcher.launcherAppPath
                launcherMenu.addItem(reveal)
                let remove = actionItem("Remove From List", #selector(removeLauncherFromList(_:)))
                remove.representedObject = launcher.launcherAppPath
                launcherMenu.addItem(remove)
                launcherMenu.addItem(.separator())
                addDisabled(launcher.managedByTool ? "Managed by CN PAC" : "Detected existing launcher", to: launcherMenu)
                if !launcher.targetAppPath.isEmpty {
                    addDisabled("Target: \(URL(fileURLWithPath: launcher.targetAppPath).lastPathComponent)", to: launcherMenu)
                }
                if let profile = launcher.launcherProfile {
                    addDisabled("Profile: \(profile.displayName)", to: launcherMenu)
                    if let note = profile.note {
                        addDisabled(note, to: launcherMenu)
                    }
                }
                launcherItem.submenu = launcherMenu
                submenu.addItem(launcherItem)
            }
        }

        item.submenu = submenu
        return item
    }

    @objc private func choosePAC() {
        frontMainWindow()

        let panel = NSOpenPanel()
        panel.title = "Choose PAC File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pac") ?? .data,
            .javaScript
        ]
        let defaultDirectory = URL(fileURLWithPath: "/Users/wsy/CascadeProjects/cn-pac/output", isDirectory: true)
        if FileManager.default.fileExists(atPath: defaultDirectory.path) {
            panel.directoryURL = defaultDirectory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectPAC(path: url.path)
    }

    @objc private func selectRecentPAC(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        selectPAC(path: path)
    }

    private func selectPAC(path: String) {
        settings.rememberPACPath(path)
        do {
            try store.saveSettings(settings)
            try ensurePACServerRunning()
            try refreshPAC(applySystemProxy: true)
            showInfo("PAC selected", "Now serving \(URL(fileURLWithPath: path).lastPathComponent).")
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func openPACFolder() {
        guard let path = settings.pacPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func togglePACServer() {
        if pacServer.state.isActive {
            pacServer.stop()
        } else {
            do {
                try ensurePACServerRunning()
            } catch {
                showError(error)
            }
        }
        refreshUI()
    }

    @objc private func configureServerPort() {
        guard let value = prompt("PAC Server Port", message: "Set the local PAC server port.", defaultValue: "\(settings.pacServerPort)"),
              let port = Int(value), (1...65535).contains(port) else {
            return
        }
        let serverWasActive = pacServer.state.isActive
        settings.pacServerPort = port
        settings.bumpRefreshVersion()
        do {
            try store.saveSettings(settings)
            if serverWasActive {
                try pacServer.start(port: port)
                if settings.pacPath != nil {
                    _ = try proxyManager.applyAutoProxy(url: settings.pacURL)
                }
            }
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func copyPACURL() {
        copyToPasteboard(settings.pacURL.absoluteString)
    }

    @objc private func copyLANPACURL() {
        guard let url = currentLANPACURL() else {
            showInfo("LAN PAC URL unavailable", "No active non-loopback IPv4 address was found.")
            return
        }
        copyToPasteboard(url.absoluteString)
    }

    @objc private func copyTerminalProxyCommand() {
        copyToPasteboard(settings.terminalProxyCommand)
    }

    @objc private func applyAutoProxy() {
        do {
            try ensurePACServerRunning()
            _ = try proxyManager.applyAutoProxy(url: settings.pacURL)
            showInfo("Auto proxy applied", settings.pacURL.absoluteString)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func disableAutoProxy() {
        do {
            _ = try proxyManager.disableAutoProxy()
            showInfo("Auto proxy disabled", "Automatic proxy configuration was disabled for enabled network services.")
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func refreshPACFromMenu() {
        do {
            try refreshPAC(applySystemProxy: true)
            showInfo("PAC refreshed", settings.pacURL.absoluteString)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func showSystemProxyStatus() {
        do {
            showInfo("System Proxy Status", try proxyManager.currentProxyStatus())
        } catch {
            showError(error)
        }
    }

    @objc private func setProxyMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = ProxyMode(rawValue: rawValue) else { return }
        settings.proxyMode = mode
        commitProxySettings()
    }

    @objc private func configureProxyRule() {
        let result = proxyRuleDialog()
        guard let result else { return }
        settings.proxyHost = result.host
        settings.httpPort = result.httpPort
        settings.socks5Port = result.socks5Port
        settings.allowDirectFallback = result.allowDirectFallback
        settings.noProxy = result.noProxy
        commitProxySettings()
    }

    @objc private func configureSocks5Port() {
        guard let port = promptPort(title: "SOCKS5 Port", message: "Set the SOCKS5 proxy port.", defaultValue: settings.socks5Port) else {
            return
        }
        settings.socks5Port = port
        commitProxySettings()
    }

    @objc private func configureHTTPPort() {
        guard let port = promptPort(title: "HTTP Port", message: "Set the HTTP proxy port.", defaultValue: settings.httpPort) else {
            return
        }
        settings.httpPort = port
        commitProxySettings()
    }

    @objc private func configureProxyHost() {
        guard let host = prompt("Proxy Host", message: "Set the proxy host used inside the PAC file and app launchers.", defaultValue: settings.proxyHost),
              !host.isEmpty else {
            return
        }
        settings.proxyHost = host
        commitProxySettings()
    }

    @objc private func toggleDirectFallback() {
        settings.allowDirectFallback.toggle()
        commitProxySettings()
    }

    @objc private func changeProxyModeFromPopup(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = ProxyMode(rawValue: rawValue) else {
            return
        }
        settings.proxyMode = mode
        commitProxySettings()
    }

    @objc private func applyQuickProxySettings() {
        guard let host = proxyHostField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              let socksText = socks5PortField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              let httpText = httpPortField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              let socksPort = Int(socksText),
              let httpPort = Int(httpText),
              (1...65535).contains(socksPort),
              (1...65535).contains(httpPort) else {
            showInfo("Invalid proxy settings", "Use a non-empty host and ports from 1 to 65535.")
            return
        }

        if let rawValue = proxyModePopup?.selectedItem?.representedObject as? String,
           let mode = ProxyMode(rawValue: rawValue) {
            settings.proxyMode = mode
        }
        settings.proxyHost = host
        settings.socks5Port = socksPort
        settings.httpPort = httpPort
        settings.allowDirectFallback = allowDirectFallbackCheckbox?.state == .on
        commitProxySettings()
    }

    @objc private func toggleVPNKeepalive() {
        settings.vpnKeepaliveEnabled.toggle()
        commitVPNKeepaliveSettings()
    }

    @objc private func runVPNKeepaliveNow() {
        keepaliveService.runNow()
        refreshUI()
    }

    @objc private func toggleVPNKeepaliveFailureIndicator() {
        settings.vpnKeepaliveFailureIndicatorEnabled.toggle()
        do {
            try store.saveSettings(settings)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func configureVPNKeepalive() {
        guard let result = vpnKeepaliveDialog() else { return }
        settings.vpnKeepaliveEnabled = result.enabled
        settings.vpnKeepaliveURL = result.url
        settings.vpnKeepaliveIntervalSeconds = result.intervalSeconds
        settings.vpnKeepaliveTimeoutSeconds = result.timeoutSeconds
        settings.vpnKeepaliveFailureIndicatorEnabled = result.failureIndicatorEnabled
        commitVPNKeepaliveSettings()
    }

    @objc private func createLauncher() {
        frontMainWindow()

        let targetPanel = NSOpenPanel()
        targetPanel.title = "Choose Target App"
        targetPanel.canChooseFiles = true
        targetPanel.canChooseDirectories = false
        targetPanel.allowsMultipleSelection = false
        targetPanel.allowedContentTypes = [.applicationBundle]
        targetPanel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard targetPanel.runModal() == .OK, let targetURL = targetPanel.url else { return }

        let destinationPanel = NSOpenPanel()
        destinationPanel.title = "Choose Launcher Destination Folder"
        destinationPanel.canChooseFiles = false
        destinationPanel.canChooseDirectories = true
        destinationPanel.canCreateDirectories = true
        destinationPanel.allowsMultipleSelection = false
        destinationPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
        guard destinationPanel.runModal() == .OK, let destinationURL = destinationPanel.url else { return }

        do {
            let record = try launcherManager.createLauncher(targetAppURL: targetURL, destinationDirectory: destinationURL)
            launcherIndex.upsert(record)
            try store.saveLauncherIndex(launcherIndex)
            let profile = record.launcherProfile?.displayName ?? "Environment"
            showInfo("Launcher created", "\(record.launcherAppPath)\nProfile: \(profile)")
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func refreshLaunchers() {
        do {
            launcherIndex = try launcherManager.refreshManagedLaunchers()
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func launchLauncher(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showError(error)
                } else {
                    self?.markLauncherLaunched(path: path)
                }
            }
        }
    }

    @objc private func revealLauncher(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func removeLauncherFromList(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        do {
            launcherIndex = try launcherManager.removeFromIndex(launcherPath: path)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.unregister()
                settings.launchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                settings.launchAtLogin = true
            }
            try store.saveSettings(settings)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func showSettings() {
        let result = settingsDialog()
        guard let result else { return }
        let serverWasActive = pacServer.state.isActive
        settings.pacServerPort = result.pacServerPort
        settings.proxyHost = result.host
        settings.httpPort = result.httpPort
        settings.socks5Port = result.socks5Port
        settings.allowDirectFallback = result.allowDirectFallback
        settings.noProxy = result.noProxy
        do {
            if serverWasActive {
                try pacServer.start(port: settings.pacServerPort)
            }
            try saveOrRefreshPAC(applySystemProxy: serverWasActive)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showMainWindow() {
        frontMainWindow()
    }

    @discardableResult
    private func frontMainWindow() -> NSWindow {
        showDockIcon()
        if let mainWindow {
            updateMainWindow(mainWindow)
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
            return mainWindow
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CN PAC Menubar"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 580, height: 500)
        window.delegate = self
        window.center()
        mainWindow = window
        updateMainWindow(window)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return window
    }

    private func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }

    private func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func updateMainWindow(_ window: NSWindow) {
        proxyModePopup = nil
        proxyHostField = nil
        socks5PortField = nil
        httpPortField = nil
        allowDirectFallbackCheckbox = nil

        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22)
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let headerText = NSStackView()
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 3
        let title = NSTextField(labelWithString: "CN PAC Menubar")
        title.font = .boldSystemFont(ofSize: 24)
        let subtitle = NSTextField(labelWithString: settings.proxyEndpointSummary)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        headerText.addArrangedSubview(title)
        headerText.addArrangedSubview(subtitle)
        header.addArrangedSubview(headerText)
        header.addArrangedSubview(statusBadge(pacServer.state.displayName, color: statusColor(for: pacServer.state)))
        stack.addArrangedSubview(header)

        let pacText = settings.pacPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No PAC selected"
        stack.addArrangedSubview(infoRow("PAC", pacText))
        stack.addArrangedSubview(infoRow("Server", pacServer.state.detail))
        stack.addArrangedSubview(infoRow("Local PAC URL", settings.pacURL.absoluteString))
        stack.addArrangedSubview(infoRow("LAN PAC URL", currentLANPACURL()?.absoluteString ?? "No LAN IPv4 found"))

        let copyPACButtons = NSStackView()
        copyPACButtons.orientation = .horizontal
        copyPACButtons.spacing = 8
        copyPACButtons.addArrangedSubview(button("Copy Local PAC URL", action: #selector(copyPACURL)))
        let copyLANPACButton = button("Copy LAN PAC URL", action: #selector(copyLANPACURL))
        copyLANPACButton.isEnabled = currentLANPACURL() != nil
        copyPACButtons.addArrangedSubview(copyLANPACButton)
        stack.addArrangedSubview(copyPACButtons)

        let terminalProxyButtons = NSStackView()
        terminalProxyButtons.orientation = .horizontal
        terminalProxyButtons.spacing = 8
        terminalProxyButtons.addArrangedSubview(button("Copy Terminal Proxy Command", action: #selector(copyTerminalProxyCommand)))
        stack.addArrangedSubview(terminalProxyButtons)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let serverButton = button(pacServer.state.isActive ? "Stop Server" : "Start Server", action: #selector(togglePACServer))
        serverButton.isEnabled = settings.pacPath != nil
        buttonRow.addArrangedSubview(serverButton)
        buttonRow.addArrangedSubview(button("Choose PAC...", action: #selector(choosePAC)))
        buttonRow.addArrangedSubview(button("Apply Auto Proxy", action: #selector(applyAutoProxy)))
        buttonRow.addArrangedSubview(button("Refresh PAC", action: #selector(refreshPACFromMenu)))
        stack.addArrangedSubview(buttonRow)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Proxy"))
        stack.addArrangedSubview(infoRow("Fallback", settings.proxyFailureBehaviorSummary))
        stack.addArrangedSubview(proxyQuickEditor())

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Google VPN Keepalive"))
        stack.addArrangedSubview(infoRow("Status", keepaliveService.status.detail))
        stack.addArrangedSubview(infoRow("Target", settings.vpnKeepaliveURL))
        let keepaliveButtons = NSStackView()
        keepaliveButtons.orientation = .horizontal
        keepaliveButtons.spacing = 8
        keepaliveButtons.addArrangedSubview(button(settings.vpnKeepaliveEnabled ? "Disable Keepalive" : "Enable Keepalive", action: #selector(toggleVPNKeepalive)))
        let checkNow = button("Check Now", action: #selector(runVPNKeepaliveNow))
        checkNow.isEnabled = settings.vpnKeepaliveEnabled
        keepaliveButtons.addArrangedSubview(checkNow)
        keepaliveButtons.addArrangedSubview(button("Keepalive Settings...", action: #selector(configureVPNKeepalive)))
        stack.addArrangedSubview(keepaliveButtons)

        let secondaryButtons = NSStackView()
        secondaryButtons.orientation = .horizontal
        secondaryButtons.spacing = 8
        secondaryButtons.addArrangedSubview(button("Settings...", action: #selector(showSettings)))
        secondaryButtons.addArrangedSubview(button("Create Launcher...", action: #selector(createLauncher)))
        stack.addArrangedSubview(secondaryButtons)

        window.contentView = root
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func proxyQuickEditor() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10

        let modePopup = NSPopUpButton()
        for mode in ProxyMode.allCases {
            modePopup.addItem(withTitle: mode.displayName)
            modePopup.lastItem?.representedObject = mode.rawValue
        }
        modePopup.selectItem(withTitle: settings.proxyMode.displayName)
        modePopup.target = self
        modePopup.action = #selector(changeProxyModeFromPopup(_:))
        modePopup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        self.proxyModePopup = modePopup

        let host = textField(settings.proxyHost, width: 180)
        let socks = textField("\(settings.socks5Port)", width: 110)
        let http = textField("\(settings.httpPort)", width: 110)
        let directFallback = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        directFallback.state = settings.allowDirectFallback ? .on : .off
        self.proxyHostField = host
        self.socks5PortField = socks
        self.httpPortField = http
        self.allowDirectFallbackCheckbox = directFallback

        container.addArrangedSubview(controlRow("Protocol", modePopup))
        container.addArrangedSubview(controlRow("Host", host))
        container.addArrangedSubview(controlRow("SOCKS5 Port", socks))
        container.addArrangedSubview(controlRow("HTTP Port", http))
        container.addArrangedSubview(controlRow("Allow DIRECT Fallback", directFallback))

        let apply = button("Apply Proxy", action: #selector(applyQuickProxySettings))
        container.addArrangedSubview(apply)
        return container
    }

    private func infoRow(_ title: String, _ value: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .right
        titleLabel.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.isSelectable = true
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.maximumNumberOfLines = 1

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func controlRow(_ title: String, _ control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .right
        titleLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(control)
        return row
    }

    private func textField(_ value: String, width: CGFloat) -> NSTextField {
        let field = NSTextField(string: value)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        return box
    }

    private func statusBadge(_ text: String, color: NSColor) -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        badge.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        label.textColor = color
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(greaterThanOrEqualTo: badge.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: badge.trailingAnchor, constant: -12),
            label.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])

        return badge
    }

    private func statusColor(for state: PACServerState) -> NSColor {
        switch state {
        case .running:
            return .systemGreen
        case .starting:
            return .controlAccentColor
        case .failed:
            return .systemRed
        case .stopped:
            return .secondaryLabelColor
        }
    }

    private func commitProxySettings() {
        do {
            try saveOrRefreshPAC(applySystemProxy: pacServer.state.isActive)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    private func commitVPNKeepaliveSettings() {
        do {
            try store.saveSettings(settings)
            keepaliveService.apply(settings: settings)
        } catch {
            showError(error)
        }
        refreshUI()
    }

    private func saveOrRefreshPAC(applySystemProxy: Bool) throws {
        guard settings.pacPath != nil else {
            try store.saveSettings(settings)
            return
        }
        try refreshPAC(applySystemProxy: applySystemProxy)
    }

    private func refreshPAC(applySystemProxy: Bool) throws {
        settings.bumpRefreshVersion()
        _ = try loadPACContent()
        try store.saveSettings(settings)
        if applySystemProxy {
            try ensurePACServerRunning()
            _ = try proxyManager.applyAutoProxy(url: settings.pacURL)
        }
    }

    private func ensurePACServerRunning() throws {
        guard settings.pacPath != nil else {
            throw AppError.missingPAC
        }
        if !pacServer.state.isActive {
            try pacServer.start(port: settings.pacServerPort)
        }
    }

    private func currentLANPACURL() -> URL? {
        guard let address = NetworkInterface.primaryLANIPv4Address() else {
            return nil
        }
        return settings.pacURL(host: address)
    }

    private func loadPACContent() throws -> String {
        guard let path = settings.pacPath else {
            throw AppError.missingPAC
        }
        let original = try String(contentsOfFile: path, encoding: .utf8)
        let result = PACRewriter.rewrite(original, settings: settings)
        lastPACWarnings = result.warnings
        return result.content
    }

    private func markLauncherLaunched(path: String) {
        guard let index = launcherIndex.launchers.firstIndex(where: { $0.launcherAppPath == path }) else { return }
        launcherIndex.launchers[index].lastLaunchedAt = Date()
        try? store.saveLauncherIndex(launcherIndex)
        refreshUI()
    }

    @discardableResult
    private func addDisabled(_ title: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    private func updateOpenMenuKeepaliveItems() {
        let status = keepaliveService.status
        menuVPNKeepaliveSummaryItem?.title = "VPN Keepalive: \(status.detail)"
        menuVPNKeepaliveParentItem?.title = "Google VPN Keepalive: \(status.displayName)"
        menuVPNKeepaliveStatusItem?.title = "Status: \(status.detail)"
        menuVPNKeepaliveCheckButton?.isEnabled = settings.vpnKeepaliveEnabled
        menuVPNKeepaliveFailureIndicatorItem?.state = settings.vpnKeepaliveFailureIndicatorEnabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuOpenDepth += 1
    }

    func menuDidClose(_ menu: NSMenu) {
        statusMenuOpenDepth = max(0, statusMenuOpenDepth - 1)
        if !isStatusMenuOpen {
            DispatchQueue.main.async { [weak self] in
                self?.refreshUI()
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func actionItem(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func prompt(_ title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptPort(title: String, message: String, defaultValue: Int) -> Int? {
        guard let value = prompt(title, message: message, defaultValue: "\(defaultValue)") else {
            return nil
        }
        guard let port = Int(value), (1...65535).contains(port) else {
            showInfo("Invalid port", "Use a port from 1 to 65535.")
            return nil
        }
        return port
    }

    private func proxyRuleDialog() -> SettingsFormResult? {
        settingsFormDialog(title: "Proxy Rule", includePACServerPort: false)
    }

    private func settingsDialog() -> SettingsFormResult? {
        settingsFormDialog(title: "Settings", includePACServerPort: true)
    }

    private func vpnKeepaliveDialog() -> VPNKeepaliveFormResult? {
        let alert = NSAlert()
        alert.messageText = "Google VPN Keepalive"
        alert.informativeText = "Send a lightweight request on a schedule so the phone-side VPN continues seeing traffic."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let enabled = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        enabled.state = settings.vpnKeepaliveEnabled ? .on : .off
        let url = NSTextField(string: settings.vpnKeepaliveURL)
        let interval = NSTextField(string: "\(settings.vpnKeepaliveIntervalSeconds)")
        let timeout = NSTextField(string: "\(settings.vpnKeepaliveTimeoutSeconds)")
        let failureIndicator = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        failureIndicator.state = settings.vpnKeepaliveFailureIndicatorEnabled ? .on : .off

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.addRow(with: [label("Enabled"), enabled])
        grid.addRow(with: [label("Target URL"), url])
        grid.addRow(with: [label("Interval Seconds"), interval])
        grid.addRow(with: [label("Timeout Seconds"), timeout])
        grid.addRow(with: [label("Menu Bar Failure Dot"), failureIndicator])
        grid.frame = NSRect(x: 0, y: 0, width: 460, height: 158)
        url.frame.size.width = 320
        interval.frame.size.width = 320
        timeout.frame.size.width = 320
        alert.accessoryView = grid

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let targetURL = url.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VPNKeepaliveConfiguration.normalizedURL(from: targetURL) != nil else {
            showInfo("Invalid keepalive URL", "Use an HTTP or HTTPS URL, for example \(CNPacSettings.defaultVPNKeepaliveURL).")
            return nil
        }
        guard let intervalSeconds = Int(interval.stringValue),
              (VPNKeepaliveConfiguration.minimumIntervalSeconds...VPNKeepaliveConfiguration.maximumIntervalSeconds).contains(intervalSeconds),
              let timeoutSeconds = Int(timeout.stringValue),
              (VPNKeepaliveConfiguration.minimumTimeoutSeconds...VPNKeepaliveConfiguration.maximumTimeoutSeconds).contains(timeoutSeconds) else {
            showInfo(
                "Invalid keepalive timing",
                "Use an interval from \(VPNKeepaliveConfiguration.minimumIntervalSeconds) to \(VPNKeepaliveConfiguration.maximumIntervalSeconds) seconds and a timeout from \(VPNKeepaliveConfiguration.minimumTimeoutSeconds) to \(VPNKeepaliveConfiguration.maximumTimeoutSeconds) seconds."
            )
            return nil
        }

        return VPNKeepaliveFormResult(
            enabled: enabled.state == .on,
            url: targetURL,
            intervalSeconds: intervalSeconds,
            timeoutSeconds: timeoutSeconds,
            failureIndicatorEnabled: failureIndicator.state == .on
        )
    }

    private func settingsFormDialog(title: String, includePACServerPort: Bool) -> SettingsFormResult? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let host = NSTextField(string: settings.proxyHost)
        let http = NSTextField(string: "\(settings.httpPort)")
        let socks = NSTextField(string: "\(settings.socks5Port)")
        let noProxy = NSTextField(string: settings.noProxy)
        let pacPort = NSTextField(string: "\(settings.pacServerPort)")
        let allowDirectFallback = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        allowDirectFallback.state = settings.allowDirectFallback ? .on : .off

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.addRow(with: [label("Proxy Host"), host])
        grid.addRow(with: [label("HTTP Port"), http])
        grid.addRow(with: [label("SOCKS5 Port"), socks])
        grid.addRow(with: [label("Allow DIRECT Fallback"), allowDirectFallback])
        grid.addRow(with: [label("NO_PROXY"), noProxy])
        if includePACServerPort {
            grid.addRow(with: [label("PAC Server Port"), pacPort])
        }
        grid.frame = NSRect(x: 0, y: 0, width: 390, height: includePACServerPort ? 190 : 160)
        host.frame.size.width = 220
        http.frame.size.width = 220
        socks.frame.size.width = 220
        noProxy.frame.size.width = 220
        pacPort.frame.size.width = 220
        alert.accessoryView = grid

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let httpPort = Int(http.stringValue),
              let socksPort = Int(socks.stringValue),
              let pacServerPort = Int(pacPort.stringValue),
              (1...65535).contains(httpPort),
              (1...65535).contains(socksPort),
              (1...65535).contains(pacServerPort) else {
            return nil
        }

        return SettingsFormResult(
            host: host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            httpPort: httpPort,
            socks5Port: socksPort,
            allowDirectFallback: allowDirectFallback.state == .on,
            noProxy: noProxy.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            pacServerPort: pacServerPort
        )
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ error: Error) {
        showInfo("CN PAC Error", error.localizedDescription)
    }
}

private struct SettingsFormResult {
    var host: String
    var httpPort: Int
    var socks5Port: Int
    var allowDirectFallback: Bool
    var noProxy: String
    var pacServerPort: Int
}

private struct VPNKeepaliveFormResult {
    var enabled: Bool
    var url: String
    var intervalSeconds: Int
    var timeoutSeconds: Int
    var failureIndicatorEnabled: Bool
}

private final class StatusBarIconProvider {
    enum State: String {
        case normal
        case healthy
        case failure
    }

    private var cache: [String: NSImage] = [:]

    func image(for state: State, appearance: NSAppearance) -> NSImage? {
        let tone = appearance.cnPacUsesDarkStatusIcon ? "dark" : "light"
        let resourceName = "StatusBarC-\(state.rawValue)-\(tone)"
        if let cached = cache[resourceName] {
            return cached
        }
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "StatusBar"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        image.size = NSSize(width: 18, height: 18)
        cache[resourceName] = image
        return image
    }
}

private extension NSAppearance {
    var cnPacUsesDarkStatusIcon: Bool {
        let matched = bestMatch(from: [
            .aqua,
            .darkAqua,
            .vibrantLight,
            .vibrantDark,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua
        ])
        return matched == .darkAqua
            || matched == .vibrantDark
            || matched == .accessibilityHighContrastDarkAqua
    }
}

private enum AppError: LocalizedError {
    case missingPAC

    var errorDescription: String? {
        switch self {
        case .missingPAC:
            return "Choose a PAC file first."
        }
    }
}
