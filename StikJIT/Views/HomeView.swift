//
//  ContentView.swift
//  StikJIT
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Pipify
import UIKit
import WidgetKit
import Combine
import Network
import SafariServices

struct JITEnableConfiguration {
    var bundleID: String? = nil
    var pid : Int? = nil
    var scriptData: Data? = nil
    var scriptName : String? = nil
}

struct HomeView: View {
    
    @AppStorage("username") private var username = "User"
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @Environment(\.colorScheme) private var colorScheme
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage("bundleID") private var bundleID: String = ""
    @AppStorage("recentApps") private var recentApps: [String] = []
    @AppStorage("favoriteApps") private var favoriteApps: [String] = []
    @State private var isProcessing = false
    @State private var isShowingInstalledApps = false
    @State private var isShowingPairingFilePicker = false
    @State private var pairingFileExists: Bool = true
    @State private var pairingFilePresentOnDisk: Bool = true
    @State private var isValidatingPairingFile = false
    @State private var lastValidatedPairingSignature: PairingFileSignature? = nil
    @State private var showPairingFileMessage = false
    @State private var pairingFileIsValid = false
    @State private var isImportingFile = false
    @State private var importProgress: Float = 0.0
    
    @State private var showPIDSheet = false
    @AppStorage("recentPIDs") private var recentPIDs: [Int] = []
    @State private var justCopied = false
    
    @State private var viewDidAppeared = false
    @State private var pendingJITEnableConfiguration : JITEnableConfiguration? = nil
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    
    @AppStorage("enablePiP") private var enablePiP = true
    @State var scriptViewShow = false
    @State private var pipRequired = false
    @AppStorage("DefaultScriptName") var selectedScript = "attachDetach.js"
    @State var jsModel: RunJSViewModel?
    
