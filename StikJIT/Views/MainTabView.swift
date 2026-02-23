//
//  MainTabView.swift
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

import SwiftUI

private struct TabDescriptor: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let builder: () -> AnyView
}

extension Notification.Name {
    static let switchToTab = Notification.Name("MainTabSwitchNotification")
}

struct MainTabView: View {
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage(TabConfiguration.storageKey) private var enabledTabIdentifiers: String = TabConfiguration.defaultRawValue
    @AppStorage("primaryTabSelection") private var selection: String = TabConfiguration.defaultIDs.first ?? "home"
    @AppStorage("powerUser") private var powerUser: Bool = false
    @State private var switchObserver: Any?
    @State private var detachedTab: TabDescriptor?
    @State private var didSetInitialHome = false

    @Environment(\.themeExpansionManager) private var themeExpansion

    private var accentColor: Color {
        themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue
    }
    
    private var preferredScheme: ColorScheme? {
        themeExpansion?.preferredColorScheme(for: appThemeRaw)
    }

    private var configurableTabs: [TabDescriptor] {
        var tabs: [TabDescriptor] = [
            TabDescriptor(id: "home", title: "Home", systemImage: "house") { AnyView(HomeView()) },
            TabDescriptor(id: "console", title: "Console", systemImage: "terminal") { AnyView(ConsoleLogsView()) },
            TabDescriptor(id: "scripts", title: "Scripts", systemImage: "scroll") { AnyView(ScriptListView()) },
            TabDescriptor(id: "deviceinfo", title: "Device Info", systemImage: "iphone.and.arrow.forward") { AnyView(DeviceInfoView()) },
            TabDescriptor(id: "profiles", title: "App Expiry", systemImage: "calendar.badge.clock") { AnyView(ProfileView()) },
            TabDescriptor(id: "processes", title: "Processes", systemImage: "rectangle.stack.person.crop") { AnyView(ProcessInspectorView()) },
            TabDescriptor(id: "location", title: "Location", systemImage: "location") { AnyView(LocationSimulationView()) }
        ]
        return tabs
    }
    
    private var availableTabs: [TabDescriptor] {
        configurableTabs
    }
    
    private let settingsTab = TabDescriptor(id: "settings", title: "Settings", systemImage: "gearshape.fill") {
        AnyView(SettingsView())
    }
    
    private var selectedTabDescriptors: [TabDescriptor] {
        let ids = TabConfiguration.sanitize(raw: enabledTabIdentifiers)
        return ids.compactMap { id in
            availableTabs.first(where: { $0.id == id })
        }
    }
    
    private func ensureSelectionIsValid() {
        let ids = displayTabs.map { $0.id }
        if ids.contains(selection) {
            return
        }
        selection = ids.first ?? settingsTab.id
    }
    
    private var displayTabs: [TabDescriptor] {
        if !powerUser {
            var tabs = ["home", "console", "scripts"].compactMap { id in
                configurableTabs.first(where: { $0.id == id })
            }
            tabs.insert(settingsTab, at: min(3, tabs.count))
            return tabs
        }
        var tabs = selectedTabDescriptors
        if tabs.count >= 3 {
            tabs.insert(settingsTab, at: 3)
        } else {
            tabs.append(settingsTab)
        }
        return tabs
    }
    
    var body: some View {
        ZStack {
            // Allow global themed background to show
            Color.clear.ignoresSafeArea()
            
            // Main tabs
            TabView(selection: $selection) {
                ForEach(displayTabs) { descriptor in
                    descriptor.builder()
                        .tabItem { Label(descriptor.title, systemImage: descriptor.systemImage) }
                        .tag(descriptor.id)
                }
            }
            .id("\((themeExpansion?.hasThemeExpansion == true) ? customAccentColorHex : "default-accent")-\(powerUser)")
            .tint(accentColor)
            .preferredColorScheme(preferredScheme)
            .onAppear {
                enabledTabIdentifiers = TabConfiguration.serialize(TabConfiguration.sanitize(raw: enabledTabIdentifiers))
                ensureSelectionIsValid()
                if !didSetInitialHome {
                    if selectedTabDescriptors.contains(where: { $0.id == "home" }) {
                        selection = "home"
                    } else if let descriptor = availableTabs.first(where: { $0.id == "home" }) {
                        detachedTab = descriptor
                    }
                    didSetInitialHome = true
                }
                switchObserver = NotificationCenter.default.addObserver(forName: .switchToTab, object: nil, queue: .main) { note in
                    guard let id = note.object as? String else { return }
                    if selectedTabDescriptors.contains(where: { $0.id == id }) {
                        selection = id
                    } else if let descriptor = availableTabs.first(where: { $0.id == id }) {
                        detachedTab = descriptor
                    }
                }
            }
            .onDisappear {
                if let observer = switchObserver {
                    NotificationCenter.default.removeObserver(observer)
                    switchObserver = nil
                }
            }
            .onChange(of: enabledTabIdentifiers) { _ in
                ensureSelectionIsValid()
            }
            .onChange(of: powerUser) { _ in
                selection = "settings"
            }
            .sheet(item: $detachedTab) { descriptor in
                NavigationStack {
                    descriptor.builder()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    detachedTab = nil
                                }
                            }
                        }
                }
            }
        }
    }

}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .themeExpansionManager(ThemeExpansionManager(previewUnlocked: true))
    }
}
