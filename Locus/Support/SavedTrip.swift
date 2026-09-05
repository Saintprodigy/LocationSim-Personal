import CoreLocation
import Foundation

enum RouteRealism: String, CaseIterable, Codable, Identifiable {
    case smooth
    case balanced
    case natural

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return "Smooth"
        case .balanced: return "Balanced"
        case .natural: return "Natural"
        }
    }

    var speedVariation: ClosedRange<Double> {
        switch self {
        case .smooth: return 0.99...1.01
        case .balanced: return 0.96...1.04
        case .natural: return 0.92...1.07
        }
    }

    var coordinateVariationMeters: Double {
        switch self {
        case .smooth: return 0
        case .balanced: return 0.45
        case .natural: return 1.1
        }
    }
}

struct TripStop: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var coordinate: PersistedCoordinate

    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = PersistedCoordinate(coordinate)
    }
}

struct SavedTrip: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var travelMode: String
    var route: [PersistedCoordinate]
    var speedPosition: Double?
    var folderID: UUID?
    var tags: [String]
    var stops: [TripStop]
    var loopEnabled: Bool
    var arrivalPauseSeconds: Double
    var realism: RouteRealism
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        travelMode: TravelMode,
        coordinates: [CLLocationCoordinate2D],
        speedPosition: Double? = nil,
        folderID: UUID? = nil,
        tags: [String] = [],
        stops: [TripStop] = [],
        loopEnabled: Bool = false,
        arrivalPauseSeconds: Double = 0,
        realism: RouteRealism = .balanced,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.travelMode = travelMode.rawValue
        route = coordinates.map(PersistedCoordinate.init)
        self.speedPosition = speedPosition
        self.folderID = folderID
        self.tags = tags
        self.stops = stops
        self.loopEnabled = loopEnabled
        self.arrivalPauseSeconds = arrivalPauseSeconds
        self.realism = realism
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, travelMode, route, speedPosition, folderID, tags, stops
        case loopEnabled, arrivalPauseSeconds, realism, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        travelMode = try values.decode(String.self, forKey: .travelMode)
        route = try values.decode([PersistedCoordinate].self, forKey: .route)
        speedPosition = try values.decodeIfPresent(Double.self, forKey: .speedPosition)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        stops = try values.decodeIfPresent([TripStop].self, forKey: .stops) ?? []
        loopEnabled = try values.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
        arrivalPauseSeconds = try values.decodeIfPresent(Double.self, forKey: .arrivalPauseSeconds) ?? 0
        realism = try values.decodeIfPresent(RouteRealism.self, forKey: .realism) ?? .balanced
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var coordinates: [CLLocationCoordinate2D] {
        route.map(\.coordinate)
    }

    var mode: TravelMode {
        TravelMode(rawValue: travelMode) ?? .walk
    }

    var distanceMeters: CLLocationDistance {
        zip(route, route.dropFirst()).reduce(0) { total, pair in
            let start = pair.0.coordinate
            let end = pair.1.coordinate
            return total + CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        }
    }

    var normalizedTags: [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

enum SavedTripStore {
    private static let folderName = "LocationSim Personal"
    private static let fileName = "SavedTrips-v1.json"

    static func load() -> [SavedTrip] {
        guard let data = try? Data(contentsOf: fileURL),
              let trips = try? JSONDecoder().decode([SavedTrip].self, from: data) else {
            return []
        }
        return trips.filter { $0.route.count >= 2 }
    }

    static func save(_ trips: [SavedTrip]) throws {
        let manager = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(trips)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
