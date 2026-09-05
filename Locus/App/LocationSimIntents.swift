import AppIntents
import Foundation

struct SavedTripEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved Trip")
    static var defaultQuery = SavedTripEntityQuery()

    let id: UUID
    let name: String
    let mode: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(mode)")
    }

    init(_ trip: SavedTrip) {
        id = trip.id
        name = trip.name
        mode = trip.mode.title
    }
}

struct SavedTripEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedTripEntity] {
        let wanted = Set(identifiers)
        return SavedTripStore.load().filter { wanted.contains($0.id) }.map(SavedTripEntity.init)
    }

    func entities(matching string: String) async throws -> [SavedTripEntity] {
        SavedTripStore.load()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(SavedTripEntity.init)
    }

    func suggestedEntities() async throws -> [SavedTripEntity] {
        SavedTripStore.load().prefix(12).map(SavedTripEntity.init)
    }
}

struct StartSavedTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Saved Trip"
    static var description = IntentDescription("Open LocationSim Personal and begin a saved route.")

    @Parameter(title: "Trip")
    var trip: SavedTripEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$trip)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "locationsim://start?trip=\(trip.id.uuidString)")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct PauseLocationTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Location Trip"
    static var description = IntentDescription("Pause the currently moving route.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "locationsim://pause")!))
    }
}

struct ResumeLocationTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Location Trip"
    static var description = IntentDescription("Resume a paused route.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "locationsim://resume")!))
    }
}

struct StopLocationSimulationIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Location Simulation"
    static var description = IntentDescription("Stop spoofing and return the device to its real location.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "locationsim://stop")!))
    }
}

struct OpenLocationLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Saved Library"
    static var description = IntentDescription("Open saved trips and locations in LocationSim Personal.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "locationsim://library")!))
    }
}

struct LocationSimShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSavedTripIntent(),
            phrases: ["Start a trip with \(.applicationName)", "Start \(\.$trip) with \(.applicationName)"],
            shortTitle: "Start Trip",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )
        AppShortcut(
            intent: PauseLocationTripIntent(),
            phrases: ["Pause \(.applicationName)"],
            shortTitle: "Pause Trip",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeLocationTripIntent(),
            phrases: ["Resume \(.applicationName)"],
            shortTitle: "Resume Trip",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopLocationSimulationIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop Spoofing",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: OpenLocationLibraryIntent(),
            phrases: ["Open my \(.applicationName) library"],
            shortTitle: "Saved Library",
            systemImageName: "folder.fill"
        )
    }
}
