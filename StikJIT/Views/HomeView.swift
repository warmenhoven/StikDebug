//
//  ContentView.swift
//  StikJIT
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {

    @AppStorage("username") private var username = "User"
    @AppStorage("customBackgroundColor") private var customBackgroundColorHex: String = Color.primaryBackground.toHex() ?? "#000000"
    @AppStorage("autoQuitAfterEnablingJIT") private var doAutoQuitAfterEnablingJIT = false
    @State private var selectedBackgroundColor: Color = Color(hex: UserDefaults.standard.string(forKey: "customBackgroundColor") ?? "#000000") ?? Color.primaryBackground
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage("bundleID") private var bundleID: String = ""
    @State private var isProcessing = false
    @State private var isShowingInstalledApps = false
    @State private var isShowingPairingFilePicker = false
    @State private var pairingFileExists: Bool = false
    @State private var showPairingFileMessage = false
    @State private var pairingFileIsValid = false
    @State private var isImportingFile = false
    @State private var importProgress: Float = 0.0
    
    @State private var viewDidAppeared = false
    @State private var pendingBundleIdToEnableJIT : String? = nil
    
    @State var scriptViewShow = false
    @State private var isShowingConsole = false
    @AppStorage("DefaultScriptName") var selectedScript = "attachDetach.js"
    @State var jsModel: RunJSViewModel?
    @ObservedObject private var mounting = MountingProgress.shared


    var body: some View {
        ZStack {
            selectedBackgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 25) {
                Spacer()
                VStack(spacing: 5) {
                    Text("Welcome to StikDebug \(username)!")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    Text(pairingFileExists ? "Click enable JIT to get started" : "Pick pairing file to get started")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Main action button - changes based on whether we have a pairing file
                Button(action: {
                    
                    
                    if pairingFileExists {
                        // Refresh heartbeat
                        pubHeartBeat = false
                        startHeartbeatInBackground()
                        
                        // Got a pairing file, show apps
                        if !mounting.coolisMounted {
                            showAlert(title: "Device Not Mounted", message: "The Developer Disk Image has not been mounted yet. Check in settings for more information.", showOk: true) { cool in
                                // No Need
                            }
                            return
                        }
                        
                        isShowingInstalledApps = true
                        
                    } else {
                        // No pairing file yet, let's get one
                        isShowingPairingFilePicker = true
                    }
                }) {
                    HStack {
                        Image(systemName: pairingFileExists ? "bolt.fill" : "doc.badge.plus")
                            .font(.system(size: 20))
                        Text(pairingFileExists ? "Enable JIT" : "Select Pairing File")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 20)

                Button(action: {
                    isShowingConsole = true
                }) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.system(size: 20))
                        Text("Open Console")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 20)

                // Status message area - keeps layout consistent
                ZStack {
                    // Progress bar for importing file
                    if isImportingFile {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Processing pairing file...")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(.secondaryText)
                                Spacer()
                                Text("\(Int(importProgress * 100))%")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(.secondaryText)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.black.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green)
                                        .frame(width: geometry.size.width * CGFloat(importProgress), height: 8)
                                        .animation(.linear(duration: 0.3), value: importProgress)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    // Success message
                    if showPairingFileMessage && pairingFileIsValid {
                        Text("✓ Pairing file successfully imported")
                            .font(.system(.callout, design: .rounded))
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                    
                    // Invisible text to reserve space - no layout jumps
                    Text(" ").opacity(0)
                }
                .frame(height: isImportingFile ? 60 : 30)  // Adjust height based on what's showing
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            checkPairingFileExists()
            startHeartbeatInBackground()
            MountingProgress.shared.checkforMounted()
        }
        .onReceive(timer) { _ in
            refreshBackground()
            checkPairingFileExists()
            if mounting.mountingThread == nil && !mounting.coolisMounted {
                MountingProgress.shared.checkforMounted()
            }
        }
        .fileImporter(isPresented: $isShowingPairingFilePicker, allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList]) {result in
            switch result {
            
            case .success(let url):
                let fileManager = FileManager.default
                let accessing = url.startAccessingSecurityScopedResource()
                
                if fileManager.fileExists(atPath: url.path) {
                    do {
                        if fileManager.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path) {
                            try fileManager.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                        }
                        
                        try fileManager.copyItem(at: url, to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                        print("File copied successfully!")
                        
                        // Show progress bar and initialize progress
                        DispatchQueue.main.async {
                            isImportingFile = true
                            importProgress = 0.0
                            pairingFileExists = true
                        }
                        
                        // Start heartbeat in background
                        startHeartbeatInBackground()
                        
                        // Create timer to update progress instead of sleeping
                        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                            DispatchQueue.main.async {
                                if importProgress < 1.0 {
                                    importProgress += 0.25
                                } else {
                                    timer.invalidate()
                                    isImportingFile = false
                                    pairingFileIsValid = true
                                    
                                    // Show success message
                                    withAnimation {
                                        showPairingFileMessage = true
                                    }
                                    
                                    // Hide message after delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation {
                                            showPairingFileMessage = false
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Ensure timer keeps running
                        RunLoop.current.add(progressTimer, forMode: .common)
                        
                    } catch {
                        print("Error copying file: \(error)")
                    }
                } else {
                    print("Source file does not exist.")
                }
                
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            case .failure(let error):
                print("Failed to import file: \(error)")
            }
        }
        .sheet(isPresented: $isShowingInstalledApps) {
            InstalledAppsListView { selectedBundle in
                bundleID = selectedBundle
                isShowingInstalledApps = false
                HapticFeedbackHelper.trigger()
                startJITInBackground(with: selectedBundle)
            }
        }
        .onOpenURL { url in
            print(url.path())
            if url.host() != "enable-jit" {
                return
            }
            
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let bundleId = components?.queryItems?.first(where: { $0.name == "bundle-id" })?.value {
                if viewDidAppeared {
                    startJITInBackground(with: bundleId)
                } else {
                    pendingBundleIdToEnableJIT = bundleId
                }
            }
            
        }
        .onAppear() {
            viewDidAppeared = true
            if let pendingBundleIdToEnableJIT {
                startJITInBackground(with: pendingBundleIdToEnableJIT)
                self.pendingBundleIdToEnableJIT = nil
            }
        }
        .sheet(isPresented: $isShowingConsole) {
            NavigationStack {
                ConsoleLogsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                isShowingConsole = false
                            }
                        }
                    }
            }
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
    }
    

    
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
            }
            
            DispatchQueue.global(qos: .background).async {
                do { try model.runScript(data: script, name: name) }
                catch { showAlert(title: "Error Occurred While Executing Script.".localized, message: error.localizedDescription, showOk: true) }
            }
        }
    }
    
    private func checkPairingFileExists() {
        pairingFileExists = FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path)
    }
    
    private func refreshBackground() {
        selectedBackgroundColor = Color(hex: customBackgroundColorHex) ?? Color.primaryBackground
    }
    
    private func startJITInBackground(with bundleID: String) {
        isProcessing = true
        LogManager.shared.addInfoLog("Starting JIT for \(bundleID)")
        
        DispatchQueue.global(qos: .background).async {
            let finishProcessing = {
                DispatchQueue.main.async {
                    isProcessing = false
                }
            }
            
            var scriptData: Data? = nil
            var scriptName: String? = nil
            
            if let preferred = preferredScript(for: bundleID) {
                scriptName = preferred.name
                scriptData = preferred.data
            }
            
            var callback: DebugAppCallback? = nil
            if ProcessInfo.processInfo.hasTXM, let sd = scriptData {
                callback = getJsCallback(sd, name: scriptName ?? bundleID)
            }

            let logger: LogFunc = { message in if let message { LogManager.shared.addInfoLog(message) } }
            
            let success = JITEnableContext.shared.debugApp(withBundleID: bundleID, logger: logger, jsCallback: callback)
            
            DispatchQueue.main.async {
                LogManager.shared.addInfoLog("JIT process completed for \(bundleID)")
                
                if success && doAutoQuitAfterEnablingJIT {
                    exit(0)
                }
            }
            finishProcessing()
        }
    }
}

#Preview {
    HomeView()
}

public extension ProcessInfo {
    var hasTXM: Bool {
        if isTXMOverridden {
            return true
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
