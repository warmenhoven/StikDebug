//
//  MapSelectionView.swift
//  StikJIT
//
//  Created by Stephen on 11/3/25.
//

import SwiftUI
import MapKit
import UIKit

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct LocationSimulationView: View {
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var resendTimer: Timer?

    private var isAppStoreBuild: Bool {
        #if APPSTORE
        return true
        #else
        return false
        #endif
    }

    private var pairingFilePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let uuid = UserDefaults.standard.string(forKey: "DeviceLibraryActiveDeviceID") ?? ""
        let name = (uuid != "00000000-0000-0000-0000-000000000001" && !uuid.isEmpty)
            ? "DeviceLibrary/Pairings/\(uuid).mobiledevicepairing"
            : "pairingFile.plist"
        return docs.appendingPathComponent(name).path()
    }

    private var pairingExists: Bool {
        FileManager.default.fileExists(atPath: pairingFilePath)
    }

    private var deviceIP: String {
        UserDefaults.standard.string(forKey: "TunnelDeviceIP") ?? "10.7.0.1"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $position) {
                    if let coordinate {
                        Marker("Pin", coordinate: coordinate)
                            .tint(.red)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onTapGesture { point in
                    if let loc = proxy.convert(point, from: .local) {
                        coordinate = loc
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
            }
            .ignoresSafeArea()
            .onChange(of: coordinate) { _, new in
                if let new {
                    position = .region(MKCoordinateRegion(center: new, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
            }

            VStack(spacing: 12) {
                if let coord = coordinate {
                    Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Stop", action: clear)
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(!pairingExists)

                        Button("Simulate Location", action: simulate)
                            .buttonStyle(.borderedProminent)
                            .disabled(isAppStoreBuild || !pairingExists)
                    }
                } else {
                    Text("Tap map to drop pin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
        }
        .navigationBarHidden(true)
        .onDisappear {
            stopResendLoop()
            endBackgroundTask()
        }
    }

    private func simulate() {
        guard pairingExists, let coord = coordinate else { return }
        let code = simulate_location(deviceIP, coord.latitude, coord.longitude, pairingFilePath)
        if code == 0 {
            beginBackgroundTask()
            startResendLoop()
        }
    }

    private func clear() {
        guard pairingExists else { return }
        let code = clear_simulated_location()
        if code == 0 {
            coordinate = nil
            stopResendLoop()
            endBackgroundTask()
        }
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { endBackgroundTask() }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func startResendLoop() {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            guard pairingExists, let coord = coordinate else { return }
            _ = simulate_location(deviceIP, coord.latitude, coord.longitude, pairingFilePath)
        }
    }

    private func stopResendLoop() {
        resendTimer?.invalidate()
        resendTimer = nil
    }
}
