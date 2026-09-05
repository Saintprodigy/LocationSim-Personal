import CoreLocation
import Network
import SwiftUI

/// Explicit developer-launched, real-device regression test. Normal launches never run it.
/// Uses public Paris landmarks; never copies pairing credentials into its report.
struct NetworkSelfTestView: View {
    let label: String
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var message = "Preparing network test…"

    var body: some View {
        VStack(spacing: 18) {
            Text("Network Regression Test").font(.title2)
            Text(label).font(.headline)
            Text(message).multilineTextAlignment(.center)
            Text("Public test route. Simulation is stopped when the test finishes.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding().task { await run() }
    }

    @MainActor private func run() async {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeLabel = label.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let output = documents.appendingPathComponent("NetworkTest-\(safeLabel).json")
        let cachedRouteURL = documents.appendingPathComponent("NetworkTestRoute.json")
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "locationsim.test.path"))
        defer { monitor.cancel() }
        try? await Task.sleep(for: .seconds(1))
        var report: [String: Any] = [
            "label": label, "date": ISO8601DateFormatter().string(from: Date()),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "vpnInterfacePresent": LocalDevVPN.isConnected,
            "pairingFilePresent": pairing.hasPairingFile,
            "cachedPortPresent": RemotePairingDiscovery.hasOfflineReconnectPort,
            "pathSatisfied": monitor.currentPath.status == .satisfied,
            "pathUsesWiFi": monitor.currentPath.usesInterfaceType(.wifi),
            "pathUsesCellular": monitor.currentPath.usesInterfaceType(.cellular),
            "pathUsesOther": monitor.currentPath.usesInterfaceType(.other)
        ]
        func save() {
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output, options: .atomic)
            }
        }
        save()
        if label.contains("socket") {
            report["socketDiagnostics"] = await Task.detached { TunnelSocketDiagnostic.run() }.value
            report["endPathUsesWiFi"] = monitor.currentPath.usesInterfaceType(.wifi)
            report["endPathUsesCellular"] = monitor.currentPath.usesInterfaceType(.cellular)
            report["finished"] = true
            save()
            message = "Socket diagnostic finished. No location was changed."
            return
        }
        // Preserve the user's library before testing, without exporting the trust credential.
        let originalLibrary = LibraryBackup.make(
            trips: session.savedTrips, folders: session.tripFolders,
            favorites: session.favorites, recents: session.recents,
            speedPositions: Dictionary(uniqueKeysWithValues: TravelMode.allCases.map { ($0.rawValue, session.speedPosition(for: $0)) }),
            mapStyleIndex: session.mapStyleIndex
        )
        if let backup = try? LibraryBackup.write(originalLibrary) {
            let destination = documents.appendingPathComponent("NetworkTest-Library.locationsimbackup")
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: backup, to: destination)
            }
        }
        message = "Generating a new road route through Apple Maps…"
        var route: [CLLocationCoordinate2D] = []
        let started = Date()
        do {
            if label.contains("offline") {
                throw NSError(domain: "NetworkTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline playback test: using the saved route, not requesting new online directions."])
            }
            route = try await RouteBuilder.roadRoute(
                from: .init(latitude: 48.85837, longitude: 2.29448),
                to: .init(latitude: 48.85765, longitude: 2.29515), mode: .walk)
            report["newRoadRoute"] = "passed"
            report["routePoints"] = route.count
            try JSONEncoder().encode(route.map(PersistedCoordinate.init)).write(to: cachedRouteURL, options: .atomic)
        } catch {
            report["newRoadRoute"] = label.contains("offline") ? "not attempted: offline playback test" : "failed"
            report["routeError"] = error.localizedDescription
            if let data = try? Data(contentsOf: cachedRouteURL),
               let saved = try? JSONDecoder().decode([PersistedCoordinate].self, from: data) {
                route = saved.map(\.coordinate)
                report["usingCachedTestRoute"] = true
            }
        }
        report["routeGenerationSeconds"] = Date().timeIntervalSince(started)
        save()
        guard route.count >= 2 else { message = "Route generation failed. Report saved."; return }
        message = "Starting test route and measuring real engine updates…"
        let oldSpeed = session.speedPosition(for: .walk)
        let oldMode = session.travelMode
        session.selectTravelMode(.walk)
        session.setSpeedPosition(0.5, for: .walk)
        let repairCountBefore = session.automaticTunnelRecoveryCount
        let enablePulseCountBefore = session.automaticTunnelEnablePulseCount
        session.followRoute(route, pairing: pairing, options: RoutePlaybackOptions(name: "Network test", realism: .smooth))
        // An automatic LocalDevVPN restart intentionally switches apps twice.
        // Allow that real recovery path to finish before measuring movement.
        for _ in 0..<45 where session.simulated == nil || session.status != .active {
            try? await Task.sleep(for: .seconds(1))
        }
        let engineStarted = LocationEngine.isSessionActive && session.simulated != nil && session.status == .active
        if engineStarted {
            try? await Task.sleep(for: .seconds(6))
        }
        report["engineStarted"] = engineStarted
        report["automaticTunnelRecoveryCount"] = session.automaticTunnelRecoveryCount - repairCountBefore
        report["automaticTunnelEnablePulseCount"] = session.automaticTunnelEnablePulseCount - enablePulseCountBefore
        report["routeRunning"] = session.routeIsRunning
        report["engineSessionActive"] = LocationEngine.isSessionActive
        report["status"] = session.status.label
        report["error"] = session.lastError ?? ""
        report["nativeDiagnostic"] = LocationEngine.lastDiagnostic ?? ""
        if let actual = session.simulated {
            report["movementMeters"] = CLLocation(latitude: route[0].latitude, longitude: route[0].longitude)
                .distance(from: CLLocation(latitude: actual.latitude, longitude: actual.longitude))
        }
        save()
        #if DEBUG
        if LocationEngine.isSessionActive, let before = session.simulated {
            message = "Testing handoff notification and interrupted-route recovery…"
            session.networkPathDidChange(pairing: pairing)
            try? await Task.sleep(for: .seconds(3))
            if let after = session.simulated {
                report["syntheticHandoffMovementMeters"] = CLLocation(latitude: before.latitude, longitude: before.longitude)
                    .distance(from: CLLocation(latitude: after.latitude, longitude: after.longitude))
            }
            let interruptedAt = session.simulated
            session.interruptRouteWorkerForTest()
            session.restoreIfNeeded(pairing: pairing)
            try? await Task.sleep(for: .seconds(3))
            if let before = interruptedAt, let after = session.simulated {
                report["interruptedWorkerRecoveryMeters"] = CLLocation(latitude: before.latitude, longitude: before.longitude)
                    .distance(from: CLLocation(latitude: after.latitude, longitude: after.longitude))
            }
            report["recoveredRouteRunning"] = session.routeIsRunning && LocationEngine.isSessionActive
        }
        #endif
        message = "Stopping the test simulation…"
        if LocationEngine.isSessionActive { session.stop(pairing: pairing) }
        report["clearSucceeded"] = engineStarted && session.simulated == nil && session.status == .idle
        report["connectionRetainedAfterStop"] = LocationEngine.isSessionActive
        session.setSpeedPosition(oldSpeed, for: .walk)
        session.selectTravelMode(oldMode)
        do {
            let original = originalLibrary
            session.replaceLibrary(trips: original.trips, folders: original.folders,
                favorites: original.favorites, recents: original.recents,
                speedPositions: original.speedPositions, mapStyleIndex: original.mapStyleIndex)
        }
        report["endPathUsesWiFi"] = monitor.currentPath.usesInterfaceType(.wifi)
        report["endPathUsesCellular"] = monitor.currentPath.usesInterfaceType(.cellular)
        report["endPathSatisfied"] = monitor.currentPath.status == .satisfied
        report["finished"] = true
        save()
        message = "Finished. Results saved on this phone for the Mac to read."
    }
}
