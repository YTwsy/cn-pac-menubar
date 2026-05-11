import Foundation

public enum SettingsStoreError: LocalizedError, Equatable {
    case applicationSupportUnavailable

    public var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Application Support directory is unavailable."
        }
    }
}

public final class SettingsStore: @unchecked Sendable {
    public let appSupportDirectory: URL
    public let settingsURL: URL
    public let launcherIndexURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public convenience init(fileManager: FileManager = .default) throws {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SettingsStoreError.applicationSupportUnavailable
        }
        try self.init(appSupportDirectory: base.appendingPathComponent("cn-pac-menubar", isDirectory: true), fileManager: fileManager)
    }

    public init(appSupportDirectory: URL, fileManager: FileManager = .default) throws {
        self.appSupportDirectory = appSupportDirectory
        self.settingsURL = appSupportDirectory.appendingPathComponent("settings.json")
        self.launcherIndexURL = appSupportDirectory.appendingPathComponent("launchers.json")
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }

    public func loadSettings() -> CNPacSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return CNPacSettings()
        }
        return (try? decoder.decode(CNPacSettings.self, from: data)) ?? CNPacSettings()
    }

    public func saveSettings(_ settings: CNPacSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: [.atomic])
    }

    public func loadLauncherIndex() -> LauncherIndex {
        guard let data = try? Data(contentsOf: launcherIndexURL) else {
            return LauncherIndex()
        }
        return (try? decoder.decode(LauncherIndex.self, from: data)) ?? LauncherIndex()
    }

    public func saveLauncherIndex(_ index: LauncherIndex) throws {
        let data = try encoder.encode(index)
        try data.write(to: launcherIndexURL, options: [.atomic])
    }
}
