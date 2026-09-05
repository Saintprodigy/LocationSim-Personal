import CoreLocation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var showBackupImporter = false
    @State private var pendingBackup: LocationSimBackup?
    @State private var showRestoreConfirmation = false
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "RPPairing file installed" : "No pairing file")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("Pair on this iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("Import RPPairing file…") { showImporter = true }
                    Button("Paste RPPairing from clipboard") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("Remove pairing file", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("Developer pairing")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "On iOS 27, Pair on this iPhone works without a computer. Confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On iOS 18–26, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing)."
                         : "Import the one-time RPPairing file created by idevice_pair (not a SideStore lockdown .mobiledevicepairing). It stays protected on this iPhone and is excluded from backups.")
                }

                Section {
                    LabeledContent("Device endpoint") {
                        Text(TunnelConfig.targetIP)
                            .font(.body.monospaced())
                    }
                    LabeledContent("Status") {
                        Text(LocalDevVPN.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    LabeledContent("Previous tunnel handshake") {
                        Text(RemotePairingDiscovery.hasOfflineReconnectPort ? "Saved" : "Not yet verified")
                            .foregroundStyle(RemotePairingDiscovery.hasOfflineReconnectPort ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("Location playback uses the local developer tunnel, not the Internet. New road routes and address searches need working Wi‑Fi or cellular Internet; saved and drawn routes do not. A saved handshake is history, not proof of current connectivity. After a restart or failed local connection, reconnect LocalDevVPN and retry; iOS may require a Wi‑Fi start.")
                }

                Section("Backup & migration") {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export Complete Library", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showBackupImporter = true
                    } label: {
                        Label("Restore Library Backup", systemImage: "square.and.arrow.down")
                    }
                    Text("Includes trips, folders, saved locations, recents, map style, and every movement-speed setting. The device pairing credential is intentionally excluded and should be recreated for a new phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Compatibility") {
                    NavigationLink {
                        CompatibilityView()
                    } label: {
                        Label("System & Future iOS Check", systemImage: "checkmark.shield.fill")
                    }
                }

                Section("Privacy") {
                    Text("Fully on-device. Saved locations, saved trips, recents and active-trip progress stay locally on this iPhone. The pairing credential is excluded from backups. No analytics and nothing uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Trip continuity") {
                    Text("With LocalDevVPN connected, a teleport or route continues when the screen is locked or this app is in the background. If iOS terminates the app, the phone restarts, or you force-quit it, reopen LocationSim Personal to restore the last saved point and resume an unfinished route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Engine", value: "idevice DVT location simulation")
                    Text("LocationSim Personal is based on the MIT-licensed Locus project. Location injection uses the MIT-licensed idevice FFI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus, n. — a place. From the Latin for where you are.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section("Connect on mobile data") {
                    Text("Outside with no Wi-Fi, try this:")
                    Text("1. Keep mobile data on, open LocalDevVPN, and connect it.")
                    Text("2. Open LocationSim and choose your destination. For a new route or address search, do this while data is on.")
                    Text("3. If the tunnel error appears, briefly turn mobile data off—leave LocalDevVPN connected.")
                    Text("4. Return to LocationSim and retry the teleport or saved trip.")
                    Text("5. Once it successfully starts, turn mobile data back on.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [UTType(filenameExtension: "locationsimbackup") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                do {
                    pendingBackup = try LibraryBackup.read(url)
                    showRestoreConfirmation = true
                } catch {
                    session.lastError = "Could not read this backup: \(error.localizedDescription)"
                }
            }
            .alert("Replace Current Library?", isPresented: $showRestoreConfirmation) {
                Button("Cancel", role: .cancel) { pendingBackup = nil }
                Button("Restore", role: .destructive) {
                    restorePendingBackup()
                }
            } message: {
                Text("This replaces the current trips, folders, saved locations, recents, and speed settings with the selected backup.")
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }

    private func exportBackup() {
        let speeds = Dictionary(uniqueKeysWithValues: TravelMode.allCases.map {
            ($0.rawValue, session.speedPosition(for: $0))
        })
        let backup = LibraryBackup.make(
            trips: session.savedTrips,
            folders: session.tripFolders,
            favorites: session.favorites,
            recents: session.recents,
            speedPositions: speeds,
            mapStyleIndex: session.mapStyleIndex
        )
        do {
            share(items: [try LibraryBackup.write(backup)])
        } catch {
            session.lastError = "Could not create the backup: \(error.localizedDescription)"
        }
    }

    private func restorePendingBackup() {
        guard let backup = pendingBackup else { return }
        session.replaceLibrary(
            trips: backup.trips,
            folders: backup.folders,
            favorites: backup.favorites,
            recents: backup.recents,
            speedPositions: backup.speedPositions,
            mapStyleIndex: backup.mapStyleIndex
        )
        pendingBackup = nil
    }

    private func share(items: [Any]) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(controller, animated: true)
        }
    }
}

private struct CompatibilityView: View {
    @EnvironmentObject private var pairing: PairingStore

    private var checks: [CompatibilityCheck] {
        CompatibilityReport.checks(pairing: pairing)
    }

    var body: some View {
        List {
            ForEach(checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: check.level))
                        .foregroundStyle(color(for: check.level))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.title).font(.headline)
                        Text(check.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }

            Section {
                ShareLink(item: CompatibilityReport.text(pairing: pairing)) {
                    Label("Share Diagnostic Summary", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("The compatibility check is local and does not upload device or pairing information.")
            }
        }
        .navigationTitle("Compatibility")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func icon(for level: CompatibilityLevel) -> String {
        switch level {
        case .good: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .information: return "info.circle.fill"
        }
    }

    private func color(for level: CompatibilityLevel) -> Color {
        switch level {
        case .good: return LocusTheme.statusGood
        case .attention: return LocusTheme.statusWarn
        case .information: return LocusTheme.accent
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var showSavePrompt = false
    @State private var promptText = ""
    @State private var coordinateToSave: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        beginSavingCurrentLocation()
                    } label: {
                        Label("Save current pin or location", systemImage: "mappin.and.ellipse")
                    }
                    .disabled(currentCoordinate == nil)

                    if let coordinate = currentCoordinate {
                        Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Drop a pin on the map first.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Quick save")
                } footer: {
                    Text("Saved locations and trips work without an internet connection.")
                }

                Section("Library") {
                    NavigationLink {
                        SavedLocationsFolderView { place in
                            session.teleport(to: place.coordinate, pairing: pairing)
                            dismiss()
                        }
                    } label: {
                        LibraryFolderRow(
                            title: "Saved Locations",
                            subtitle: "Pins and places ready to teleport",
                            count: session.favorites.count,
                            icon: "folder.fill",
                            color: .blue
                        )
                    }

                    NavigationLink {
                        SavedTripsFolderView { trip in
                            session.startSavedTrip(trip, pairing: pairing)
                            dismiss()
                        }
                    } label: {
                        LibraryFolderRow(
                            title: "Saved Trips",
                            subtitle: "Routes with mode and speed saved",
                            count: session.savedTrips.count,
                            icon: "folder.fill.badge.gearshape",
                            color: LocusTheme.accent
                        )
                    }

                    NavigationLink {
                        RecentLocationsFolderView { place in
                            session.teleport(to: place.coordinate, pairing: pairing)
                            dismiss()
                        }
                    } label: {
                        LibraryFolderRow(
                            title: "Recent Locations",
                            subtitle: "Your latest teleports",
                            count: session.recents.count,
                            icon: "clock.fill",
                            color: .indigo
                        )
                    }
                }
            }
            .navigationTitle("Saved Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Location", isPresented: $showSavePrompt) {
                TextField("Name", text: $promptText)
                Button("Cancel", role: .cancel) {
                    coordinateToSave = nil
                }
                Button("Save") {
                    finishSavingLocation()
                }
            } message: {
                Text("Choose a name you’ll recognize later.")
            }
        }
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }

    private func beginSavingCurrentLocation() {
        guard let coordinate = currentCoordinate else { return }
        coordinateToSave = coordinate
        promptText = session.suggestedFavoriteName(for: coordinate)
        showSavePrompt = true
    }

    private func finishSavingLocation() {
        if let coordinate = coordinateToSave {
            session.addFavorite(name: promptText, coordinate: coordinate)
        }
        coordinateToSave = nil
    }
}

private struct LibraryFolderRow: View {
    let title: String
    let subtitle: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.16))
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

private struct SavedLocationsFolderView: View {
    @EnvironmentObject private var session: SpoofSession
    let onSelect: (SavedPlace) -> Void

    @State private var query = ""
    @State private var renamePlace: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        List {
            if filteredPlaces.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Saved Locations" : "No Matches",
                    systemImage: "mappin.slash",
                    description: Text(query.isEmpty ? "Save a pin from the library or star a place on the map." : "Try another name or coordinate.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(filteredPlaces) { place in
                PlaceLibraryButton(place: place, action: { onSelect(place) })
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            session.removeFavorite(place)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        Button {
                            renameText = place.name
                            renamePlace = place
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
            }
        }
        .navigationTitle("Saved Locations")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search saved locations")
        .alert("Rename Location", isPresented: Binding(
            get: { renamePlace != nil },
            set: { if !$0 { renamePlace = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamePlace = nil }
            Button("Save") {
                if let place = renamePlace {
                    session.renameFavorite(place, to: renameText)
                }
                renamePlace = nil
            }
        }
    }

    private var filteredPlaces: [SavedPlace] {
        filterPlaces(session.favorites, query: query)
    }
}

private struct SavedTripsFolderView: View {
    @EnvironmentObject private var session: SpoofSession
    let onSelect: (SavedTrip) -> Void

    @State private var query = ""
    @State private var editingTrip: SavedTrip?
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            if !query.isEmpty {
                tripSection(filteredTrips, title: "Search Results")
            } else {
                Section("Folders") {
                    if session.tripFolders.isEmpty {
                        Text("Create folders for work, school, travel, or anything else.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.tripFolders) { folder in
                        NavigationLink {
                            TripCollectionView(folder: folder, onSelect: onSelect)
                        } label: {
                            LibraryFolderRow(
                                title: folder.name,
                                subtitle: "Saved route collection",
                                count: session.savedTrips.filter { $0.folderID == folder.id }.count,
                                icon: "folder.fill",
                                color: LocusTheme.accent
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                session.removeTripFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }

                tripSection(session.savedTrips, title: "All Trips")
            }

            if filteredTrips.isEmpty && session.tripFolders.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Saved Trips" : "No Matches",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text(query.isEmpty ? "Build, draw, or import a route, then save it from Routes." : "Try another trip name or travel mode.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Saved Trips")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search saved trips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .alert("New Trip Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { session.createTripFolder(name: newFolderName) }
        } message: {
            Text("Trips can be moved into this folder from Edit Trip.")
        }
        .sheet(item: $editingTrip) { trip in
            TripEditorView(trip: trip)
                .environmentObject(session)
        }
    }

    private var filteredTrips: [SavedTrip] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return session.savedTrips }
        return session.savedTrips.filter { trip in
            trip.name.localizedCaseInsensitiveContains(needle)
                || trip.mode.title.localizedCaseInsensitiveContains(needle)
                || trip.tags.contains { $0.localizedCaseInsensitiveContains(needle) }
                || session.tripFolders.first(where: { $0.id == trip.folderID })?
                    .name.localizedCaseInsensitiveContains(needle) == true
        }
    }

    @ViewBuilder
    private func tripSection(_ trips: [SavedTrip], title: String) -> some View {
        Section(title) {
            ForEach(trips) { trip in
                tripButton(trip)
            }
            .onMove { offsets, destination in
                guard title == "All Trips" else { return }
                session.moveTrip(fromOffsets: offsets, toOffset: destination)
            }
        }
    }

    private func tripButton(_ trip: SavedTrip) -> some View {
        Button { onSelect(trip) } label: {
            TripLibraryRow(trip: trip)
        }
        .contextMenu {
            Button { editingTrip = trip } label: { Label("Edit Trip", systemImage: "slider.horizontal.3") }
            Button { session.duplicateTrip(trip) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { session.reverseTrip(trip) } label: { Label("Reverse Route", systemImage: "arrow.left.arrow.right") }
            Button(role: .destructive) { session.removeTrip(trip) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { session.removeTrip(trip) } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            Button { editingTrip = trip } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .tint(.gray)
        }
    }
}

private struct TripCollectionView: View {
    @EnvironmentObject private var session: SpoofSession
    let folder: TripFolder
    let onSelect: (SavedTrip) -> Void

    @State private var query = ""
    @State private var editingTrip: SavedTrip?
    @State private var showRename = false
    @State private var folderName = ""

    private var trips: [SavedTrip] {
        let scoped = session.savedTrips.filter { $0.folderID == folder.id }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return scoped }
        return scoped.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    var body: some View {
        List {
            if trips.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Folder Is Empty" : "No Matches",
                    systemImage: "folder",
                    description: Text(query.isEmpty ? "Edit a trip and move it into this folder." : "Try another trip name or tag.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(trips) { trip in
                Button { onSelect(trip) } label: { TripLibraryRow(trip: trip) }
                    .contextMenu {
                        Button { editingTrip = trip } label: { Label("Edit Trip", systemImage: "slider.horizontal.3") }
                        Button { session.duplicateTrip(trip) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button { session.reverseTrip(trip) } label: { Label("Reverse Route", systemImage: "arrow.left.arrow.right") }
                        Button(role: .destructive) { session.removeTrip(trip) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { session.removeTrip(trip) } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        Button { editingTrip = trip } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                        .tint(.gray)
                    }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this folder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    folderName = folder.name
                    showRename = true
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }
            }
        }
        .alert("Rename Folder", isPresented: $showRename) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { session.renameTripFolder(folder, to: folderName) }
        }
        .sheet(item: $editingTrip) { trip in
            TripEditorView(trip: trip).environmentObject(session)
        }
    }
}

private struct TripLibraryRow: View {
    @EnvironmentObject private var session: SpoofSession
    let trip: SavedTrip

    var body: some View {
        HStack(spacing: 12) {
            RouteThumbnail(coordinates: trip.coordinates)
                .frame(width: 64, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: trip.mode.icon)
                        .foregroundStyle(LocusTheme.accent)
                    Text(trip.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if trip.loopEnabled {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(LocusTheme.accentSecondary)
                    }
                }
                Text(tripDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !trip.tags.isEmpty {
                    Text(trip.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(LocusTheme.accent)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var tripDetail: String {
        let kilometers = trip.distanceMeters / 1_000
        let speed = session.speedDescription(for: trip.mode, position: trip.speedPosition)
        return "\(trip.mode.title) · \(speed) · \(String(format: "%.1f", kilometers)) km · \(trip.realism.title)"
    }
}

private struct RouteThumbnail: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        Canvas { context, size in
            guard coordinates.count > 1 else { return }
            let latitudes = coordinates.map(\.latitude)
            let longitudes = coordinates.map(\.longitude)
            guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
                  let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
            let latSpan = max(0.000001, maxLat - minLat)
            let lonSpan = max(0.000001, maxLon - minLon)
            var path = Path()
            for (index, coordinate) in coordinates.enumerated() {
                let point = CGPoint(
                    x: 6 + ((coordinate.longitude - minLon) / lonSpan) * max(1, size.width - 12),
                    y: 6 + ((maxLat - coordinate.latitude) / latSpan) * max(1, size.height - 12)
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(LocusTheme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }
}

private struct TripEditorView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SavedTrip
    @State private var tagText: String

    init(trip: SavedTrip) {
        _draft = State(initialValue: trip)
        _tagText = State(initialValue: trip.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name", text: $draft.name)
                    Picker("Folder", selection: $draft.folderID) {
                        Text("No Folder").tag(UUID?.none)
                        ForEach(session.tripFolders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                    TextField("Tags separated by commas", text: $tagText)
                        .textInputAutocapitalization(.never)
                }

                Section("Movement") {
                    Picker("Default method", selection: Binding(
                        get: { draft.mode },
                        set: { draft.travelMode = $0.rawValue }
                    )) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                    Picker("Realism", selection: $draft.realism) {
                        ForEach(RouteRealism.allCases) { realism in
                            Text(realism.title).tag(realism)
                        }
                    }
                    Toggle("Repeat route", isOn: $draft.loopEnabled)
                    Stepper(value: $draft.arrivalPauseSeconds, in: 0...600, step: 5) {
                        LabeledContent("Pause at each end", value: pauseLabel)
                    }
                }

                Section("Route") {
                    LabeledContent("Distance", value: String(format: "%.1f km", draft.distanceMeters / 1_000))
                    LabeledContent("Stops", value: "\(max(2, draft.stops.count))")
                    Button("Reverse Route") {
                        draft.route.reverse()
                        draft.stops.reverse()
                    }
                }
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.tags = tagText.split(separator: ",").map(String.init)
                        session.updateTrip(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var pauseLabel: String {
        draft.arrivalPauseSeconds == 0 ? "None" : "\(Int(draft.arrivalPauseSeconds)) sec"
    }
}

private struct RecentLocationsFolderView: View {
    @EnvironmentObject private var session: SpoofSession
    let onSelect: (SavedPlace) -> Void

    @State private var query = ""

    var body: some View {
        List {
            if filteredPlaces.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Recent Locations" : "No Matches",
                    systemImage: "clock",
                    description: Text(query.isEmpty ? "Locations you teleport to will appear here." : "Try another name or coordinate.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(filteredPlaces) { place in
                PlaceLibraryButton(place: place, action: { onSelect(place) })
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            session.removeRecent(place)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
            }
        }
        .navigationTitle("Recent Locations")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search recent locations")
    }

    private var filteredPlaces: [SavedPlace] {
        filterPlaces(session.recents, query: query)
    }
}

private struct PlaceLibraryButton: View {
    let place: SavedPlace
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func filterPlaces(_ places: [SavedPlace], query: String) -> [SavedPlace] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return places }
    return places.filter {
        $0.name.localizedCaseInsensitiveContains(needle)
            || String(format: "%.5f, %.5f", $0.latitude, $0.longitude).contains(needle)
    }
}
