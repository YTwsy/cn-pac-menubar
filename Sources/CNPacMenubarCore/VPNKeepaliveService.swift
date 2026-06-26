import Foundation

public struct VPNKeepaliveConfiguration: Equatable, Sendable {
    public static let minimumIntervalSeconds = 30
    public static let maximumIntervalSeconds = 86_400
    public static let minimumTimeoutSeconds = 1
    public static let maximumTimeoutSeconds = 120

    public var url: URL
    public var pacPath: String?
    public var settings: CNPacSettings
    public var intervalSeconds: Int
    public var timeoutSeconds: Int

    public init?(settings: CNPacSettings) {
        guard settings.vpnKeepaliveEnabled,
              let url = Self.normalizedURL(from: settings.vpnKeepaliveURL) else {
            return nil
        }
        self.url = url
        self.pacPath = settings.pacPath
        self.settings = settings
        self.intervalSeconds = Self.normalizedIntervalSeconds(settings.vpnKeepaliveIntervalSeconds)
        self.timeoutSeconds = Self.normalizedTimeoutSeconds(settings.vpnKeepaliveTimeoutSeconds)
    }

    public static func normalizedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }

    public static func normalizedIntervalSeconds(_ value: Int) -> Int {
        min(max(value, minimumIntervalSeconds), maximumIntervalSeconds)
    }

    public static func normalizedTimeoutSeconds(_ value: Int) -> Int {
        min(max(value, minimumTimeoutSeconds), maximumTimeoutSeconds)
    }
}

public enum VPNKeepaliveResult: Equatable, Sendable {
    case success(completedAt: Date, statusCode: Int, durationMilliseconds: Int)
    case failure(completedAt: Date, message: String)

    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    public var detail: String {
        switch self {
        case .success(let completedAt, let statusCode, let durationMilliseconds):
            return "HTTP \(statusCode) at \(VPNKeepaliveTimeText.clockTime(completedAt)) (\(durationMilliseconds) ms)"
        case .failure(let completedAt, let message):
            return "Failed at \(VPNKeepaliveTimeText.clockTime(completedAt)): \(message)"
        }
    }
}

public struct VPNKeepaliveStatus: Equatable, Sendable {
    public var isEnabled: Bool
    public var isRunning: Bool
    public var nextRun: Date?
    public var lastStartedAt: Date?
    public var lastResult: VPNKeepaliveResult?

    public init(
        isEnabled: Bool,
        isRunning: Bool,
        nextRun: Date? = nil,
        lastStartedAt: Date? = nil,
        lastResult: VPNKeepaliveResult? = nil
    ) {
        self.isEnabled = isEnabled
        self.isRunning = isRunning
        self.nextRun = nextRun
        self.lastStartedAt = lastStartedAt
        self.lastResult = lastResult
    }

    public static var disabled: VPNKeepaliveStatus {
        VPNKeepaliveStatus(isEnabled: false, isRunning: false)
    }

    public var displayName: String {
        guard isEnabled else {
            return "Disabled"
        }
        if isRunning {
            return "Checking"
        }
        if let lastResult {
            return lastResult.isSuccess ? "OK" : "Failed"
        }
        return "Waiting"
    }

    public var hasFailedLastResult: Bool {
        guard isEnabled, let lastResult else {
            return false
        }
        return !lastResult.isSuccess
    }

    public var detail: String {
        guard isEnabled else {
            return "Disabled"
        }
        if isRunning {
            if let lastStartedAt {
                return "Request in progress since \(VPNKeepaliveTimeText.clockTime(lastStartedAt))"
            }
            return "Request in progress"
        }

        let nextText = nextRun.map {
            "next at \(VPNKeepaliveTimeText.clockTime($0))"
        }
        if let lastResult {
            if let nextText {
                return "\(lastResult.detail); \(nextText)"
            }
            return lastResult.detail
        }
        if let nextText {
            return "Waiting; \(nextText)"
        }
        return "Enabled"
    }
}

private enum VPNKeepaliveTimeText {
    static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

public final class VPNKeepaliveService: @unchecked Sendable {
    public var onStatusChange: ((VPNKeepaliveStatus) -> Void)?

    private let queue = DispatchQueue(label: "cn-pac-menubar.vpn-keepalive")
    private let statusLock = NSLock()
    private var currentStatus = VPNKeepaliveStatus.disabled
    private var configuration: VPNKeepaliveConfiguration?
    private var timer: DispatchSourceTimer?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var activeRequestID: UUID?
    private var lastResult: VPNKeepaliveResult?

    public init() {}

    public var status: VPNKeepaliveStatus {
        statusLock.lock()
        defer { statusLock.unlock() }
        return currentStatus
    }

