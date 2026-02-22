//  SettingsView.swift
//  StikJIT
//
//  Created by Stephen on 3/27/25.

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @AppStorage("username") private var username = "User"
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "AppIcon"
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("enableAdvancedBetaOptions") private var enableAdvancedBetaOptions = false
    @AppStorage("enableTesting") private var enableTesting = false
    @AppStorage("enablePiP") private var enablePiP = false
    @AppStorage(UserDefaults.Keys.txmOverride) private var overrideTXMDetection = false
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage(TabConfiguration.storageKey) private var enabledTabIdentifiers = TabConfiguration.defaultRawValue
    @AppStorage("primaryTabSelection") private var tabSelection = TabConfiguration.defaultIDs.first ?? "home"
    @Environment(\.themeExpansionManager) private var themeExpansion
    private var backgroundStyle: BackgroundStyle { themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle }
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }
    private var isAppStoreBuild: Bool {
        #if APPSTORE
        return true
        #else
        return false
        #endif
    }
    
    @State private var isShowingPairingFilePicker = false
    @State private var showPairingFileMessage = false
    @State private var isImportingFile = false
    @State private var importProgress: Float = 0.0
    @State private var pairingStatusMessage: String? = nil
    @State private var showDDIConfirmation = false
    @State private var isRedownloadingDDI = false
    @State private var ddiDownloadProgress: Double = 0.0
    @State private var ddiStatusMessage: String = ""
    @State private var ddiResultMessage: (text: String, isError: Bool)?

    @State private var showingDisplayView = false

    private var appVersion: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }
    
    private var accentColor: Color {
        themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue
    }

    private var currentThemeName: String {
        AppTheme(rawValue: appThemeRaw)?.displayName ?? "Default"
    }

    private var accentColorDescription: String {
        customAccentColorHex.isEmpty ? "System Blue" : customAccentColorHex.uppercased()
    }
    struct TabOption: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let isBeta: Bool
    }
    
    private var tabOptions: [TabOption] {
        var options: [TabOption] = [
            TabOption(id: "home", title: "Home", detail: "Dashboard overview", icon: "house", isBeta: false),
            TabOption(id: "console", title: "Console", detail: "Live device logs", icon: "terminal", isBeta: false),
            TabOption(id: "scripts", title: "Scripts", detail: "Manage automation scripts", icon: "scroll", isBeta: false)
        ]
        options.append(TabOption(id: "deviceinfo", title: "Device Info", detail: "View detailed device metadata", icon: "iphone.and.arrow.forward", isBeta: false))
        options.append(TabOption(id: "profiles", title: "App Expiry", detail: "Check app expiration date, install/remove profiles", icon: "calendar.badge.clock", isBeta: false))
        
        if FeatureFlags.showBetaTabs {
            options.append(TabOption(id: "processes", title: "Processes", detail: "Inspect running apps", icon: "rectangle.stack.person.crop", isBeta: true))
            options.append(TabOption(id: "devicelibrary", title: "Devices", detail: "Manage external devices", icon: "list.bullet.rectangle", isBeta: true))
            if FeatureFlags.isLocationSpoofingEnabled && !isAppStoreBuild {
                options.append(TabOption(id: "location", title: "Location Sim", detail: "Sideload only", icon: "location", isBeta: true))
            }
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                // 1) App Header
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image("StikDebug")
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("StikDebug").font(.title2.weight(.semibold))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }

                // 2) Appearance
                Section("Appearance") {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 8).fill(accentColor).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentThemeName).font(.subheadline.weight(.semibold))
                            Text("Accent · \(accentColorDescription)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button { showingDisplayView = true } label: {
                        Label("Customize Display", systemImage: "paintbrush")
                    }
                    .foregroundStyle(.primary)
                }

                // 3) Navigation
                Section("Navigation") {
                    NavigationLink {
                        TabCustomizationView(
                            tabOptions: tabOptions,
                            enabledTabIdentifiers: $enabledTabIdentifiers,
                            tabSelection: $tabSelection
                        )
                    } label: {
                        Label("Tab Bar", systemImage: "list.bullet")
                    }
                }

                // 4) Pairing File
                Section("Pairing File") {
                    Button { isShowingPairingFilePicker = true } label: {
                        Label("Import Pairing File", systemImage: "doc.badge.plus")
                    }
                    if showPairingFileMessage && !isImportingFile {
                        Label("Imported successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                // 5) Behavior
                Section("Behavior") {
                    Toggle("Picture in Picture", isOn: $enablePiP)
                    Toggle(isOn: $overrideTXMDetection) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Always Run Scripts")
                            Text("Treats device as TXM-capable to bypass hardware checks.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // 6) Advanced
                Section("Advanced") {
                    Button { openAppFolder() } label: {
                        Label("App Folder", systemImage: "folder")
                    }.foregroundStyle(.primary)
                    Button { showDDIConfirmation = true } label: {
                        Label("Redownload DDI", systemImage: "arrow.down.circle")
                    }.foregroundStyle(.primary).disabled(isRedownloadingDDI)
                    if isRedownloadingDDI {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: ddiDownloadProgress, total: 1.0).tint(accentColor)
                            Text(ddiStatusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let result = ddiResultMessage {
                        Text(result.text).font(.caption).foregroundStyle(result.isError ? .red : .green)
                    }
                }

                // 7) Help
                Section("Help") {
                    Link(destination: URL(string: "https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md")!) {
                        Label("Pairing File Guide", systemImage: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!) {
                        Label("Download LocalDevVPN", systemImage: "arrow.down.circle")
                    }
                    Link(destination: URL(string: "https://discord.gg/qahjXNTDwS")!) {
                        Label("Discord Support", systemImage: "bubble.left.and.bubble.right")
                    }
                }

                // 8) Version footer
                Section {
                    Text(versionFooter)
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
        }
        .tint(accentColor)
        .preferredColorScheme(preferredScheme)
        .sheet(isPresented: $showingDisplayView) {
            if let manager = themeExpansion {
                DisplayView().themeExpansionManager(manager)
            } else {
                DisplayView()
            }
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                let fileManager = FileManager.default
                let accessing = url.startAccessingSecurityScopedResource()

                if fileManager.fileExists(atPath: url.path) {
                    do {
                        if fileManager.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path) {
                            try fileManager.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                        }

                        try fileManager.copyItem(at: url, to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                        DispatchQueue.main.async {
                            isImportingFile = true
                            importProgress = 0.0
                            pairingStatusMessage = nil
                            showPairingFileMessage = false
                        }

                        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                            DispatchQueue.main.async {
                                if importProgress < 1.0 {
                                    importProgress += 0.05
                                } else {
                                    timer.invalidate()
                                    isImportingFile = false
                                }
                            }
                        }

                        RunLoop.current.add(progressTimer, forMode: .common)
                        DispatchQueue.main.async {
                            startHeartbeatInBackground()
                        }

                    } catch { }
                }

                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            case .failure:
                break
            }
        }
        .confirmationDialog("Redownload DDI Files?", isPresented: $showDDIConfirmation, titleVisibility: .visible) {
            Button("Redownload", role: .destructive) {
                redownloadDDIPressed()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Existing DDI files will be removed before downloading fresh copies.")
        }
        .overlay { if isImportingFile { importBusyOverlay } }
    }

    @ViewBuilder
    private var importBusyOverlay: some View {
        Color.black.opacity(0.35).ignoresSafeArea()
        VStack(spacing: 12) {
            ProgressView("Processing pairing file…")
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green)
                            .frame(width: geometry.size.width * CGFloat(importProgress), height: 8)
                            .animation(.linear(duration: 0.3), value: importProgress)
                    }
                }
                .frame(height: 8)
                Text("\(Int(importProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    private var versionFooter: String {
        let processInfo = ProcessInfo.processInfo
        let txmLabel: String
        if processInfo.isTXMOverridden {
            txmLabel = "TXM (Override)"
        } else {
            txmLabel = processInfo.hasTXM ? "TXM" : "Non TXM"
        }
        return "Version \(appVersion) • iOS \(UIDevice.current.systemVersion) • \(txmLabel)"
    }
    
    // MARK: - Business Logic

    private func openAppFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let path = documentsURL.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        if let url = URL(string: path) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func redownloadDDIPressed() {
        guard !isRedownloadingDDI else { return }
        Task {
            await MainActor.run {
                isRedownloadingDDI = true
                ddiDownloadProgress = 0
                ddiStatusMessage = "Preparing download…"
                ddiResultMessage = nil
            }
            do {
                try await redownloadDDI { progress, status in
                    Task { @MainActor in
                        self.ddiDownloadProgress = progress
                        self.ddiStatusMessage = status
                    }
                }
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("DDI files refreshed successfully.", false)
                }
            } catch {
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("Failed to redownload DDI files: \(error.localizedDescription)", true)
                }
            }
        }
        scheduleDDIStatusDismiss()
    }
    
    private func scheduleDDIStatusDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isRedownloadingDDI {
                    ddiResultMessage = nil
                }
            }
        }
    }
}

