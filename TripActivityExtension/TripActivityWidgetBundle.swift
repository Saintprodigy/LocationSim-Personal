import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct TripActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripLiveActivityWidget()
    }
}

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.attributes.tripName, systemImage: context.state.modeIcon)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.paused ? "Paused" : context.state.mode)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.paused ? .orange : .mint)
                }

                ProgressView(value: min(1, max(0, context.state.progress)))
                    .tint(.mint)

                HStack {
                    Text(distanceText(context.state.distanceMeters))
                    Spacer()
                    Text(etaText(context.state.etaSeconds))
                    Spacer()
                    Link(destination: URL(string: context.state.paused ? "locationsim://resume" : "locationsim://pause")!) {
                        Image(systemName: context.state.paused ? "play.fill" : "pause.fill")
                            .frame(width: 34, height: 28)
                    }
                    Link(destination: URL(string: "locationsim://stop")!) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                            .frame(width: 34, height: 28)
                    }
                }
                .font(.caption.monospacedDigit())
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "locationsim://library"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.mode, systemImage: context.state.modeIcon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(etaText(context.state.etaSeconds))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: min(1, max(0, context.state.progress)))
                        .tint(.mint)
                }
            } compactLeading: {
                Image(systemName: context.state.modeIcon)
            } compactTrailing: {
                Text(shortETA(context.state.etaSeconds))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : context.state.modeIcon)
            }
            .widgetURL(URL(string: "locationsim://library"))
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1_000 ? String(format: "%.1f km left", meters / 1_000) : "\(Int(meters.rounded())) m left"
    }

    private func etaText(_ seconds: Int) -> String {
        seconds < 60 ? "Arriving soon" : "ETA \(seconds / 60) min"
    }

    private func shortETA(_ seconds: Int) -> String {
        seconds < 60 ? "<1m" : "\(seconds / 60)m"
    }
}
