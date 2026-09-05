import CoreLocation
import Foundation

struct PersistedCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PersistedSpoofState: Codable {
    enum Mode: String, Codable {
        case stationary
        case route
    }

    let mode: Mode
    let current: PersistedCoordinate
    let route: [PersistedCoordinate]
    let nextRouteIndex: Int
    let travelMode: String
    let updatedAt: Date
    let activeTripName: String?
    let routePaused: Bool
    let loopEnabled: Bool
    let arrivalPauseSeconds: Double
    let routeRealism: String

    init(
        mode: Mode,
        current: PersistedCoordinate,
        route: [PersistedCoordinate],
        nextRouteIndex: Int,
        travelMode: String,
        updatedAt: Date,
        activeTripName: String? = nil,
        routePaused: Bool = false,
        loopEnabled: Bool = false,
        arrivalPauseSeconds: Double = 0,
        routeRealism: String = RouteRealism.balanced.rawValue
    ) {
        self.mode = mode
        self.current = current
        self.route = route
        self.nextRouteIndex = nextRouteIndex
        self.travelMode = travelMode
        self.updatedAt = updatedAt
        self.activeTripName = activeTripName
        self.routePaused = routePaused
        self.loopEnabled = loopEnabled
        self.arrivalPauseSeconds = arrivalPauseSeconds
        self.routeRealism = routeRealism
    }

    private enum CodingKeys: String, CodingKey {
        case mode, current, route, nextRouteIndex, travelMode, updatedAt
        case activeTripName, routePaused, loopEnabled, arrivalPauseSeconds, routeRealism
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(Mode.self, forKey: .mode)
        current = try container.decode(PersistedCoordinate.self, forKey: .current)
        route = try container.decode([PersistedCoordinate].self, forKey: .route)
        nextRouteIndex = try container.decode(Int.self, forKey: .nextRouteIndex)
        travelMode = try container.decode(String.self, forKey: .travelMode)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        activeTripName = try container.decodeIfPresent(String.self, forKey: .activeTripName)
        routePaused = try container.decodeIfPresent(Bool.self, forKey: .routePaused) ?? false
        loopEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
        arrivalPauseSeconds = try container.decodeIfPresent(Double.self, forKey: .arrivalPauseSeconds) ?? 0
        routeRealism = try container.decodeIfPresent(String.self, forKey: .routeRealism)
            ?? RouteRealism.balanced.rawValue
    }
}

enum SessionPersistence {
    private static let key = "locationsim.personal.persisted-session.v1"

    static func load() -> PersistedSpoofState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedSpoofState.self, from: data)
    }

    static func save(_ state: PersistedSpoofState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
