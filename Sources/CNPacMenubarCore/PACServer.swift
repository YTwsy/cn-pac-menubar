import Foundation
import Network

public enum PACServerState: Equatable, Sendable {
    case stopped
    case starting(port: Int)
    case running(port: Int)
    case failed(port: Int, message: String)

    public var isActive: Bool {
        switch self {
        case .starting, .running:
            return true
        case .stopped, .failed:
            return false
        }
    }

    public var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    public var port: Int? {
        switch self {
        case .stopped:
            return nil
        case .starting(let port), .running(let port), .failed(let port, _):
            return port
        }
    }

    public var displayName: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        }
    }

    public var detail: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting(let port):
            return "Starting on all interfaces:\(port)"
        case .running(let port):
            return "Running on all interfaces:\(port)"
        case .failed(let port, let message):
            return "Failed on all interfaces:\(port) - \(message)"
        }
    }
}

public final class PACServer: @unchecked Sendable {
    public typealias ContentLoader = @Sendable () throws -> String

    private let queue = DispatchQueue(label: "cn-pac-menubar.pac-server")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var port: Int?
    private var generation: UInt64 = 0
    private var currentState: PACServerState = .stopped
    private var loader: ContentLoader
    public var onStateChange: ((PACServerState) -> Void)?

    public init(loader: @escaping ContentLoader) {
        self.loader = loader
    }

    public var state: PACServerState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentState
    }

    public var isRunning: Bool {
        state.isRunning
    }

    public func updateLoader(_ loader: @escaping ContentLoader) {
        queue.async {
            self.loader = loader
        }
    }

    public func start(port: Int) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw PACServerError.invalidPort(port)
        }

        let previousListener = replaceListener(nil, nextState: .stopped)
        previousListener?.cancel()

        let parameters = Self.listenerParameters()
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        let listenerGeneration = install(listener: listener, port: port)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed(let error) = state {
                fputs("PAC server failed: \(error)\n", stderr)
            }
            self.handle(listenerState: state, port: port, generation: listenerGeneration)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        let previousListener = replaceListener(nil, nextState: .stopped)
        previousListener?.cancel()
    }

    static func listenerParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = false
        return parameters
    }

    private func install(listener: NWListener, port: Int) -> UInt64 {
        stateLock.lock()
        generation += 1
        let listenerGeneration = generation
        self.listener = listener
        self.port = port
        currentState = .starting(port: port)
        let state = currentState
        let handler = onStateChange
        stateLock.unlock()

        handler?(state)
        return listenerGeneration
    }

    private func replaceListener(_ newListener: NWListener?, nextState: PACServerState) -> NWListener? {
        stateLock.lock()
        generation += 1
        let previousListener = listener
        listener = newListener
        port = newListener == nil ? nil : nextState.port
        currentState = nextState
        let handler = onStateChange
        stateLock.unlock()

        handler?(nextState)
        return previousListener
    }

    private func handle(listenerState: NWListener.State, port: Int, generation listenerGeneration: UInt64) {
        switch listenerState {
        case .ready:
            updateState(.running(port: port), for: listenerGeneration)
        case .failed(let error):
            let failedListener = clearCurrentListener(
                for: listenerGeneration,
                nextState: .failed(port: port, message: error.localizedDescription)
            )
            failedListener?.cancel()
        case .cancelled:
            _ = clearCurrentListener(for: listenerGeneration, nextState: .stopped)
        default:
            break
        }
    }

    private func updateState(_ state: PACServerState, for listenerGeneration: UInt64) {
        stateLock.lock()
        guard listenerGeneration == generation else {
            stateLock.unlock()
            return
        }
        currentState = state
        let handler = onStateChange
        stateLock.unlock()

        handler?(state)
    }

    private func clearCurrentListener(for listenerGeneration: UInt64, nextState: PACServerState) -> NWListener? {
        stateLock.lock()
        guard listenerGeneration == generation else {
            stateLock.unlock()
            return nil
        }
        generation += 1
        let previousListener = listener
        listener = nil
        port = nil
        currentState = nextState
        let handler = onStateChange
        stateLock.unlock()

        handler?(nextState)
        return previousListener
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                self.send(status: "500 Internal Server Error", body: "PAC server read failed: \(error)", contentType: "text/plain; charset=utf-8", to: connection)
                return
            }

            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let path = Self.path(fromHTTPRequest: request)
            guard path == "/" || path == "/proxy.pac" else {
                self.send(status: "404 Not Found", body: "Not found", contentType: "text/plain; charset=utf-8", to: connection)
                return
            }

            do {
                let content = try self.loader()
                self.send(status: "200 OK", body: content, contentType: "application/x-ns-proxy-autoconfig", to: connection)
            } catch {
                self.send(status: "500 Internal Server Error", body: error.localizedDescription, contentType: "text/plain; charset=utf-8", to: connection)
            }
        }
    }

    private func send(status: String, body: String, contentType: String, to connection: NWConnection) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-cache, no-store, must-revalidate",
            "Pragma: no-cache",
            "Expires: 0",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    public static func path(fromHTTPRequest request: String) -> String {
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            return "/"
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return "/"
        }
        return String(parts[1].split(separator: "?", maxSplits: 1).first ?? "/")
    }
}

public enum PACServerError: LocalizedError, Equatable {
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid PAC server port: \(port)."
        }
    }
}
