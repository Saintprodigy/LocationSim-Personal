import Foundation

struct LocationSimBackup: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String
    let trips: [SavedTrip]
    let folders: [TripFolder]
    let favorites: [SavedPlace]
    let recents: [SavedPlace]
    let speedPositions: [String: Double]
    let mapStyleIndex: Int
}

enum LibraryBackup {
    static func make(
        trips: [SavedTrip],
        folders: [TripFolder],
        favorites: [SavedPlace],
        recents: [SavedPlace],
        speedPositions: [String: Double],
        mapStyleIndex: Int
    ) -> LocationSimBackup {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return LocationSimBackup(
            schemaVersion: 1,
            createdAt: Date(),
            appVersion: version,
            trips: trips,
            folders: folders,
            favorites: favorites,
            recents: recents,
            speedPositions: speedPositions,
            mapStyleIndex: mapStyleIndex
        )
    }

    static func write(_ backup: LocationSimBackup) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let stamp = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationSim-Backup-\(stamp).locationsimbackup")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func read(_ sourceURL: URL) throws -> LocationSimBackup {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LocationSimBackup.self, from: data)
        guard backup.schemaVersion == 1 else {
            throw BackupError.unsupportedVersion(backup.schemaVersion)
        }
        return backup
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This backup uses unsupported format version \(version)."
        }
    }
}
