import ActivityKit
import Foundation

@MainActor
final class TripActivityManager {
    private var activity: Activity<TripActivityAttributes>?
    private var lastUpdate = Date.distantPast

    func start(name: String, state: TripActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            activity = try Activity.request(
                attributes: TripActivityAttributes(tripName: name),
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(20)),
                pushType: nil
            )
            lastUpdate = Date()
        } catch {
            activity = nil
        }
    }

    func update(_ state: TripActivityAttributes.ContentState, force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastUpdate) >= 1 else { return }
        lastUpdate = now
        Task {
            await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(20)))
        }
    }

    func end(finalState: TripActivityAttributes.ContentState? = nil) {
        guard let activity else { return }
        self.activity = nil
        Task {
            let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60)))
        }
    }
}
