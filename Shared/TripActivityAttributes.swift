import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: String
        var modeIcon: String
        var progress: Double
        var distanceMeters: Double
        var etaSeconds: Int
        var paused: Bool
    }

    var tripName: String
}