// MARK: - Tab Customization

struct TabCustomizationView: View {
    let tabOptions: [SettingsView.TabOption]
    @Binding var enabledTabIdentifiers: String
    @Binding var tabSelection: String

    private var selectedIDs: [String] {
        TabConfiguration.sanitize(raw: enabledTabIdentifiers)
    }

    private var pinnedOptions: [SettingsView.TabOption] {
        selectedIDs.compactMap { id in tabOptions.first(where: { $0.id == id }) }
    }

    private var availableOptions: [SettingsView.TabOption] {
        tabOptions.filter { !selectedIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                ForEach(pinnedOptions) { option in
                    HStack {
                        Label(option.title, systemImage: option.icon)
                        if option.isBeta {
                            Spacer()
                            Text("BETA")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .foregroundStyle(.orange)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                    }
                }
                .onMove { indices, newOffset in
                    var ids = selectedIDs
                    ids.move(fromOffsets: indices, toOffset: newOffset)
                    enabledTabIdentifiers = TabConfiguration.serialize(ids)
                }
                .onDelete { indexSet in
                    var ids = selectedIDs
                    ids.remove(atOffsets: indexSet)
                    if ids.isEmpty { ids = TabConfiguration.defaultIDs }
                    enabledTabIdentifiers = TabConfiguration.serialize(ids)
                }
            } header: {
                Text("Pinned")
            } footer: {
                Text("Settings is always the last tab.")
            }

            if !availableOptions.isEmpty {
                Section("Available") {
                    ForEach(availableOptions) { option in
                        Button {
                            var ids = selectedIDs
                            guard ids.count < TabConfiguration.maxSelectableTabs else { return }
                            ids.append(option.id)
                            enabledTabIdentifiers = TabConfiguration.serialize(ids)
                        } label: {
                            HStack {
                                Label(option.title, systemImage: option.icon)
                                if option.isBeta {
                                    Spacer()
                                    Text("BETA")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(.orange)
                                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle("Tab Bar")
        .toolbar {
            EditButton()
        }
    }
}

struct ConsoleLogsView_Preview: PreviewProvider {
    static var previews: some View {
        ConsoleLogsView()
            .themeExpansionManager(ThemeExpansionManager(previewUnlocked: true))
    }
}
