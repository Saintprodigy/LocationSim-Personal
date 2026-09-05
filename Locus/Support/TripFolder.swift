import Foundation

struct TripFolder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var sortIndex: Int

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}

enum TripFolderStore {
    private static let folderName = "LocationSim Personal"
    private static let fileName = "TripFolders-v1.json"

    static func load() -> [TripFolder] {
        guard let data = try? Data(contentsOf: fileURL),
              let folders = try? JSONDecoder().decode([TripFolder].self, from: data) else {
            return []
        }
        return folders.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    static func save(_ folders: [TripFolder]) throws {
        let manager = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(folders)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
