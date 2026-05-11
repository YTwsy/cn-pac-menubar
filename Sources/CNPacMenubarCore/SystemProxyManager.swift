import Foundation

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var errorOutput: String

    public var succeeded: Bool { exitCode == 0 }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
    }
}

public enum NetworkServiceParser {
    public static func enabledServices(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }
}

public final class SystemProxyManager: @unchecked Sendable {
    private let runner: CommandRunning
    private let networksetupPath = "/usr/sbin/networksetup"
    private let scutilPath = "/usr/sbin/scutil"

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func listEnabledServices() throws -> [String] {
        let result = try runner.run(networksetupPath, arguments: ["-listallnetworkservices"])
        guard result.succeeded else {
            throw ProxyManagerError.commandFailed(result.errorOutput.nonEmptyOr(result.output))
        }
        return NetworkServiceParser.enabledServices(from: result.output)
    }

    public func applyAutoProxy(url: URL, authorizeOnFailure: Bool = true) throws -> [CommandResult] {
        let services = try listEnabledServices()
        var results: [CommandResult] = []
        for service in services {
            let setURL = try runNetworkSetup(arguments: ["-setautoproxyurl", service, url.absoluteString], authorizeOnFailure: authorizeOnFailure)
            results.append(setURL)
            guard setURL.succeeded else {
                throw ProxyManagerError.commandFailed(setURL.errorOutput.nonEmptyOr(setURL.output))
            }

            let setState = try runNetworkSetup(arguments: ["-setautoproxystate", service, "on"], authorizeOnFailure: authorizeOnFailure)
            results.append(setState)
            guard setState.succeeded else {
                throw ProxyManagerError.commandFailed(setState.errorOutput.nonEmptyOr(setState.output))
            }
        }
        return results
    }

    public func disableAutoProxy(authorizeOnFailure: Bool = true) throws -> [CommandResult] {
        let services = try listEnabledServices()
        var results: [CommandResult] = []
        for service in services {
            let result = try runNetworkSetup(arguments: ["-setautoproxystate", service, "off"], authorizeOnFailure: authorizeOnFailure)
            results.append(result)
            guard result.succeeded else {
                throw ProxyManagerError.commandFailed(result.errorOutput.nonEmptyOr(result.output))
            }
        }
        return results
    }

    public func currentProxyStatus() throws -> String {
        let result = try runner.run(scutilPath, arguments: ["--proxy"])
        guard result.succeeded else {
            throw ProxyManagerError.commandFailed(result.errorOutput.nonEmptyOr(result.output))
        }
        return result.output
    }

    public static func applyArguments(service: String, url: URL) -> [[String]] {
        [
            ["-setautoproxyurl", service, url.absoluteString],
            ["-setautoproxystate", service, "on"]
        ]
    }

    private func runNetworkSetup(arguments: [String], authorizeOnFailure: Bool) throws -> CommandResult {
        let direct = try runner.run(networksetupPath, arguments: arguments)
        guard !direct.succeeded, authorizeOnFailure else {
            return direct
        }

        let command = ([networksetupPath] + arguments).map { $0.shellSingleQuoted() }.joined(separator: " ")
        let appleScript = "do shell script \(command.appleScriptQuoted()) with administrator privileges"
        return try runner.run("/usr/bin/osascript", arguments: ["-e", appleScript])
    }
}

public enum ProxyManagerError: LocalizedError, Equatable {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "networksetup command failed." : message
        }
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }

    func shellSingleQuoted() -> String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func appleScriptQuoted() -> String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