    public func apply(settings: CNPacSettings) {
        queue.async {
            self.cancelTimer()
            self.cancelActiveRequest()
            self.lastResult = nil

            guard settings.vpnKeepaliveEnabled else {
                self.configuration = nil
                self.publish(.disabled)
                return
            }

            guard let configuration = VPNKeepaliveConfiguration(settings: settings) else {
                let result = VPNKeepaliveResult.failure(
                    completedAt: Date(),
                    message: "Invalid keepalive URL. Use an HTTP or HTTPS URL."
                )
                self.configuration = nil
                self.lastResult = result
                self.publish(VPNKeepaliveStatus(isEnabled: true, isRunning: false, lastResult: result))
                return
            }

            self.configuration = configuration
            self.runRequest(configuration: configuration)
        }
    }

    public func runNow() {
        queue.async {
            guard let configuration = self.configuration else {
                return
            }
            self.cancelTimer()
            if self.activeRequestID == nil {
                self.runRequest(configuration: configuration)
            }
        }
    }

    public func stop() {
        queue.async {
            self.cancelTimer()
            self.cancelActiveRequest()
            self.configuration = nil
            self.lastResult = nil
            self.publish(.disabled)
        }
    }

    private func runRequest(configuration: VPNKeepaliveConfiguration) {
        guard self.configuration == configuration else {
            return
        }

        cancelTimer()
        let requestID = UUID()
        let startedAt = Date()
        activeRequestID = requestID
        publish(VPNKeepaliveStatus(
            isEnabled: true,
            isRunning: true,
            lastStartedAt: startedAt,
            lastResult: lastResult
        ))

        let proxyEndpoint: PACProxyEndpoint
        do {
            proxyEndpoint = try PACProxyResolver.firstProxy(for: configuration.url, settings: configuration.settings)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failActiveRequest(
                requestID: requestID,
                configuration: configuration,
                message: message
            )
            return
        }

        var request = URLRequest(
            url: configuration.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: TimeInterval(configuration.timeoutSeconds)
        )
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("cn-pac-menubar/1.0", forHTTPHeaderField: "User-Agent")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfiguration.timeoutIntervalForRequest = TimeInterval(configuration.timeoutSeconds)
        sessionConfiguration.timeoutIntervalForResource = TimeInterval(configuration.timeoutSeconds)
        sessionConfiguration.connectionProxyDictionary = proxyEndpoint.urlSessionProxyDictionary

        let session = URLSession(configuration: sessionConfiguration)
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let errorMessage = error.map { ($0 as NSError).localizedDescription }
            self?.queue.async {
                self?.finishRequest(
                    requestID: requestID,
                    configuration: configuration,
                    startedAt: startedAt,
                    statusCode: statusCode,
                    errorMessage: errorMessage
                )
            }
        }
        self.session = session
        self.task = task
        task.resume()
    }

    private func failActiveRequest(
        requestID: UUID,
        configuration: VPNKeepaliveConfiguration,
        message: String
    ) {
        guard activeRequestID == requestID, self.configuration == configuration else {
            return
        }

        activeRequestID = nil
        task = nil
        session?.invalidateAndCancel()
        session = nil

        let result = VPNKeepaliveResult.failure(completedAt: Date(), message: message)
        lastResult = result
        scheduleNext(configuration: configuration)
    }

    private func finishRequest(
        requestID: UUID,
        configuration: VPNKeepaliveConfiguration,
        startedAt: Date,
        statusCode: Int?,
        errorMessage: String?
    ) {
        guard activeRequestID == requestID, self.configuration == configuration else {
            return
        }

        activeRequestID = nil
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil

        let completedAt = Date()
        let durationMilliseconds = max(0, Int((completedAt.timeIntervalSince(startedAt) * 1_000).rounded()))
        let result: VPNKeepaliveResult
        if let errorMessage {
            result = .failure(completedAt: completedAt, message: errorMessage)
        } else if let statusCode, (200...399).contains(statusCode) {
            result = .success(completedAt: completedAt, statusCode: statusCode, durationMilliseconds: durationMilliseconds)
        } else if let statusCode {
            result = .failure(completedAt: completedAt, message: "HTTP \(statusCode)")
        } else {
            result = .failure(completedAt: completedAt, message: "No HTTP response.")
        }

        lastResult = result
        scheduleNext(configuration: configuration)
    }

    private func scheduleNext(configuration: VPNKeepaliveConfiguration) {
        guard self.configuration == configuration else {
            return
        }

        cancelTimer()
        let nextRun = Date().addingTimeInterval(TimeInterval(configuration.intervalSeconds))
        publish(VPNKeepaliveStatus(
            isEnabled: true,
            isRunning: false,
            nextRun: nextRun,
            lastResult: lastResult
        ))

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .seconds(configuration.intervalSeconds),
            leeway: .seconds(5)
        )
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            self.timer = nil
            self.runRequest(configuration: configuration)
        }
        self.timer = timer
        timer.resume()
    }

    private func cancelTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func cancelActiveRequest() {
        activeRequestID = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func publish(_ status: VPNKeepaliveStatus) {
        statusLock.lock()
        currentStatus = status
        let handler = onStatusChange
        statusLock.unlock()

        handler?(status)
    }
}
