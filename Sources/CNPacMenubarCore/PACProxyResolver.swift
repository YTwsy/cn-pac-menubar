import CFNetwork
import Foundation
import JavaScriptCore

enum PACProxyResolverError: LocalizedError, Equatable {
    case missingPACPath
    case unreadablePAC(String)
    case invalidPAC(String)
    case missingFindProxyForURL
    case directSelected
    case emptyProxyResult
    case unsupportedProxyDirective(String)

    var errorDescription: String? {
        switch self {
        case .missingPACPath:
            return "No PAC file is selected for strict keepalive."
        case .unreadablePAC(let path):
            return "Cannot read PAC file: \(path)"
        case .invalidPAC(let message):
            return "PAC evaluation failed: \(message)"
        case .missingFindProxyForURL:
            return "PAC file does not define FindProxyForURL."
        case .directSelected:
            return "PAC selected DIRECT; strict keepalive requires a proxy path."
        case .emptyProxyResult:
            return "PAC returned an empty proxy rule."
        case .unsupportedProxyDirective(let directive):
            return "Unsupported PAC proxy directive: \(directive)"
        }
    }
}

enum PACProxyKind: String, Equatable, Sendable {
    case http = "PROXY"
    case https = "HTTPS"
    case socks = "SOCKS"
    case socks5 = "SOCKS5"
}

struct PACProxyEndpoint: Equatable, Sendable {
    var kind: PACProxyKind
    var host: String
    var port: Int

    var displayName: String {
        "\(kind.rawValue) \(host):\(port)"
    }

    var urlSessionProxyDictionary: [AnyHashable: Any] {
        switch kind {
        case .http, .https:
            return [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port
            ]
        case .socks, .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port
            ]
        }
    }
}

enum PACProxyResolver {
    static func firstProxy(for targetURL: URL, settings: CNPacSettings) throws -> PACProxyEndpoint {
        guard let pacPath = settings.pacPath,
              !pacPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PACProxyResolverError.missingPACPath
        }

        let pac = try rewrittenPAC(at: pacPath, settings: settings)
        let proxyResult = try evaluate(pac: pac, targetURL: targetURL)
        return try firstProxy(from: proxyResult)
    }

    static func firstProxy(for targetURL: URL, pacPath: String?) throws -> PACProxyEndpoint {
        guard let pacPath, !pacPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PACProxyResolverError.missingPACPath
        }

        let pac: String
        do {
            pac = try String(contentsOfFile: pacPath, encoding: .utf8)
        } catch {
            throw PACProxyResolverError.unreadablePAC(pacPath)
        }

        let proxyResult = try evaluate(pac: pac, targetURL: targetURL)
        return try firstProxy(from: proxyResult)
    }

    private static func rewrittenPAC(at pacPath: String, settings: CNPacSettings) throws -> String {
        let pac: String
        do {
            pac = try String(contentsOfFile: pacPath, encoding: .utf8)
        } catch {
            throw PACProxyResolverError.unreadablePAC(pacPath)
        }
        return PACRewriter.rewrite(pac, settings: settings).content
    }

    static func evaluate(pac: String, targetURL: URL) throws -> String {
        guard let host = targetURL.host, !host.isEmpty else {
            throw PACProxyResolverError.invalidPAC("Target URL has no host.")
        }
        guard let context = JSContext() else {
            throw PACProxyResolverError.invalidPAC("Cannot create JavaScript context.")
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString()
        }
        context.evaluateScript(pacHelperScript)
        if let exceptionMessage {
            throw PACProxyResolverError.invalidPAC(exceptionMessage)
        }
        context.evaluateScript(pac)
        if let exceptionMessage {
            throw PACProxyResolverError.invalidPAC(exceptionMessage)
        }

        guard let function = context.objectForKeyedSubscript("FindProxyForURL"),
              !function.isUndefined else {
            throw PACProxyResolverError.missingFindProxyForURL
        }

        guard let result = function.call(withArguments: [targetURL.absoluteString, host]) else {
            throw PACProxyResolverError.invalidPAC("FindProxyForURL returned no value.")
        }
        if let exceptionMessage {
            throw PACProxyResolverError.invalidPAC(exceptionMessage)
        }
        guard let proxyResult = result.toString() else {
            throw PACProxyResolverError.invalidPAC("FindProxyForURL returned a non-string value.")
        }
        return proxyResult
    }

    static func firstProxy(from proxyResult: String) throws -> PACProxyEndpoint {
        let directives = proxyResult
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = directives.first else {
            throw PACProxyResolverError.emptyProxyResult
        }
        if first.uppercased() == "DIRECT" {
            throw PACProxyResolverError.directSelected
        }
        guard let endpoint = proxyEndpoint(from: first) else {
            throw PACProxyResolverError.unsupportedProxyDirective(first)
        }
        return endpoint
    }

    private static func proxyEndpoint(from directive: String) -> PACProxyEndpoint? {
        let parts = directive.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2,
              let kind = PACProxyKind(rawValue: parts[0].uppercased()) else {
            return nil
        }

        let endpoint = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = parseHostPort(endpoint)
        guard let host = parsed.host,
              let port = parsed.port,
              (1...65_535).contains(port) else {
            return nil
        }
        return PACProxyEndpoint(kind: kind, host: host, port: port)
    }

    private static func parseHostPort(_ endpoint: String) -> (host: String?, port: Int?) {
        if endpoint.hasPrefix("["),
           let bracket = endpoint.firstIndex(of: "]"),
           endpoint.index(after: bracket) < endpoint.endIndex,
           endpoint[endpoint.index(after: bracket)] == ":" {
            let host = String(endpoint[endpoint.index(after: endpoint.startIndex)..<bracket])
            let portStart = endpoint.index(bracket, offsetBy: 2)
            return (host, Int(endpoint[portStart...]))
        }

        guard let colon = endpoint.lastIndex(of: ":") else {
            return (nil, nil)
        }
        let host = String(endpoint[..<colon])
        let portStart = endpoint.index(after: colon)
        return (host, Int(endpoint[portStart...]))
    }

    private static let pacHelperScript = #"""
    function dnsDomainIs(host, domain) {
      return String(host).toLowerCase().endsWith(String(domain).toLowerCase());
    }
    function isPlainHostName(host) {
      return String(host).indexOf(".") === -1;
    }
    function localHostOrDomainIs(host, hostdom) {
      host = String(host).toLowerCase();
      hostdom = String(hostdom).toLowerCase();
      return host === hostdom || (host.indexOf(".") === -1 && hostdom.indexOf(host + ".") === 0);
    }
    function shExpMatch(str, shexp) {
      var escaped = String(shexp).replace(/[.+^${}()|[\]\\]/g, "\\$&");
      var pattern = "^" + escaped.replace(/\*/g, ".*").replace(/\?/g, ".") + "$";
      return new RegExp(pattern).test(String(str));
    }
    function myIpAddress() {
      return "127.0.0.1";
    }
    """#
}
