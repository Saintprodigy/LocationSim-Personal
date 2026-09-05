import SwiftUI

@main
struct LocusApp: App {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false

    /// Map when setup finished, or when already paired outside this walkthrough.
    private var showMap: Bool {
        setupComplete || (pairing.hasPairingFile && !SetupGate.isInProgress)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let testLabel = ProcessInfo.processInfo.environment["LOCATIONSIM_NETWORK_TEST"] {
                    NetworkSelfTestView(label: testLabel)
                } else if showMap {
                    RootView()
                } else {
                    SetupFlowView(initialStep: SetupGate.initialStep(hasPairingFile: pairing.hasPairingFile)) {
                        SetupGate.markComplete()
                        setupComplete = true
                    }
                }
            }
            .environmentObject(session)
            .environmentObject(pairing)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleIncoming(url)
            }
            .onAppear {
                NetworkPathObserver.shared.start()
                if !setupComplete, pairing.hasPairingFile, !SetupGate.isInProgress {
                    SetupGate.markComplete()
                    setupComplete = true
                }
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        if url.scheme?.lowercased() == "locationsim" {
            if url.host == nil, session.handleTunnelRecoveryCallback(pairing: pairing) {
                return
            }
            handleCommand(url)
            return
        }
        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            try? pairing.importPairing(from: url)
        } else if ext == "gpx" {
            NotificationCenter.default.post(name: .locusImportGPX, object: url)
        }
    }

    private func handleCommand(_ url: URL) {
        switch url.host?.lowercased() {
        case "start":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let value = components?.queryItems?.first(where: { $0.name == "trip" })?.value,
                  let id = UUID(uuidString: value),
                  let trip = session.savedTrips.first(where: { $0.id == id }) else {
                session.lastError = "That saved trip is no longer available."
                return
            }
            session.startSavedTrip(trip, pairing: pairing)
        case "pause":
            session.setRoutePaused(true)
        case "resume":
            session.setRoutePaused(false)
        case "stop":
            session.stop(pairing: pairing)
        case "library":
            NotificationCenter.default.post(name: .locusOpenLibrary, object: nil)
        case "vpn":
            LocalDevVPN.openOrInstall()
        default:
            break
        }
    }
}

extension Notification.Name {
    static let locusImportGPX = Notification.Name("locusImportGPX")
    static let locusOpenLibrary = Notification.Name("locusOpenLibrary")
}
