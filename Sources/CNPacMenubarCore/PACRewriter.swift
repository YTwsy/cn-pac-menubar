import Foundation

public struct PACRewriteResult: Equatable, Sendable {
    public var content: String
    public var changedProxyRules: Bool
    public var warnings: [String]

    public init(content: String, changedProxyRules: Bool, warnings: [String] = []) {
        self.content = content
        self.changedProxyRules = changedProxyRules
        self.warnings = warnings
    }
}

public enum PACRewriter {
    public static func rewrite(_ pac: String, settings: CNPacSettings) -> PACRewriteResult {
        let proxyExpression = settings.pacProxyExpression.escapedForJavaScriptString()
        let replacement = "return \"\(proxyExpression)\";"

        var warnings: [String] = []
        var content = pac
        var changed = false

        let proxyReturnPattern = #"return\s+"(?:SOCKS5|SOCKS|PROXY|HTTPS|HTTP)\s+[^"]*";"#
        if let regex = try? NSRegularExpression(pattern: proxyReturnPattern) {
            let range = NSRange(location: 0, length: (content as NSString).length)
            let matchCount = regex.numberOfMatches(in: content, range: range)
            if matchCount > 0 {
                content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: replacement)
                changed = true
            }
        }

        if content.contains("%mixed-port%") {
            content = content.replacingOccurrences(of: "%mixed-port%", with: "\(settings.httpPort)")
            changed = true
        }

        if !changed {
            warnings.append("No safe proxy rule pattern was found; serving the PAC unchanged.")
        }

        return PACRewriteResult(content: content, changedProxyRules: changed, warnings: warnings)
    }
}

extension String {
    func escapedForJavaScriptString() -> String {
        var result = ""
        for character in self {
            switch character {
            case "\\":
                result.append("\\\\")
            case "\"":
                result.append("\\\"")
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            default:
                result.append(character)
            }
        }
        return result
    }
}