    @ObservedObject private var mounting = MountingProgress.shared
    @ObservedObject private var deviceStore = DeviceLibraryStore.shared
    @State private var heartbeatOK = false
    @State private var cachedAppNames: [String: String] = [:]
    @AppStorage("pinnedSystemApps") private var pinnedSystemApps: [String] = []
    @AppStorage("pinnedSystemAppNames") private var pinnedSystemAppNames: [String: String] = [:]
    @State private var launchingSystemApps: Set<String> = []
    @State private var systemLaunchMessage: String? = nil
    @State private var connectionCheckState: ConnectionCheckState = .idle
    @State private var connectionInfoMessage: String? = nil
    @State private var hasAutoStartedConnectionCheck = false
    @State private var connectionTimeoutTask: DispatchWorkItem? = nil
    @State private var wifiConnected = false
    @State private var wifiMonitor: NWPathMonitor? = nil
    @State private var isCellularActive = false
    @State private var cellularMonitor: NWPathMonitor? = nil
    @State private var isSchedulingInitialSetup = false
    @AppStorage("cachedAppNamesData") private var cachedAppNamesData: Data?
    
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.themeExpansionManager) private var themeExpansion
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }
    
    private var accentColor: Color {
        themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue
    }
    
    private var ddiMounted: Bool { true }
    private var canConnectByApp: Bool { pairingFileExists && ddiMounted }
    private var requiresLoopbackVPN: Bool { DeviceConnectionContext.requiresLoopbackVPN }
    private var sanitizedUsername: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "there" : trimmed
    }
    
    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }
    private let pairingFileURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Greeting
                    HStack {
                        Text("\(timeOfDayGreeting), \(sanitizedUsername)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    
                    // Status Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Status")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Label("Heartbeat", systemImage: "waveform.path.ecg")
                                    .font(.body.weight(.medium))
                                Spacer()
                                heartbeatStatusBadge
                            }
                            .padding()
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    
                    // Actions Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Actions")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        VStack(spacing: 12) {
                            Button(action: primaryActionTapped) {
                                HStack {
                                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if isValidatingPairingFile {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                                .padding()
                                .background(accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .disabled(isProcessing || isValidatingPairingFile)
                            
                            if pairingFileExists {
                                 Button {
                                     isShowingPairingFilePicker = true
                                 } label: {
                                     Label("Import New Pairing File", systemImage: "doc.badge.arrow.up")
                                         .font(.subheadline.weight(.medium))
                                         .foregroundColor(.secondary)
                                         .padding()
                                         .frame(maxWidth: .infinity)
                                         .background(Color(UIColor.secondarySystemGroupedBackground))
                                         .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                 }
                            }
                            
                            if let info = connectionInfoMessage, !info.isEmpty {
                                Text(info)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                            }
                            
                            if isImportingFile {
                                pairingImportProgressView
                                    .padding()
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Home")
            .preferredColorScheme(preferredScheme)
            .overlay {
                if isImportingFile {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Processing pairing file…")
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                }
                if showPairingFileMessage && pairingFileIsValid && !isImportingFile {
                    toast("✓ Pairing file successfully imported")
                }
                if justCopied {
                    toast("Copied")
                }
                if let message = systemLaunchMessage {
                    toast(message)
                }
            }
            .onAppear {
                scheduleInitialSetupWork()
                startWiFiMonitoring()
                startCellularMonitoring()
                if !hasAutoStartedConnectionCheck {
                    hasAutoStartedConnectionCheck = true
                    runConnectionDiagnostics(autoStart: true)
                }
                startHeartbeatInBackground()
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ShowPairingFilePicker"),
                    object: nil,
                    queue: .main
                ) { _ in isShowingPairingFilePicker = true }
            }
            .onDisappear {
                connectionTimeoutTask?.cancel()
                connectionTimeoutTask = nil
                stopWiFiMonitoring()
                stopCellularMonitoring()
                hasAutoStartedConnectionCheck = false
            }
            .onReceive(timer) { _ in
                refreshBackground()
                checkPairingFileExists()
                heartbeatOK = pubHeartBeat
                if mounting.mountingThread == nil && !mounting.coolisMounted {
                    MountingProgress.shared.checkforMounted()
                }
            }
            .onChange(of: pairingFileExists) { _, newValue in
                if newValue {
                    loadAppListIfNeeded(force: cachedAppNames.isEmpty)
                    runConnectionDiagnostics()
                } else {
                    cachedAppNames = [:]
                }
            }
            .onChange(of: favoriteApps) { _, _ in
                loadAppListIfNeeded()
                syncFavoriteAppNamesWithCache()
            }
            .onChange(of: recentApps) { _, _ in
                loadAppListIfNeeded()
            }
            .fileImporter(isPresented: $isShowingPairingFilePicker, allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList]) { result in
                switch result {
                case .success(let url):
                    let fileManager = FileManager.default
                    let accessing = url.startAccessingSecurityScopedResource()
                    
                    if fileManager.fileExists(atPath: url.path) {
                        do {
                            let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                            if FileManager.default.fileExists(atPath: dest.path) {
                                try fileManager.removeItem(at: dest)
                            }
                            try fileManager.copyItem(at: url, to: dest)
                            
                            DispatchQueue.main.async {
                                isImportingFile = true
                                importProgress = 0
                                pairingFileExists = true
                            }
                            
                            DispatchQueue.main.async {
                                startHeartbeatInBackground()
                            }
                            
                            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
                                DispatchQueue.main.async {
                                    if importProgress < 1 {
                                        importProgress += 0.25
                                    } else {
                                        t.invalidate()
                                        isImportingFile = false
                                        pairingFileIsValid = true
                                        withAnimation { showPairingFileMessage = true }
                                        MountingProgress.shared.checkforMounted()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            withAnimation { showPairingFileMessage = false }
                                        }
                                    }
                                }
                            }
                            RunLoop.current.add(progressTimer, forMode: .common)
                        } catch { }
                    }
                    if accessing { url.stopAccessingSecurityScopedResource() }
                case .failure:
                    break
                }
            }
            .sheet(isPresented: $isShowingInstalledApps) {
                InstalledAppsListView { selectedBundle in
                    bundleID = selectedBundle
                    isShowingInstalledApps = false
                    HapticFeedbackHelper.trigger()
                    
                    var autoScriptData: Data? = nil
                    var autoScriptName: String? = nil
                    
                    if let scriptInfo = preferredScript(for: selectedBundle) {
                        autoScriptData = scriptInfo.data
                        autoScriptName = scriptInfo.name
                    }
                    
                    startJITInBackground(bundleID: selectedBundle,
                                         pid: nil,
                                         scriptData: autoScriptData,
                                         scriptName: autoScriptName,
                                         triggeredByURLScheme: false)
                }
            }
            .pipify(isPresented: Binding(
                get: { pipRequired && enablePiP },
                set: { pipRequired = $0 }
            )) {
                RunJSViewPiP(model: $jsModel)
            }
            .sheet(isPresented: $scriptViewShow) {
                NavigationStack {
                    if let jsModel {
                        RunJSView(model: jsModel)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { scriptViewShow = false }
                                }
                            }
                            .navigationTitle(selectedScript)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .sheet(isPresented: $showPIDSheet) {
                ConnectByPIDSheet(
                    recentPIDs: $recentPIDs,
                    onPasteCopyToast: { showCopiedToast() },
                    onConnect: { pid in
                        HapticFeedbackHelper.trigger()
                        startJITInBackground(pid: pid)
                    }
                )
            }
            .onOpenURL { url in
                guard let host = url.host else { return }
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                switch host {
                case "enable-jit":
                    var config = JITEnableConfiguration()
                    if let pidStr = components?.queryItems?.first(where: { $0.name == "pid" })?.value, let pid = Int(pidStr) {
                        config.pid = pid
                    }
                    if let bundleId = components?.queryItems?.first(where: { $0.name == "bundle-id" })?.value {
                        config.bundleID = bundleId
                    }
                    if let scriptBase64URL = components?.queryItems?.first(where: { $0.name == "script-data" })?.value?.removingPercentEncoding {
                        let base64 = base64URLToBase64(scriptBase64URL)
                        if let scriptData = Data(base64Encoded: base64) {
                            config.scriptData = scriptData
                        }
                    }
                    if let scriptName = components?.queryItems?.first(where: { $0.name == "script-name" })?.value {
                        config.scriptName = scriptName
                    }
                    if config.scriptData == nil, let bundleID = config.bundleID,
                       let scriptInfo = preferredScript(for: bundleID) {
                        config.scriptData = scriptInfo.data
                        config.scriptName = scriptInfo.name
                    }
                    if viewDidAppeared {
                        startJITInBackground(bundleID: config.bundleID, pid: config.pid, scriptData: config.scriptData, scriptName: config.scriptName, triggeredByURLScheme: true)
                    } else {
                        pendingJITEnableConfiguration = config
                    }
                case "launch-app":
                    if let bundleId = components?.queryItems?.first(where: { $0.name == "bundle-id" })?.value {
                        HapticFeedbackHelper.trigger()
                        DispatchQueue.global(qos: .userInitiated).async {
                            let success = JITEnableContext.shared.launchAppWithoutDebug(bundleId, logger: nil)
                            DispatchQueue.main.async {
                                let nameRaw = pinnedSystemAppNames[bundleId] ?? friendlyName(for: bundleId)
                                let name = shortDisplayName(from: nameRaw)
                                systemLaunchMessage = success
                                ? String(format: "Launch requested: %@".localized, name)
                                : String(format: "Failed to launch %@".localized, name)
                                scheduleSystemToastDismiss()
                            }
                        }
                    }
                default:
                    break
                }
            }
            .onAppear {
                viewDidAppeared = true
                if let config = pendingJITEnableConfiguration {
                    startJITInBackground(bundleID: config.bundleID, pid: config.pid, scriptData: config.scriptData, scriptName: config.scriptName, triggeredByURLScheme: true)
                    pendingJITEnableConfiguration = nil
                }
            }
        }
    }
    
    // MARK: - Status Badges

    @ViewBuilder
    private var heartbeatStatusBadge: some View {
        switch heartbeatIndicatorStatus {
        case .success:
            Text("Connected")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.green)
        case .running:
             Text("Starting…")
                .font(.caption)
                .foregroundColor(.orange)
        case .warning:
            Text("Waiting")
                .font(.caption)
                .foregroundColor(.yellow)
        case .error:
            Text("Error")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.red)
        case .idle:
            Text("Idle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
    }
    
    private func startWiFiMonitoring() {
        guard wifiMonitor == nil else { return }
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        wifiMonitor = monitor
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                wifiConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func stopWiFiMonitoring() {
        wifiMonitor?.cancel()
        wifiMonitor = nil
    }
    
    private func startCellularMonitoring() {
        guard cellularMonitor == nil else { return }
        let monitor = NWPathMonitor(requiredInterfaceType: .cellular)
        cellularMonitor = monitor
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                isCellularActive = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func stopCellularMonitoring() {
        cellularMonitor?.cancel()
        cellularMonitor = nil
        isCellularActive = false
    }
    
    private var isConnectionCheckRunning: Bool { false }

    private var heartbeatSubtitle: String {
        if heartbeatOK {
            return "Heartbeat is responding."
        }
        if !requiresLoopbackVPN && pairingFileExists {
            return "Waiting for a response."
        }
        if !pairingFileExists {
            return "Import a pairing file to start the heartbeat."
        }
        if case .running = connectionCheckState {
            return "Waiting for the connection check to finish."
        }
        if case .success = connectionCheckState {
            return "We’ll start heartbeat automatically—leave the app open."
        }
        return "Heartbeat runs after the connection check completes."
    }
    
    private var heartbeatIndicatorStatus: StartupIndicatorStatus {
        if heartbeatOK { return .success }
        return .warning
    }
    
    private func runConnectionDiagnostics(autoStart: Bool = false) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        connectionCheckState = .success
        connectionInfoMessage = nil
        if pairingFileExists && !heartbeatOK {
            startHeartbeatInBackground()
        }
    }
    
        private var primaryActionTitle: String {
            if isValidatingPairingFile { return "Validating…" }
            if !pairingFileExists { return pairingFilePresentOnDisk ? "Import New Pairing File" : "Import Pairing File" }
            if !ddiMounted { return "Mount Developer Disk Image" }
            return "Enable JIT"
        }

        private var primaryActionIcon: String {
            if isValidatingPairingFile { return "hourglass" }
            if !pairingFileExists { return pairingFilePresentOnDisk ? "arrow.clockwise" : "doc.badge.plus" }
            if !ddiMounted { return "externaldrive" }
            return "cable.connector.horizontal"
        }
        
    // MARK: - Import Progress

    private var pairingImportProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Processing pairing file…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(importProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: Double(importProgress))
        }
        .accessibilityElement(children: .combine)
    }
        
    private var pairingSuccessMessage: some View {
        Label("Pairing file successfully imported", systemImage: "checkmark.circle.fill")
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(.green)
            .padding(.top, 4)
            .transition(.opacity)
    }
    
        private var pinnedLaunchItems: [SystemPinnedItem] {
            pinnedSystemApps.compactMap { bundleID in
                let raw = pinnedSystemAppNames[bundleID] ?? friendlyName(for: bundleID)
                let displayName = shortDisplayName(from: raw)
                return SystemPinnedItem(bundleID: bundleID, displayName: displayName)
            }
        }
        
        // Prefer CoreDevice-reported app name, trimmed to a Home Screen–style label; else fall back to bundle ID last component.
        private func friendlyName(for bundleID: String) -> String {
            if let cached = cachedAppNames[bundleID], !cached.isEmpty {
                return shortDisplayName(from: cached)
            }
            let components = bundleID.split(separator: ".")
            if let last = components.last {
                let cleaned = last.replacingOccurrences(of: "_", with: " ")
                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed.capitalized }
            }
            return bundleID
        }
        
        // Heuristic “Home Screen” shortener for long marketing names.
        private func shortDisplayName(from name: String) -> String {
            var s = name
            
            // Keep only the part before common separators/subtitles.
            let separators = [" — ", " – ", " - ", ":", "|", "·", "•"]
            for sep in separators {
                if let r = s.range(of: sep) {
                    s = String(s[..<r.lowerBound])
                    break
                }
            }
            
            // Drop common suffixes like "for iPad", "for iOS"
            let suffixes = [
                " for iPhone", " for iPad", " for iOS", " for iPadOS",
                " iPhone", " iPad", " iOS", " iPadOS"
            ]
            for suf in suffixes {
                if s.localizedCaseInsensitiveContains(suf) {
                    s = s.replacingOccurrences(of: suf, with: "", options: [.caseInsensitive])
                }
            }
            
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? name : s
        }
        
        private func scheduleInitialSetupWork() {
            guard !isSchedulingInitialSetup else { return }
            isSchedulingInitialSetup = true
            
            let shouldRestoreCache = cachedAppNames.isEmpty
            let cachedData = cachedAppNamesData
            
            DispatchQueue.global(qos: .userInitiated).async {
                var restoredApps: [String: String]? = nil
                if shouldRestoreCache, let cachedData {
                    restoredApps = try? JSONDecoder().decode([String: String].self, from: cachedData)
                }
                
                DispatchQueue.main.async {
                    defer { isSchedulingInitialSetup = false }
                    
                    if let restoredApps, cachedAppNames.isEmpty {
                        cachedAppNames = restoredApps
                        syncFavoriteAppNamesWithCache()
                    }
                    
                    refreshBackground()
                    checkPairingFileExists()
                    loadAppListIfNeeded()
                    MountingProgress.shared.checkforMounted()
                }
            }
        }
        
        private func loadAppListIfNeeded(force: Bool = false) {
            guard pairingFileExists else {
                cachedAppNames = [:]
                cachedAppNamesData = nil
                return
            }
            
            if !force && !cachedAppNames.isEmpty { return }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let result = (try? JITEnableContext.shared.getAppList()) ?? [:]
                let encoded = try? JSONEncoder().encode(result)
                DispatchQueue.main.async {
                    cachedAppNames = result
                    syncFavoriteAppNamesWithCache()
                    cachedAppNamesData = encoded
                }
            }
        }
        
        private func tipRow(systemImage: String, title: String, message: String) -> some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(accentColor)
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        
        private func primaryActionTapped() {
            guard !isValidatingPairingFile else { return }
            if !ddiMounted {
                showAlert(title: "Device Not Mounted".localized, message: "The Developer Disk Image has not been mounted yet. Check in settings for more information.".localized, showOk: true) { _ in }
                return
            }
            isShowingInstalledApps = true
        }
        
        private func showCopiedToast() {
            withAnimation { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation { justCopied = false }
            }
        }
        
        @ViewBuilder private func toast(_ text: String) -> some View {
            VStack {
                Spacer()
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 30)
            }
            .animation(.easeInOut(duration: 0.25), value: text)
        }
        
        private func checkPairingFileExists() {
            // Home screen no longer blocks on pairing file checks; assume available.
            pairingFileExists = true
            pairingFilePresentOnDisk = true
            isValidatingPairingFile = false
        }
        
        private func needsValidation(for signature: PairingFileSignature) -> Bool {
            guard let lastSignature = lastValidatedPairingSignature else { return true }
            return lastSignature != signature
        }
        
        
        private func pairingFileSignature(for url: URL) -> PairingFileSignature {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let modificationDate = attributes[.modificationDate] as? Date
            let sizeValue = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            return PairingFileSignature(modificationDate: modificationDate, fileSize: sizeValue)
        }
        private func refreshBackground() { }
        
        private func autoScript(for bundleID: String) -> (data: Data, name: String)? {
            guard ProcessInfo.processInfo.hasTXM else { return nil }
            guard #available(iOS 26, *) else { return nil }
            let appName = (try? JITEnableContext.shared.getAppList()[bundleID]) ?? storedFavoriteName(for: bundleID)
            guard let appName,
                  let resource = autoScriptResource(for: appName) else {
                return nil
            }
            let scriptsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("scripts")
            let documentsURL = scriptsDir.appendingPathComponent(resource.fileName)
            if let data = try? Data(contentsOf: documentsURL) {
                return (data, resource.fileName)
            }
            guard let bundleURL = Bundle.main.url(forResource: resource.resource, withExtension: "js"),
                  let data = try? Data(contentsOf: bundleURL) else {
                return nil
            }
            return (data, resource.fileName)
        }
        
        private func assignedScript(for bundleID: String) -> (data: Data, name: String)? {
            guard let mapping = UserDefaults.standard.dictionary(forKey: "BundleScriptMap") as? [String: String],
                  let scriptName = mapping[bundleID] else { return nil }
            let scriptsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("scripts")
            let scriptURL = scriptsDir.appendingPathComponent(scriptName)
            guard FileManager.default.fileExists(atPath: scriptURL.path),
                  let data = try? Data(contentsOf: scriptURL) else { return nil }
            return (data, scriptName)
        }
        
        private func preferredScript(for bundleID: String) -> (data: Data, name: String)? {
            if let assigned = assignedScript(for: bundleID) {
                return assigned
            }
            return autoScript(for: bundleID)
        }
        
        private func storedFavoriteName(for bundleID: String) -> String? {
            let defaults = UserDefaults(suiteName: "group.com.stik.sj")
            let names = defaults?.dictionary(forKey: "favoriteAppNames") as? [String: String]
            return names?[bundleID]
        }
        
        private func syncFavoriteAppNamesWithCache() {
            guard let sharedDefaults = UserDefaults(suiteName: "group.com.stik.sj") else { return }
            let favorites = sharedDefaults.stringArray(forKey: "favoriteApps") ?? []
            guard !favorites.isEmpty else { return }
            
            var storedNames = (sharedDefaults.dictionary(forKey: "favoriteAppNames") as? [String: String]) ?? [:]
            var changed = false
            
            for bundle in favorites {
                guard let rawName = cachedAppNames[bundle], !rawName.isEmpty else { continue }
                let display = shortDisplayName(from: rawName)
                if storedNames[bundle] != display {
                    storedNames[bundle] = display
                    changed = true
                }
            }
            
            if changed {
                sharedDefaults.set(storedNames, forKey: "favoriteAppNames")
                WidgetCenter.shared.reloadTimelines(ofKind: "FavoritesWidget")
            }
        }
        
        private func autoScriptResource(for appName: String) -> (resource: String, fileName: String)? {
            switch appName {
            case "maciOS":
                return ("maciOS", "maciOS.js")
            case "Amethyst", "MeloNX":
                return ("Amethyst-MeloNX", "Amethyst-MeloNX.js")
            case "Geode":
                return ("Geode", "Geode.js")
            case "Manic EMU":
                return ("manic", "manic.js")
            case "UTM", "DolphiniOS", "Flycast":
                return ("UTM-Dolphin", "UTM-Dolphin.js")
            default:
                return nil
            }
        }
        
        private func getJsCallback(_ script: Data, name: String? = nil) -> DebugAppCallback {
            return { pid, debugProxyHandle, remoteServerHandle, semaphore in
                let model = RunJSViewModel(pid: Int(pid),
                                           debugProxy: debugProxyHandle,
                                           remoteServer: remoteServerHandle,
                                           semaphore: semaphore)
                
                DispatchQueue.main.async {
                    jsModel = model
                    scriptViewShow = true
                    pipRequired = true
                }
                
                DispatchQueue.global(qos: .background).async {
                    do { try model.runScript(data: script, name: name) }
                    catch { showAlert(title: "Error Occurred While Executing Script.".localized, message: error.localizedDescription, showOk: true) }
                }
            }
        }
        
        private func startJITInBackground(bundleID: String? = nil, pid : Int? = nil, scriptData: Data? = nil, scriptName: String? = nil, triggeredByURLScheme: Bool = false) {
            isProcessing = true
            LogManager.shared.addInfoLog("Starting Debug for \(bundleID ?? String(pid ?? 0))")
            
            DispatchQueue.global(qos: .background).async {
                let finishProcessing = {
                    DispatchQueue.main.async {
                        isProcessing = false
                        pipRequired = false
                    }
                }
                
                var scriptData = scriptData
                var scriptName = scriptName
                if scriptData == nil,
                   let bundleID,
                   let preferred = preferredScript(for: bundleID) {
                    scriptName = preferred.name
                    scriptData = preferred.data
                }
                
                var callback: DebugAppCallback? = nil
                if ProcessInfo.processInfo.hasTXM, let sd = scriptData {
                    callback = getJsCallback(sd, name: scriptName ?? bundleID ?? "Script")
                    if triggeredByURLScheme { usleep(500000) }
                    DispatchQueue.main.async { pipRequired = true }
                } else {
                    DispatchQueue.main.async { pipRequired = false }
                }
                
                let logger: LogFunc = { message in if let message { LogManager.shared.addInfoLog(message) } }
                var success: Bool
                if let pid {
                    success = JITEnableContext.shared.debugApp(withPID: Int32(pid), logger: logger, jsCallback: callback)
                    if success { DispatchQueue.main.async { addRecentPID(pid) } }
                } else if let bundleID {
                    success = JITEnableContext.shared.debugApp(withBundleID: bundleID, logger: logger, jsCallback: callback)
                } else {
                    DispatchQueue.main.async {
                        showAlert(title: "Failed to Debug App".localized, message: "Either bundle ID or PID should be specified.".localized, showOk: true)
                    }
                    success = false
                }
                
                if success {
                    DispatchQueue.main.async {
                        LogManager.shared.addInfoLog("Debug process completed for \(bundleID ?? String(pid ?? 0))")
                    }
                }
                finishProcessing()
            }
        }
        
        private func launchSystemApp(item: SystemPinnedItem) {
            guard !launchingSystemApps.contains(item.bundleID) else { return }
            launchingSystemApps.insert(item.bundleID)
            HapticFeedbackHelper.trigger()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let success = JITEnableContext.shared.launchAppWithoutDebug(item.bundleID, logger: nil)
                
                DispatchQueue.main.async {
                    launchingSystemApps.remove(item.bundleID)
                    if success {
                        LogManager.shared.addInfoLog("Launch request sent for \(item.bundleID)")
                        systemLaunchMessage = String(format: "Launch requested: %@".localized, item.displayName)
                    } else {
                        LogManager.shared.addErrorLog("Failed to launch \(item.bundleID)")
                        systemLaunchMessage = String(format: "Failed to launch %@".localized, item.displayName)
                    }
                    scheduleSystemToastDismiss()
                }
            }
        }
        
        private func removePinnedSystemApp(bundleID: String) {
            Haptics.light()
            pinnedSystemApps.removeAll { $0 == bundleID }
            pinnedSystemAppNames.removeValue(forKey: bundleID)
            persistPinnedSystemApps()
        }
        
        private func scheduleSystemToastDismiss() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if systemLaunchMessage != nil {
                    withAnimation {
                        systemLaunchMessage = nil
                    }
                }
            }
        }
        
        private func persistPinnedSystemApps() {
            if let sharedDefaults = UserDefaults(suiteName: "group.com.stik.sj") {
                sharedDefaults.set(pinnedSystemApps, forKey: "pinnedSystemApps")
                sharedDefaults.set(pinnedSystemAppNames, forKey: "pinnedSystemAppNames")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        private func addRecentPID(_ pid: Int) {
            var list = recentPIDs.filter { $0 != pid }
            list.insert(pid, at: 0)
            if list.count > 8 { list = Array(list.prefix(8)) }
            recentPIDs = list
        }
        
        func base64URLToBase64(_ base64url: String) -> String {
            var base64 = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            let pad = 4 - (base64.count % 4)
            if pad < 4 { base64 += String(repeating: "=", count: pad) }
            return base64
        }
        
        
        private struct SystemPinnedRow: View {
            let item: SystemPinnedItem
            let accentColor: Color
            let isLaunching: Bool
            var action: () -> Void
            var onRemove: () -> Void

            var body: some View {
                Button(action: action) {
                    HStack(spacing: 14) {
                        QuickAppBadge(title: item.displayName, accentColor: accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if isLaunching {
                            ProgressView().controlSize(.small).tint(accentColor)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLaunching)
                .contextMenu {
                    Button("Remove from Home".localized, systemImage: "star.slash") { onRemove() }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { onRemove() } label: {
                        Label("Remove".localized, systemImage: "trash")
                    }
                }
            }
        }
        
        private struct QuickAppBadge: View {
            let title: String
            let accentColor: Color
            
            private var initials: String {
                let words = title.split(separator: " ")
                if let first = words.first, !first.isEmpty {
                    return String(first.prefix(1)).uppercased()
                }
                return String(title.prefix(1)).uppercased()
            }
            
            var body: some View {
                Text(initials)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(0.16))
                    )
                    .foregroundStyle(accentColor)
            }
        }
        
        private struct PairingFileSignature: Equatable {
            let modificationDate: Date?
            let fileSize: UInt64
        }
        
        private enum ConnectionCheckState: Equatable {
            case idle
            case running
            case success
            case failure(String)
            case timeout
        }
        
        private enum StartupIndicatorStatus: Equatable {
            case idle, running, success, warning, error
        }
        private struct SystemPinnedItem: Identifiable {
            let bundleID: String
            let displayName: String
            var id: String { bundleID }
        }
        
        private struct SafariView: UIViewControllerRepresentable {
            let url: URL
            
            func makeUIViewController(context: Context) -> SFSafariViewController {
                return SFSafariViewController(url: url)
            }
            
            func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
        }
        
        // MARK: - Connect-by-PID Sheet (minus/plus removed)
        
        private struct ConnectByPIDSheet: View {
            @Environment(\.dismiss) private var dismiss
            @Binding var recentPIDs: [Int]
            @State private var pidText: String = ""
            @State private var errorText: String? = nil
            @FocusState private var focused: Bool
            var onPasteCopyToast: () -> Void
            var onConnect: (Int) -> Void
            
            private var isValid: Bool {
                if let v = Int(pidText), v > 0 { return true }
                return false
            }
            
            private let capsuleHeight: CGFloat = 40
            
            var body: some View {
                NavigationStack {
                    Form {
                        Section {
                            TextField("e.g. 1234", text: $pidText)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.system(.title3, design: .rounded))
                                .focused($focused)
                                .onChange(of: pidText) { _, newVal in validate(newVal) }

                            HStack(spacing: 10) {
                                CapsuleButton(systemName: "doc.on.clipboard", title: "Paste", height: capsuleHeight) {
                                    if let n = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       let v = Int(n), v > 0 {
                                        pidText = String(v)
                                        validate(pidText)
                                        onPasteCopyToast()
                                    } else {
                                        errorText = "No valid PID on the clipboard."
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                }
                                CapsuleButton(systemName: "xmark", title: "Clear", height: capsuleHeight) {
                                    pidText = ""
                                    errorText = nil
                                }
                            }

                            if let errorText {
                                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        } header: {
                            Text("Enter a Process ID")
                        }

                        if !recentPIDs.isEmpty {
                            Section("Recents") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(recentPIDs, id: \.self) { pid in
                                            Button {
                                                pidText = String(pid); validate(pidText)
                                            } label: {
                                                Text("#\(pid)")
                                                    .font(.footnote.weight(.semibold))
                                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                                    .background(Capsule(style: .continuous).fill(Color(UIColor.tertiarySystemBackground)))
                                            }
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button(role: .destructive) { removeRecent(pid) } label: {
                                                    Label("Remove", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }

                        Section {
                            Button {
                                guard let pid = Int(pidText), pid > 0 else { return }
                                onConnect(pid)
                                addRecent(pid)
                                dismiss()
                            } label: {
                                Label("Connect", systemImage: "bolt.horizontal.circle")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isValid)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .navigationTitle("Connect by PID")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
                    .onAppear { focused = true }
                }
            }
            
            private func validate(_ text: String) {
                if text.isEmpty { errorText = nil; return }
                if Int(text) == nil || Int(text)! <= 0 { errorText = "Please enter a positive number." }
                else { errorText = nil }
            }
            private func addRecent(_ pid: Int) {
                var list = recentPIDs.filter { $0 != pid }
                list.insert(pid, at: 0)
                if list.count > 8 { list = Array(list.prefix(8)) }
                recentPIDs = list
            }
            private func removeRecent(_ pid: Int) { recentPIDs.removeAll { $0 == pid } }
            private func prefillFromClipboardIfPossible() {
                if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let v = Int(s), v > 0 {
                    pidText = String(v); errorText = nil
                }
            }
            
            @ViewBuilder private func CapsuleButton(systemName: String, title: String, height: CGFloat = 40, action: @escaping () -> Void) -> some View {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: systemName)
                        Text(title).font(.subheadline.weight(.semibold))
                    }
                    .frame(height: height) // enforce uniform height
                    .padding(.horizontal, 12)
                    .background(Capsule(style: .continuous).fill(Color(UIColor.tertiarySystemBackground)))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }

    }
public extension ProcessInfo {
    var hasTXM: Bool {
        if isTXMOverridden {
            return true
        }
        if DeviceLibraryStore.shared.isUsingExternalDevice {
            return DeviceLibraryStore.shared.activeDevice?.isTXM ?? false
        }
        return ProcessInfo.detectLocalTXM()
    }
    
    var isTXMOverridden: Bool {
        UserDefaults.standard.bool(forKey: UserDefaults.Keys.txmOverride)
    }
    
    private static func detectLocalTXM() -> Bool {
        if let boot = FileManager.default.filePath(atPath: "/System/Volumes/Preboot", withLength: 36),
           let file = FileManager.default.filePath(atPath: "\(boot)/boot", withLength: 96) {
            return access("\(file)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0
        } else {
            return (FileManager.default.filePath(atPath: "/private/preboot", withLength: 96).map {
                access("\($0)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0
            }) ?? false
        }
    }
}
