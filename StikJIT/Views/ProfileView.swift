//
//  ProfileView.swift
//  StikDebug
//
//  Created by s s on 2025/11/29.
//
import SwiftUI
import UniformTypeIdentifiers

class Profile: ObservableObject {
    private static let dateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
    let data: Data
    @Published var appName: String = "unknown"
    @Published var appId: String = "unknown"
    @Published var uuid: String
    @Published var expirationDate: Date? = nil
    @Published var plistDict: [String:Any]? = nil
    
    init(data: Data) {
        self.data = data
        do {
            let plistData = try CMSDecoderHelper.decodeCMSData(data)
            let plistDict = try PropertyListSerialization.propertyList(from: plistData, format: nil)
            if let plistDict = plistDict as? [String:Any] {
                self.plistDict = plistDict
                self.appName = plistDict["AppIDName"] as? String ?? "unknown"
                if let entitlementsDict = plistDict["Entitlements"] as? [String:Any] {
                    self.appId = entitlementsDict["application-identifier"] as? String ?? "unknown"
                }
                self.expirationDate = plistDict["ExpirationDate"] as? Date
                self.uuid = plistDict["UUID"] as? String ?? UUID().uuidString
            } else {
                self.uuid = UUID().uuidString
            }
        } catch {
            appName = "Failed to decode this profile."
            appId = error.localizedDescription
            uuid = UUID().uuidString
        }
    }
    
    var formattedDate: String {
        get {
            if let expirationDate {
                return Profile.dateFormatter.string(from: expirationDate)
            } else {
                return "Unknown"
            }
        }
    }
    
    // from AltStore
    var dateColor: Color {
        get {
            guard let expirationDate else {
                return .secondary
            }
            let currentDate = Date()
            let numberOfDays = expirationDate.numberOfCalendarDays(since: currentDate)
            switch numberOfDays
            {
            case 2...3: return .refreshOrange
            case 4...5: return .refreshYellow
            case 6...: return .refreshGreen
            default: return .refreshRed
            }
        }
    }
}

struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "mobileprovision")!] }
    
    var data: Data? = nil
    
    init() {}
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data ?? Data())
    }
}

// the following 2 extensions are from AltStore
extension Color {
    static let refreshRed = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let refreshOrange = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let refreshYellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let refreshGreen = Color(red: 0.204, green: 0.780, blue: 0.348)
    
}

extension Date {
    func numberOfCalendarDays(since date: Date) -> Int
    {
        let today = Calendar.current.startOfDay(for: self)
        let previousDay = Calendar.current.startOfDay(for: date)
        
        let components = Calendar.current.dateComponents([.day], from: previousDay, to: today)
        return components.day!
    }
}

struct ProfileView: View {
    @State private var working = true
    @State private var isExporterPresented = false
    @State private var exportFileName = ""
    @State private var exportDoc = ProfileDocument()
    @State private var isImporterPresented = false
    
    @State private var searchText = ""
    @State private var alert = false
    @State private var alertTitle = ""
    @State private var alertMsg = ""
    @State private var alertSuccess = false
    
    @State private var profiles: [Profile] = []
    @AppStorage("cachedProfilesData") private var cachedProfilesData: Data?
    @State private var confirmRemove = false
    @State private var removeTargetName: String = ""
    @State private var removeTargetUUID: String = ""
    @State private var expandedAppIds: Set<String> = []
    
    // Computed property to group profiles by appId and sort by expiration date
    private var groupedProfiles: [String: [Profile]] {
        Dictionary(grouping: profiles, by: { $0.appId })
            .mapValues { profiles in
                profiles.sorted { profile1, profile2 in
                    // Sort by expiration date descending (latest first)
                    guard let date1 = profile1.expirationDate else { return false }
                    guard let date2 = profile2.expirationDate else { return true }
                    return date1 > date2
                }
            }
    }
    
