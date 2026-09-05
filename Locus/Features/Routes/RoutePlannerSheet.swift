import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var stops: [TripStop]
    @Binding var isRouting: Bool
    var canSave: Bool
    var suggestedTripName: String
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onSave: (String) -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveTrip = false
    @State private var saveTripName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Road route") {
                    Button("Use current location / spoof as start") {
                        start = session.simulated ?? session.realCoordinate ?? session.pin
                    }
                    Button("Use current pin as end") {
                        end = session.pin
                    }
                    Button {
                        guard let end else { return }
                        stops.append(TripStop(name: "Stop \(stops.count + 1)", coordinate: end))
                        self.end = nil
                    } label: {
                        Label("Add current end as another stop", systemImage: "plus.circle")
                    }
                    .disabled(end == nil)
                    LabeledContent("Start") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    if !stops.isEmpty {
                        ForEach(stops) { stop in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                    Text(coordText(stop.coordinate.coordinate))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    stops.removeAll { $0.id == stop.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    LabeledContent("End") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("Build multi-stop route on roads", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section("Play / draw / GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("Use drawn path from map", systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label("Follow route", systemImage: "play.fill")
                    }
                    Button {
                        saveTripName = suggestedTripName
                        showSaveTrip = true
                    } label: {
                        Label("Save route to library", systemImage: "tray.and.arrow.down.fill")
                    }
                    .disabled(!canSave)
                    Button(action: onImportGPX) {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("Routes follow Apple Maps roads/footpaths for the selected travel mode. Speed gets light random variation so motion looks less robotic.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Trip", isPresented: $showSaveTrip) {
                TextField("Trip name", text: $saveTripName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    onSave(saveTripName)
                }
            } message: {
                Text("This route and its movement style will be available from your saved library.")
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
