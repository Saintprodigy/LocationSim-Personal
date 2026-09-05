import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .drive: return "Drive"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var minimumSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 0.67       // 1.5 mph / about 40 min per mile
        case .run: return 1.79        // 4 mph / about 15 min per mile
        case .cycle: return 2.68      // 6 mph
        case .drive: return 2.24      // 5 mph
        }
    }

    var maximumSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 2.24       // 5 mph / about 12 min per mile
        case .run: return 5.36        // 12 mph / about 5 min per mile
        case .cycle: return 11.18     // 25 mph
        case .drive: return 35.76     // 80 mph
        }
    }

    /// A conservative acceleration limit keeps the first few updates from
    /// jumping immediately to cruising speed.
    var accelerationPerUpdate: CLLocationSpeed {
        switch self {
        case .walk: return 0.32
        case .run: return 0.55
        case .cycle: return 0.9
        case .drive: return 2.2
        }
    }

    func configuredSpeed(position: Double) -> CLLocationSpeed {
        let value = min(1, max(0, position))
        if value <= 0.5 {
            return minimumSpeed + (baseSpeed - minimumSpeed) * (value * 2)
        }
        return baseSpeed + (maximumSpeed - baseSpeed) * ((value - 0.5) * 2)
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return "Not Spoofing"
        case .connecting: return "Starting…"
        case .active: return "Spoofing"
        case .reconnecting: return "Reconnecting…"
        case .dropped: return "Interrupted"
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

struct RoutePlaybackOptions {
    var name: String = "Route"
    var loopEnabled = false
    var arrivalPauseSeconds: Double = 0
    var realism: RouteRealism = .balanced
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = min(
        2,
        max(0, UserDefaults.standard.integer(forKey: "locationsim.personal.map-style"))
    ) {
        didSet {
            UserDefaults.standard.set(mapStyleIndex, forKey: "locationsim.personal.map-style")
        }
    }
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false
    @Published private(set) var activeRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var routeProgressIndex = 0
    @Published private(set) var routeIsRunning = false
    @Published private(set) var routeIsPaused = false
    @Published private(set) var activeTripName: String?
    @Published private(set) var routeRemainingMeters: CLLocationDistance = 0
    @Published private(set) var routeETASeconds: TimeInterval = 0
    @Published private(set) var currentRouteSpeed: CLLocationSpeed = 0
    @Published private(set) var activeRouteTotalMeters: CLLocationDistance = 0

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []
    @Published private(set) var savedTrips: [SavedTrip] = []
    @Published private(set) var tripFolders: [TripFolder] = []
    @Published private(set) var speedSettingsRevision = 0

    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()
    private let audioKeeper = SilentAudioKeepAlive()
    private var lastPersistedAt = Date.distantPast
    private var restoreInProgress = false
    private var didRestorePersistedState = false
    private var routeNeedsResume = false
    private var activeRouteOptions = RoutePlaybackOptions()
    private let activityManager = TripActivityManager()

    private enum TunnelRecoveryStage {
        case idle
        case disabling
        case enabling
        case waitingForTunnel
    }

    private struct PendingTunnelAction {
        let coordinate: CLLocationCoordinate2D
        let markRecent: Bool
        let persist: Bool
    }

    private var tunnelRecoveryStage: TunnelRecoveryStage = .idle
    private var pendingTunnelAction: PendingTunnelAction?
    private var pendingLocationUpdate: PendingTunnelAction?
    private var nextPendingRetryAt = Date.distantPast
    private var lastAutomaticTunnelRecoveryAt = Date.distantPast
    private(set) var automaticTunnelRecoveryCount = 0
    private(set) var automaticTunnelEnablePulseCount = 0
    private var currentTunnelEnablePulseCount = 0

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"
    private let speedKeyPrefix = "locationsim.personal.speed-position."

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        savedTrips = SavedTripStore.load()
        tripFolders = TripFolderStore.load()
        if let saved = SessionPersistence.load() {
            pin = saved.current.coordinate
            travelMode = TravelMode(rawValue: saved.travelMode) ?? .walk
            activeRoute = saved.route.map(\.coordinate)
            routeProgressIndex = saved.nextRouteIndex
        }
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        cancelRouteForNewAction()
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    /// Restores the last stationary point or unfinished trip once the local
    /// developer tunnel is available. A force-quit cannot keep code executing,
    /// but reopening the app resumes from the most recently persisted point.
    func restoreIfNeeded(pairing: PairingStore) {
        if pendingLocationUpdate != nil {
            retryPendingLocation(pairing: pairing, immediately: true)
            return
        }
        guard (!didRestorePersistedState || routeNeedsResume), !restoreInProgress,
              (!isSpoofing || routeNeedsResume), tunnelRecoveryStage == .idle else { return }
        guard pairing.hasPairingFile, LocalDevVPN.isConnected else { return }
        guard let saved = SessionPersistence.load() else {
            didRestorePersistedState = true
            return
        }

        restoreInProgress = true
        travelMode = TravelMode(rawValue: saved.travelMode) ?? .walk
        let current = saved.current.coordinate
        pin = current

        guard apply(current, pairing: pairing, markRecent: false, persist: false) else {
            restoreInProgress = false
            return
        }

        didRestorePersistedState = true
        restoreInProgress = false

        let route = saved.route.map(\.coordinate)
        if saved.mode == .route, route.count >= 2 {
            let index = min(max(saved.nextRouteIndex, 1), route.count - 1)
            let remaining = [current] + Array(route[index...])
            if remaining.count >= 2 {
                let options = RoutePlaybackOptions(
                    name: saved.activeTripName ?? "Restored Route",
                    loopEnabled: saved.loopEnabled,
                    arrivalPauseSeconds: saved.arrivalPauseSeconds,
                    realism: RouteRealism(rawValue: saved.routeRealism) ?? .balanced
                )
                followRoute(remaining, pairing: pairing, options: options)
                setRoutePaused(saved.routePaused)
            }
        } else {
            persistCurrentState(force: true)
        }
    }

    func stop(pairing: PairingStore) {
        pendingLocationUpdate = nil
        routeNeedsResume = false
        tunnelRecoveryStage = .idle
        pendingTunnelAction = nil
        currentTunnelEnablePulseCount = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        routeTask?.cancel()
        routeTask = nil
        activeRoute = []
        routeProgressIndex = 0
        routeIsRunning = false
        routeIsPaused = false
        activeTripName = nil
        routeRemainingMeters = 0
        routeETASeconds = 0
        currentRouteSpeed = 0
        activeRouteTotalMeters = 0
        activeRouteOptions = RoutePlaybackOptions()
        activityManager.end()
        stopJoystick()
        stopResend()
        stopHealth()
        isBusy = true
        let result = LocationEngine.clear(keepConnection: true)
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            pin = nil
            status = .idle
            endBackground()
            audioKeeper.stop()
            SessionPersistence.clear()
            didRestorePersistedState = true
            // Keep location updates running so the map puck / locate button
            // can return to the real GPS fix (not the leftover pin).
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
        }
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        cancelRouteForNewAction()
        let start = simulated ?? pin ?? locationKeeper.lastKnownCoordinate
        guard let start else {
            lastError = "Drop a pin or teleport somewhere before using the joystick."
            return
        }
        if simulated == nil {
            apply(start, pairing: pairing, markRecent: false)
        }
        joystickActive = true
        joystickTimer?.invalidate()
        joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickJoystick(pairing: pairing)
            }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(
        _ coordinates: [CLLocationCoordinate2D],
        pairing: PairingStore,
        options: RoutePlaybackOptions = RoutePlaybackOptions()
    ) {
        guard pairing.hasPairingFile, coordinates.count >= 2 else { return }
        pendingLocationUpdate = nil
        routeNeedsResume = false
        routeTask?.cancel()
        stopJoystick()
        activeRoute = coordinates
        routeProgressIndex = 1
        routeIsRunning = true
        routeIsPaused = false
        activeTripName = options.name
        activeRouteOptions = options
        activeRouteTotalMeters = routeDistance(coordinates)
        routeRemainingMeters = activeRouteTotalMeters
        routeETASeconds = routeRemainingMeters / max(0.25, speedMetersPerSecond(for: travelMode))
        activityManager.start(name: options.name, state: tripActivityState())
        routeTask = Task { [weak self] in
            guard let self else { return }
            var current = coordinates[0]
            var currentMode = self.travelMode
            var currentSpeed = max(0.35, self.speedMetersPerSecond(for: currentMode) * 0.45)
            var cycleCoordinates = coordinates
            let updateInterval = 0.25
            guard self.apply(current, pairing: pairing, markRecent: true) else {
                self.markRouteInterrupted()
                return
            }

            repeat {
                for targetIndex in 1..<cycleCoordinates.count {
                    if Task.isCancelled { return }
                    let target = cycleCoordinates[targetIndex]
                    self.routeProgressIndex = targetIndex
                    while true {
                        if Task.isCancelled { return }
                        while self.routeIsPaused, !Task.isCancelled {
                            self.currentRouteSpeed = 0
                            try? await Task.sleep(nanoseconds: 250_000_000)
                        }
                        if Task.isCancelled { return }

                        let distance = self.distance(from: current, to: target)
                        guard distance > 0.35 else { break }

                        let liveMode = self.travelMode
                        let baseSpeed = self.speedMetersPerSecond(for: liveMode)
                        let cornerFactor = self.cornerSpeedFactor(
                            current: current,
                            targetIndex: targetIndex,
                            coordinates: cycleCoordinates,
                            speed: currentSpeed,
                            mode: liveMode
                        )
                        let requestedSpeed = baseSpeed
                            * Double.random(in: options.realism.speedVariation)
                            * cornerFactor
                        if liveMode != currentMode {
                            // A switch to a slower method should be visible immediately.
                            // Faster methods still ramp up using their realistic acceleration.
                            currentSpeed = min(currentSpeed, requestedSpeed * 1.15)
                            currentMode = liveMode
                        }
                        let delta = requestedSpeed - currentSpeed
                        let limitedDelta = min(
                            liveMode.accelerationPerUpdate,
                            max(-liveMode.accelerationPerUpdate, delta)
                        )
                        currentSpeed = max(0.25, currentSpeed + limitedDelta)

                        let stepMeters = min(distance, currentSpeed * updateInterval)
                        let fraction = min(1, stepMeters / distance)
                        let idealCoordinate = CLLocationCoordinate2D(
                            latitude: current.latitude + (target.latitude - current.latitude) * fraction,
                            longitude: current.longitude + (target.longitude - current.longitude) * fraction
                        )
                        let appliedCoordinate = self.variedCoordinate(
                            idealCoordinate,
                            maximumMeters: options.realism.coordinateVariationMeters
                        )
                        try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
                        if Task.isCancelled { return }
                        guard self.apply(appliedCoordinate, pairing: pairing, markRecent: false) else {
                            self.markRouteInterrupted()
                            return
                        }
                        current = idealCoordinate
                        self.currentRouteSpeed = currentSpeed
                        self.routeRemainingMeters = self.remainingDistance(
                            from: current,
                            targetIndex: targetIndex,
                            coordinates: cycleCoordinates
                        )
                        self.routeETASeconds = self.routeRemainingMeters / max(0.25, currentSpeed)
                        self.updateTripActivity()
                    }
                    current = target
                    guard self.apply(target, pairing: pairing, markRecent: false) else {
                        self.markRouteInterrupted()
                        return
                    }
                    self.routeProgressIndex = targetIndex + 1
                    self.persistCurrentState(force: true)
                    self.updateTripActivity(force: true)
                }

                self.routeRemainingMeters = 0
                self.routeETASeconds = 0
                self.currentRouteSpeed = 0
                if options.arrivalPauseSeconds > 0 {
                    var remainingPause = options.arrivalPauseSeconds
                    while remainingPause > 0, !Task.isCancelled {
                        if !self.routeIsPaused { remainingPause -= 0.25 }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }

                if options.loopEnabled, !Task.isCancelled {
                    cycleCoordinates.reverse()
                    self.activeRoute = cycleCoordinates
                    current = cycleCoordinates[0]
                    self.routeProgressIndex = 1
                    self.activeRouteTotalMeters = self.routeDistance(cycleCoordinates)
                    self.routeRemainingMeters = self.activeRouteTotalMeters
                    self.routeETASeconds = self.routeRemainingMeters
                        / max(0.25, self.speedMetersPerSecond(for: self.travelMode))
                    self.updateTripActivity(force: true)
                }
            } while options.loopEnabled && !Task.isCancelled

            guard !Task.isCancelled else { return }
            let completedActivityState = TripActivityAttributes.ContentState(
                mode: self.travelMode.title,
                modeIcon: self.travelMode.icon,
                progress: 1,
                distanceMeters: 0,
                etaSeconds: 0,
                paused: false
            )
            self.routeIsRunning = false
            self.routeIsPaused = false
            self.routeTask = nil
            self.activeRoute = []
            self.routeProgressIndex = 0
            self.activeTripName = nil
            self.routeRemainingMeters = 0
            self.routeETASeconds = 0
            self.currentRouteSpeed = 0
            self.activeRouteTotalMeters = 0
            self.activeRouteOptions = RoutePlaybackOptions()
            self.activityManager.end(finalState: completedActivityState)
            self.persistCurrentState(force: true)
        }
    }

    func toggleRoutePause() {
        guard routeIsRunning else { return }
        routeIsPaused.toggle()
        persistCurrentState(force: true)
        updateTripActivity(force: true)
    }

    func setRoutePaused(_ paused: Bool) {
        guard routeIsRunning else { return }
        routeIsPaused = paused
        persistCurrentState(force: true)
        updateTripActivity(force: true)
    }

    func selectTravelMode(_ mode: TravelMode) {
        guard travelMode != mode else { return }
        travelMode = mode
        persistCurrentState(force: true)
        updateTripActivity(force: true)
    }

    func saveTrip(
        name: String,
        coordinates: [CLLocationCoordinate2D],
        mode: TravelMode? = nil,
        stops: [TripStop] = []
    ) {
        guard coordinates.count >= 2 else {
            lastError = "Build, draw, or import a route before saving it."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty
            ? "Trip \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            : trimmed
        let trip = SavedTrip(
            name: title,
            travelMode: mode ?? travelMode,
            coordinates: coordinates,
            speedPosition: speedPosition(for: mode ?? travelMode),
            stops: stops
        )
        savedTrips.insert(trip, at: 0)
        if savedTrips.count > 50 {
            savedTrips = Array(savedTrips.prefix(50))
        }
        persistSavedTrips()
    }

    func startSavedTrip(_ trip: SavedTrip, pairing: PairingStore) {
        travelMode = trip.mode
        if let savedSpeed = trip.speedPosition {
            setSpeedPosition(savedSpeed, for: trip.mode)
        }
        followRoute(
            trip.coordinates,
            pairing: pairing,
            options: RoutePlaybackOptions(
                name: trip.name,
                loopEnabled: trip.loopEnabled,
                arrivalPauseSeconds: trip.arrivalPauseSeconds,
                realism: trip.realism
            )
        )
    }

    func speedPosition(for mode: TravelMode) -> Double {
        let key = speedKeyPrefix + mode.rawValue
        guard UserDefaults.standard.object(forKey: key) != nil else { return 0.5 }
        return min(1, max(0, UserDefaults.standard.double(forKey: key)))
    }

    func setSpeedPosition(_ position: Double, for mode: TravelMode) {
        let normalized = min(1, max(0, position))
        UserDefaults.standard.set(normalized, forKey: speedKeyPrefix + mode.rawValue)
        speedSettingsRevision &+= 1
    }

    func speedMetersPerSecond(for mode: TravelMode) -> CLLocationSpeed {
        mode.configuredSpeed(position: speedPosition(for: mode))
    }

    func speedDescription(for mode: TravelMode, position: Double? = nil) -> String {
        let speed = mode.configuredSpeed(position: position ?? speedPosition(for: mode))
        if mode == .walk || mode == .run {
            let totalSeconds = Int((1_609.344 / speed).rounded())
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%d:%02d / mile", minutes, seconds)
        }
        return String(format: "%.0f mph", speed * 2.236_936)
    }

    var routeProgressFraction: Double {
        guard activeRouteTotalMeters > 0 else {
            return routeIsRunning && routeRemainingMeters <= 0 ? 1 : 0
        }
        return min(1, max(0, 1 - (routeRemainingMeters / activeRouteTotalMeters)))
    }

    func renameTrip(_ trip: SavedTrip, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = savedTrips.firstIndex(where: { $0.id == trip.id }) else { return }
        savedTrips[index].name = trimmed
        savedTrips[index].updatedAt = Date()
        persistSavedTrips()
    }

    func removeTrip(_ trip: SavedTrip) {
        savedTrips.removeAll { $0.id == trip.id }
        persistSavedTrips()
    }

    func updateTrip(_ trip: SavedTrip) {
        guard let index = savedTrips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        updated.tags = updated.normalizedTags
        updated.arrivalPauseSeconds = min(600, max(0, updated.arrivalPauseSeconds))
        updated.updatedAt = Date()
        savedTrips[index] = updated
        persistSavedTrips()
    }

    func duplicateTrip(_ trip: SavedTrip) {
        var duplicate = trip
        duplicate.id = UUID()
        duplicate.name = "\(trip.name) Copy"
        duplicate.createdAt = Date()
        duplicate.updatedAt = Date()
        savedTrips.insert(duplicate, at: 0)
        persistSavedTrips()
    }

    func reverseTrip(_ trip: SavedTrip) {
        guard let index = savedTrips.firstIndex(where: { $0.id == trip.id }) else { return }
        savedTrips[index].route.reverse()
        savedTrips[index].stops.reverse()
        savedTrips[index].updatedAt = Date()
        persistSavedTrips()
    }

    func moveTrip(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.sorted().map { savedTrips[$0] }
        for index in offsets.sorted(by: >) {
            savedTrips.remove(at: index)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let insertion = min(savedTrips.count, max(0, destination - removedBeforeDestination))
        savedTrips.insert(contentsOf: moving, at: insertion)
        persistSavedTrips()
    }

    @discardableResult
    func createTripFolder(name: String) -> TripFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = TripFolder(name: trimmed, sortIndex: tripFolders.count)
        tripFolders.append(folder)
        persistTripFolders()
        return folder
    }

    func renameTripFolder(_ folder: TripFolder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tripFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        tripFolders[index].name = trimmed
        persistTripFolders()
    }

    func removeTripFolder(_ folder: TripFolder) {
        tripFolders.removeAll { $0.id == folder.id }
        for index in savedTrips.indices where savedTrips[index].folderID == folder.id {
            savedTrips[index].folderID = nil
            savedTrips[index].updatedAt = Date()
        }
        persistTripFolders()
        persistSavedTrips()
    }

    func replaceLibrary(
        trips: [SavedTrip],
        folders: [TripFolder],
        favorites: [SavedPlace],
        recents: [SavedPlace],
        speedPositions: [String: Double],
        mapStyleIndex: Int
    ) {
        savedTrips = trips.filter { $0.route.count >= 2 }
        tripFolders = folders
        self.favorites = favorites
        self.recents = recents
        self.mapStyleIndex = min(2, max(0, mapStyleIndex))
        persistSavedTrips()
        persistTripFolders()
        SavedPlace.save(favorites, key: favoritesKey)
        SavedPlace.save(recents, key: recentsKey)
        for mode in TravelMode.allCases {
            if let position = speedPositions[mode.rawValue] {
                setSpeedPosition(position, for: mode)
            }
        }
    }

    /// Verify the existing local session first. Switching the Internet interface
    /// does not necessarily break the on-device VPN; closing a good session can
    /// make an otherwise successful cellular handoff impossible to recover.
    func networkPathDidChange(pairing: PairingStore) {
        if pendingLocationUpdate != nil {
            retryPendingLocation(pairing: pairing, immediately: true)
            return
        }
        guard simulated != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self, let coordinate = self.simulated else { return }
            guard LocalDevVPN.isConnected else {
                self.status = .dropped("Reconnect LocalDevVPN")
                return
            }
            self.status = .reconnecting
            let recovered = self.apply(
                coordinate,
                pairing: pairing,
                markRecent: false,
                reportError: false
            )
            if recovered, self.routeNeedsResume { self.restoreIfNeeded(pairing: pairing) }
        }
    }

    /// LocalDevVPN 1.3 exposes enable/disable callback URLs. A path handoff can
    /// leave its utun interface visible while the RSD socket behind it is stale.
    /// In that case, restart the local-only tunnel and replay the exact action
    /// that failed instead of making the user manually switch apps.
    @discardableResult
    func handleTunnelRecoveryCallback(pairing: PairingStore) -> Bool {
        switch tunnelRecoveryStage {
        case .idle, .waitingForTunnel:
            return false
        case .disabling:
            tunnelRecoveryStage = .enabling
            Task { @MainActor in
                // The helper returns after one second, which can still be inside
                // iOS's disconnect transition. Give the provider time to stop
                // before asking it to start on the new interface.
                try? await Task.sleep(for: .milliseconds(1_200))
                guard self.tunnelRecoveryStage == .enabling else { return }
                self.currentTunnelEnablePulseCount = 1
                self.automaticTunnelEnablePulseCount += 1
                LocalDevVPN.enableThenReturn()
            }
            return true
        case .enabling:
            // LocalDevVPN 1.3 returns after one second even when its asynchronous
            // preference load has not started the provider yet. Re-entering its
            // documented enable URL gives that work a bounded foreground window.
            if !LocalDevVPN.isConnected, currentTunnelEnablePulseCount < 5 {
                currentTunnelEnablePulseCount += 1
                automaticTunnelEnablePulseCount += 1
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard self.tunnelRecoveryStage == .enabling else { return }
                    LocalDevVPN.enableThenReturn()
                }
                return true
            }
            tunnelRecoveryStage = .waitingForTunnel
            Task { @MainActor in
                await self.finishAutomaticTunnelRecovery(pairing: pairing)
            }
            return true
        }
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    @discardableResult
    private func apply(
        _ coordinate: CLLocationCoordinate2D,
        pairing: PairingStore,
        markRecent: Bool,
        persist: Bool = true,
        reportError: Bool = true,
        allowAutomaticTunnelRepair: Bool = true
    ) -> Bool {
        if status == .idle || status.isDropped {
            status = .connecting
        }
        isBusy = true
        let result = LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            pendingLocationUpdate = nil
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.start()
            audioKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            if markRecent {
                pushRecent(coordinate)
            }
            if persist {
                persistCurrentState(force: markRecent)
            }
            return true
        case .failure(let error):
            var message = LocationEngine.userMessage(for: error)
            if error == .tunnelCreate, NetworkPathObserver.shared.isCellularOnly {
                message = "The local developer tunnel could not start on cellular. Keep LocalDevVPN connected, briefly turn Mobile Data off, then return here. Your destination is remembered and will retry automatically. Once the status says Active, turn Mobile Data back on. If this still fails, Wi-Fi may be needed to establish the session on this iOS version.\n\n" + message
            }
            switch error {
            case .tunnelCreate, .remoteServer, .simulationCreate, .locationSet:
                pendingLocationUpdate = PendingTunnelAction(
                    coordinate: coordinate, markRecent: markRecent, persist: persist
                )
                nextPendingRetryAt = Date().addingTimeInterval(12)
                startHealth(pairing: pairing)
            default:
                break
            }
            if allowAutomaticTunnelRepair,
               beginAutomaticTunnelRecovery(
                    coordinate: coordinate,
                    markRecent: markRecent,
                    persist: persist
               ) {
                return false
            }
            if reportError {
                lastError = message
            }
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                if reportError {
                    postDropNotification(message)
                }
            } else {
                status = .dropped("Waiting for developer connection")
            }
            return false
        }
    }

    private func beginAutomaticTunnelRecovery(
        coordinate: CLLocationCoordinate2D,
        markRecent: Bool,
        persist: Bool
    ) -> Bool {
        // Experimental callbacks have not passed device validation: the helper
        // can fail to return, leaving the UI stuck on Starting. Keep automatic
        // app switching opt-in for developer testing until it is proven.
        guard ProcessInfo.processInfo.environment["LOCATIONSIM_TEST_VPN_REPAIR"] == "1" else { return false }
        guard tunnelRecoveryStage == .idle, LocalDevVPN.isInstalled else { return false }
        // Prevent a broken or outdated helper from bouncing between apps forever.
        guard Date().timeIntervalSince(lastAutomaticTunnelRecoveryAt) >= 30 else { return false }

        lastAutomaticTunnelRecoveryAt = Date()
        automaticTunnelRecoveryCount += 1
        currentTunnelEnablePulseCount = 0
        pendingTunnelAction = PendingTunnelAction(
            coordinate: coordinate,
            markRecent: markRecent,
            persist: persist
        )
        status = simulated == nil ? .connecting : .reconnecting
        lastError = nil

        if LocalDevVPN.isConnected {
            tunnelRecoveryStage = .disabling
            LocalDevVPN.disableThenReturn()
        } else {
            tunnelRecoveryStage = .enabling
            currentTunnelEnablePulseCount = 1
            automaticTunnelEnablePulseCount += 1
            LocalDevVPN.enableThenReturn()
        }
        return true
    }

    private func finishAutomaticTunnelRecovery(pairing: PairingStore) async {
        // The helper's callback is intentionally quick; the packet-tunnel
        // extension may need several more seconds before 10.7.0.1 is usable.
        for _ in 0..<12 where !LocalDevVPN.isConnected {
            guard tunnelRecoveryStage == .waitingForTunnel else { return }
            try? await Task.sleep(for: .seconds(1))
        }

        // Two bounded handshake attempts cover the short RSD settle window but
        // avoid an endless app-switch or retry loop when the helper itself fails.
        if LocalDevVPN.isConnected, let pending = pendingTunnelAction {
            for attempt in 0..<2 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(2))
                }
                LocationEngine.resetConnection()
                if apply(
                    pending.coordinate,
                    pairing: pairing,
                    markRecent: pending.markRecent,
                    persist: pending.persist,
                    reportError: false,
                    allowAutomaticTunnelRepair: false
                ) {
                    tunnelRecoveryStage = .idle
                    pendingTunnelAction = nil
                    currentTunnelEnablePulseCount = 0
                    if routeNeedsResume {
                        restoreIfNeeded(pairing: pairing)
                    }
                    return
                }
            }
        }

        let pending = pendingTunnelAction
        tunnelRecoveryStage = .idle
        pendingTunnelAction = nil
        currentTunnelEnablePulseCount = 0
        guard let pending else { return }
        LocationEngine.resetConnection()
        _ = apply(
            pending.coordinate,
            pairing: pairing,
            markRecent: pending.markRecent,
            persist: pending.persist,
            reportError: true,
            allowAutomaticTunnelRepair: false
        )
    }

    private func cancelRouteForNewAction() {
        pendingLocationUpdate = nil
        routeNeedsResume = false
        routeTask?.cancel()
        routeTask = nil
        activeRoute = []
        routeProgressIndex = 0
        routeIsRunning = false
        routeIsPaused = false
        activeTripName = nil
        routeRemainingMeters = 0
        routeETASeconds = 0
        currentRouteSpeed = 0
        activeRouteTotalMeters = 0
        activeRouteOptions = RoutePlaybackOptions()
        activityManager.end()
        persistCurrentState(force: true)
    }

    private func markRouteInterrupted() {
        routeTask = nil
        routeNeedsResume = true
        // Preserve the unfinished route so returning after the tunnel
        // reconnects resumes from the last coordinate that succeeded.
        routeIsRunning = true
        didRestorePersistedState = false
        activityManager.end()
        persistCurrentState(force: true)
    }

    /// An initial failure has no simulated coordinate to restore. Keep the
    /// requested update separately: it must never be presented as successful GPS.
    private func retryPendingLocation(pairing: PairingStore, immediately: Bool = false) {
        guard let pending = pendingLocationUpdate,
              tunnelRecoveryStage == .idle,
              immediately || Date() >= nextPendingRetryAt,
              pairing.hasPairingFile, LocalDevVPN.isConnected else { return }
        nextPendingRetryAt = Date().addingTimeInterval(12)
        let needsRoute = routeNeedsResume
        let route = activeRoute
        let options = activeRouteOptions
        let wasPaused = routeIsPaused
        guard apply(pending.coordinate, pairing: pairing,
                    markRecent: pending.markRecent, persist: pending.persist,
                    reportError: false, allowAutomaticTunnelRepair: false) else { return }
        if needsRoute, route.count >= 2 {
            let index = min(max(routeProgressIndex, 1), route.count - 1)
            followRoute([pending.coordinate] + Array(route[index...]),
                        pairing: pairing, options: options)
            setRoutePaused(wasPaused)
        }
    }

    #if DEBUG
    /// Explicit test hook: simulates a stopped route worker, not a physical outage.
    func interruptRouteWorkerForTest() {
        guard routeIsRunning else { return }
        routeTask?.cancel()
        markRouteInterrupted()
    }
    #endif

    private func persistCurrentState(force: Bool = false) {
        guard let simulated else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersistedAt) >= 2 else { return }
        lastPersistedAt = now

        let mode: PersistedSpoofState.Mode = routeIsRunning && activeRoute.count >= 2
            ? .route : .stationary
        SessionPersistence.save(PersistedSpoofState(
            mode: mode,
            current: PersistedCoordinate(simulated),
            route: mode == .route ? activeRoute.map(PersistedCoordinate.init) : [],
            nextRouteIndex: mode == .route ? routeProgressIndex : 0,
            travelMode: travelMode.rawValue,
            updatedAt: now,
            activeTripName: mode == .route ? activeTripName : nil,
            routePaused: mode == .route && routeIsPaused,
            loopEnabled: mode == .route && activeRouteOptions.loopEnabled,
            arrivalPauseSeconds: mode == .route ? activeRouteOptions.arrivalPauseSeconds : 0,
            routeRealism: activeRouteOptions.realism.rawValue
        ))
    }

    private func tripActivityState() -> TripActivityAttributes.ContentState {
        return TripActivityAttributes.ContentState(
            mode: travelMode.title,
            modeIcon: travelMode.icon,
            progress: routeProgressFraction,
            distanceMeters: max(0, routeRemainingMeters),
            etaSeconds: max(0, Int(routeETASeconds.rounded())),
            paused: routeIsPaused
        )
    }

    private func updateTripActivity(force: Bool = false) {
        guard routeIsRunning else { return }
        activityManager.update(tripActivityState(), force: force)
    }

    private func tickJoystick(pairing: PairingStore) {
        guard joystickActive, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude
        let speed = speedMetersPerSecond(for: travelMode)
            * min(1.0, magnitude)
            * Double.random(in: 0.96...1.04)
        let dt = 0.25
        let meters = speed * dt
        let next = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        apply(next, pairing: pairing, markRecent: false)
    }

    private func startResend(pairing: PairingStore) {
        guard resendTimer == nil else { return }
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                let result = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
                if case .failure(let error) = result {
                    let wasDropped = self.status.isDropped
                    self.status = .dropped(error.localizedDescription)
                    self.didRestorePersistedState = false
                    if !wasDropped {
                        self.postDropNotification("The connection changed. LocationSim Personal will keep trying to reconnect.")
                    }
                }
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.pendingLocationUpdate != nil {
                    self.retryPendingLocation(pairing: pairing)
                    return
                }
                guard let sim = self.simulated else { return }
                if self.routeNeedsResume {
                    self.restoreIfNeeded(pairing: pairing)
                    return
                }
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false, reportError: false)
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false, reportError: false)
                }
            }
        }
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    private func persistSavedTrips() {
        do {
            try SavedTripStore.save(savedTrips)
        } catch {
            lastError = "Could not save the trip library: \(error.localizedDescription)"
        }
    }

    private func persistTripFolders() {
        do {
            try TripFolderStore.save(tripFolders)
        } catch {
            lastError = "Could not save trip folders: \(error.localizedDescription)"
        }
    }

    private func distance(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    private func routeDistance(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + distance(from: pair.0, to: pair.1)
        }
    }

    private func remainingDistance(
        from current: CLLocationCoordinate2D,
        targetIndex: Int,
        coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard coordinates.indices.contains(targetIndex) else { return 0 }
        var result = distance(from: current, to: coordinates[targetIndex])
        if targetIndex + 1 < coordinates.count {
            result += routeDistance(Array(coordinates[targetIndex...]))
        }
        return result
    }

    private func cornerSpeedFactor(
        current: CLLocationCoordinate2D,
        targetIndex: Int,
        coordinates: [CLLocationCoordinate2D],
        speed: CLLocationSpeed,
        mode: TravelMode
    ) -> Double {
        guard targetIndex + 1 < coordinates.count else { return 1 }
        let target = coordinates[targetIndex]
        let distanceToCorner = distance(from: current, to: target)
        let brakingDistance = max(4, speed * (mode == .drive ? 2.2 : 1.3))
        guard distanceToCorner < brakingDistance else { return 1 }

        let incoming = bearing(from: current, to: target)
        let outgoing = bearing(from: target, to: coordinates[targetIndex + 1])
        var turn = abs(outgoing - incoming).truncatingRemainder(dividingBy: 360)
        if turn > 180 { turn = 360 - turn }
        let severity = min(1, turn / 120)
        let maximumReduction: Double
        switch mode {
        case .walk: maximumReduction = 0.08
        case .run: maximumReduction = 0.18
        case .cycle: maximumReduction = 0.42
        case .drive: maximumReduction = 0.66
        }
        let proximity = 1 - min(1, distanceToCorner / brakingDistance)
        return max(0.3, 1 - (maximumReduction * severity * proximity))
    }

    private func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return atan2(y, x) * 180 / .pi
    }

    private func variedCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        maximumMeters: Double
    ) -> CLLocationCoordinate2D {
        guard maximumMeters > 0 else { return coordinate }
        let radius = Double.random(in: 0...maximumMeters)
        let angle = Double.random(in: 0...(2 * .pi))
        return offset(
            coordinate: coordinate,
            eastMeters: cos(angle) * radius,
            northMeters: sin(angle) * radius
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "LocationSim Personal was interrupted"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * cos(coordinate.latitude * .pi / 180)) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }
}