    private var sortedAppIds: [String] {
        groupedProfiles.keys.sorted()
    }
    
    
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.themeExpansionManager) private var themeExpansion
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }
    private var accentColor: Color { themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue }

    var body: some View {
        NavigationStack {
            List {
                if profiles.isEmpty {
                    Section {
                        Text(working ? "Loading Profiles…" : "No profiles available.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sortedAppIds, id: \.self) { appId in
                        if let appProfiles = groupedProfiles[appId] {
                            Section {
                                let displayProfiles: [Profile] = expandedAppIds.contains(appId)
                                    ? appProfiles
                                    : Array(appProfiles.prefix(1))
                                ForEach(Array(displayProfiles.enumerated()), id: \.element.uuid) { pair in
                                    profileEntryRow(profile: pair.element, isLatest: pair.offset == 0)
                                }
                                if appProfiles.count > 1 {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            if expandedAppIds.contains(appId) {
                                                expandedAppIds.remove(appId)
                                            } else {
                                                expandedAppIds.insert(appId)
                                            }
                                        }
                                    } label: {
                                        Text(expandedAppIds.contains(appId)
                                             ? "Show Less"
                                             : "Show \(appProfiles.count - 1) More…")
                                            .font(.footnote)
                                    }
                                }
                            } header: {
                                Text(appId)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { isImporterPresented = true } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button { Task { await loadProfiles(force: true) } } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
            .onAppear { Task { await loadProfiles() } }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "mobileprovision")!],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleImport(result: result) }
            }
            .fileExporter(
                isPresented: $isExporterPresented,
                document: exportDoc,
                contentType: .data,
                defaultFilename: exportFileName
            ) { result in
                switch result {
                case .success:
                    break
                case .failure:
                    break
                }
            }
        }
        .tint(accentColor)
        .preferredColorScheme(preferredScheme)
        .overlay {
            if alert {
                CustomErrorView(title: alertTitle,
                                message: alertMsg,
                                onDismiss: { alert = false },
                                messageType: alertSuccess ? .success : .error)
            }
            if confirmRemove {
                CustomErrorView(
                    title: "Confirm Removal",
                    message: "Remove profile for \(removeTargetName) (UUID: \(removeTargetUUID))?\n**Apps associated with this profile may become unavailable.**",
                    onDismiss: { confirmRemove = false },
                    showButton: true,
                    primaryButtonText: "Remove",
                    secondaryButtonText: "Cancel",
                    onPrimaryButtonTap: { Task { await removeProfile(uuid: removeTargetUUID) } },
                    onSecondaryButtonTap: { },
                    showSecondaryButton: true,
                    messageType: .info
                )
            }
        }
    }

    // MARK: - Row

    private func profileEntryRow(profile: Profile, isLatest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.appName).bold()
                Text(profile.uuid).lineLimit(1)
                Text("Expires: \(profile.formattedDate)")
                    .foregroundStyle(isLatest ? profile.dateColor : Color.secondary)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            Spacer()
            HStack(spacing: 14) {
                profileActionButton(icon: "square.and.arrow.down", color: accentColor) {
                    saveProfile(profile: profile)
                }
                profileActionButton(icon: "trash", color: .refreshRed) {
                    removeProfilePrompt(entry: profile)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func profileActionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
        }
        .buttonStyle(.borderless)
    }
    
    private func removeProfilePrompt(entry: Profile) {
        removeTargetName = entry.appName
        removeTargetUUID = entry.uuid
        confirmRemove = true
    }
    
    private func restoreCachedProfilesIfNeeded() async -> Bool {
        guard profiles.isEmpty, let cachedProfilesData else { return false }
        
        let cachedDatas: [Data]? = try? await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode([Data].self, from: cachedProfilesData)
        }.value
        
        guard let cachedDatas, !cachedDatas.isEmpty else { return false }
        let restoredProfiles = cachedDatas.map { Profile(data: $0) }
        await MainActor.run {
            guard self.profiles.isEmpty else { return }
            self.profiles = restoredProfiles
            self.working = false
        }
        return true
    }
    
    func loadProfiles(force: Bool = false) async {
        if !force {
            if !profiles.isEmpty {
                await MainActor.run { working = false }
                return
            }
            if await restoreCachedProfilesIfNeeded() { return }
        }
        
        await MainActor.run { working = true }
        do {
            let profileDatas = try await Task.detached(priority: .userInitiated) {
                try JITEnableContext.shared.fetchAllProfiles()
            }.value
            let parsedProfiles = profileDatas.map { Profile(data: $0) }
            let encodedProfiles = try? JSONEncoder().encode(profileDatas)
            await MainActor.run {
                self.profiles = parsedProfiles
                self.cachedProfilesData = encodedProfiles
                self.working = false
            }
        } catch {
            await MainActor.run {
                alertMsg = error.localizedDescription
                alertTitle = "Failed to Fetch Profiles"
                alertSuccess = false
                alert = true
                working = false
            }
        }
    }
    
    func saveProfile(profile: Profile) {
        exportFileName = "\(profile.appName).mobileprovision"
        exportDoc = ProfileDocument(data: profile.data)
        isExporterPresented = true
    }
    
    func removeProfile(uuid: String) async {
        working = true
        do {
            try JITEnableContext.shared.removeProfile(withUUID: uuid)
            alertMsg = "Profile removed successfully"
            alertTitle = "Success"
            alertSuccess = true
            alert = true
            // Reload profiles after removal
            await loadProfiles(force: true)
        } catch {
            alertMsg = error.localizedDescription
            alertTitle = "Failed to Remove Profile"
            alertSuccess = false
            alert = true
        }
        working = false
    }
    
    func handleImport(result: Result<[URL], Error>) async {
        working = true
        do {
            let fileURL = try result.get().first
            guard let fileURL = fileURL else {
                throw NSError(domain: "ProfileView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No file selected"])
            }
            
            // Start accessing security-scoped resource
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            let profileData = try Data(contentsOf: fileURL)
            try JITEnableContext.shared.addProfile(profileData)
            
            alertMsg = "Profile added successfully"
            alertTitle = "Success"
            alertSuccess = true
            alert = true
            
            // Reload profiles after adding
            await loadProfiles(force: true)
        } catch {
            alertMsg = error.localizedDescription
            alertTitle = "Failed to Add Profile"
            alertSuccess = false
            alert = true
        }
        working = false
    }
    
}
