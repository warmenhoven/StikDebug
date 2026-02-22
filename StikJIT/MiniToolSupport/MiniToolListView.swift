import SwiftUI
import UniformTypeIdentifiers
import UIKit

class ToolCombo : Hashable, ObservableObject {
    static func == (lhs: ToolCombo, rhs: ToolCombo) -> Bool {
        return lhs === rhs
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    init(tool: MiniToolBundle, info: ToolInfo) {
        self.tool = tool
        self.info = info
    }
    
    init() {
        self.tool = nil
        self.info = nil
    }
    
    @Published var tool: MiniToolBundle?
    @Published var info: ToolInfo?
}

struct MiniToolListView: View {
    @StateObject private var store = MiniToolStore()
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showDeleteConfirmation = false
    @State private var pendingDelete: MiniToolBundle?
    @State private var alertVisible = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showInfoSheet = false
    @State private var navigationToolCombo: ToolCombo?
    @StateObject private var pendingToolCombo: ToolCombo = ToolCombo()
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.themeExpansionManager) private var themeExpansion
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }

    private var filteredTools: [MiniToolBundle] {
        guard !searchText.isEmpty else { return store.tools }
        return store.tools.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredTools.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("No mini tools found", systemImage: "shippingbox")
                                .foregroundStyle(.secondary)
                            Text("Tap Import to add a tool.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        ForEach(filteredTools) { tool in
                            Button {
                                handleRun(tool)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.blue)
                                        .imageScale(.large)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tool.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(tool.url.lastPathComponent)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    NavigationLink(destination: MiniToolEditorView(tool: tool)) {
                                        EmptyView()
                                    }
                                    .frame(width: 0)
                                    .opacity(0)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = tool
                                    showDeleteConfirmation = true
                                } label: { Label("Delete", systemImage: "trash") }

                                NavigationLink(destination: MiniToolEditorView(tool: tool)) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                NavigationLink(destination: MiniToolEditorView(tool: tool)) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button { copy(tool.url.lastPathComponent) } label: {
                                    Label("Copy Name", systemImage: "doc.on.doc")
                                }
                                Button { copy(tool.url.path) } label: {
                                    Label("Copy Path", systemImage: "folder")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    pendingDelete = tool
                                    showDeleteConfirmation = true
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search tools…"
            )
            .navigationTitle("Mini Tools")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: {
                        Label("Import", systemImage: "tray.and.arrow.down")
                    }
                }
            }
            .onAppear { store.refresh() }
            .onChange(of: store.lastError) { _, message in
                guard let message else { return }
                presentError(title: "Mini Tool", message: message)
                store.lastError = nil
            }
            .alert("Delete Mini Tool?", isPresented: $showDeleteConfirmation, presenting: pendingDelete) { tool in
                Button("Delete", role: .destructive) { delete(tool) }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { tool in
                Text("Delete \(tool.name)? This removes its files permanently.")
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType("com.stik.StikJIT.stiktool") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    store.importTool(from: url)
                case .failure(let error):
                    presentError(title: "Import Failed", message: error.localizedDescription)
                }
            }
            .navigationDestination(item: $navigationToolCombo) { combo in
                MiniToolRunnerView(tool: combo.tool!, toolInfo: combo.info!)
            }
        }
        .preferredColorScheme(preferredScheme)
        .overlay {
            if store.isBusy {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView("Working…")
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if alertVisible {
                CustomErrorView(
                    title: alertTitle,
                    message: alertMessage,
                    onDismiss: { alertVisible = false },
                    messageType: .error
                )
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            toolInfoSheet
        }
    }

    // MARK: - Actions

    private func delete(_ tool: MiniToolBundle) {
        store.delete(tool)
        if let error = store.lastError {
            presentError(title: "Delete Failed", message: error)
        }
    }

    private func presentError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertVisible = true
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func handleRun(_ tool: MiniToolBundle) {
        do {
            guard let info = try loadToolInfo(for: tool) else {
                presentError(title: "Mini Tool", message: "toolInfo.json is missing or unreadable for this tool.")
                return
            }
            if try isTrusted(tool) {
                navigationToolCombo = ToolCombo(tool: tool, info: info)
                return
            }
            
            pendingToolCombo.info = info
            pendingToolCombo.tool = tool
            showInfoSheet = true
        } catch {
            presentError(title: "Mini Tool", message: error.localizedDescription)
        }
    }
    
    private func loadToolInfo(for tool: MiniToolBundle) throws -> ToolInfo? {
        let infoURL = tool.url.appendingPathComponent("toolInfo.json")
        guard FileManager.default.fileExists(atPath: infoURL.path) else { return nil }
        let data = try Data(contentsOf: infoURL)
        return try JSONDecoder().decode(ToolInfo.self, from: data)
    }

    private func isTrusted(_ tool: MiniToolBundle) throws -> Bool {
        guard let uuid = UIDevice.current.identifierForVendor?.uuidString else { return false }
        let checkURL = tool.url.appendingPathComponent("check")
        guard FileManager.default.fileExists(atPath: checkURL.path) else { return false }
        let contents = try String(contentsOf: checkURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return contents == uuid
    }

    private func authorizeAndRun() {
        guard let tool = pendingToolCombo.tool else {
            return
        }
        
        do {
            try writeCheck(for: tool)
            navigationToolCombo = pendingToolCombo
        } catch {
            presentError(title: "Mini Tool", message: error.localizedDescription)
        }
        resetPending()
    }

    private func writeCheck(for tool: MiniToolBundle) throws {
        guard let uuid = UIDevice.current.identifierForVendor?.uuidString else {
            throw NSError(domain: "MiniTool", code: -1, userInfo: [NSLocalizedDescriptionKey: "identifierForVendor is unavailable."])
        }
        let checkURL = tool.url.appendingPathComponent("check")
        try uuid.write(to: checkURL, atomically: true, encoding: .utf8)
    }

    private func resetPending() {
        showInfoSheet = false
//        pendingTool = MiniToolBundle()
    }

    @ViewBuilder
    private var toolInfoSheet: some View {
        if let tool = pendingToolCombo.tool, let info = pendingToolCombo.info {
            ToolInfoSheet(tool: tool, info: info) {
                authorizeAndRun()
            } onCancel: {
                resetPending()
            }
        }
    }
}

private struct ToolInfoSheet: View {
    let tool: MiniToolBundle
    let info: ToolInfo
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.name)
                            .font(.title2.weight(.semibold))
                        Text(info.desc)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Author", systemImage: "person")
                            .font(.subheadline.weight(.semibold))
                        Text(info.author)
                            .font(.body)
                    }

                    if let capabilities = info.capabilities {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Capabilities", systemImage: "checkmark.shield")
                                .font(.subheadline.weight(.semibold))
                            CapabilityRow(title: "Internet Access", enabled: capabilities.internetAccess ?? false)
                        }
                    }

                    if let functions = info.requiredIDeviceFunctions, !functions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Required iDevice Functions", systemImage: "bolt.horizontal.circle")
                                .font(.subheadline.weight(.semibold))
                            ForEach(functions, id: \.self) { function in
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(.blue)
                                    Text(function)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Allow Tool?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allow & Run") { onAllow() }
                        .bold()
                }
            }
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(enabled ? .green : .red)
            Text(title)
                .font(.body)
        }
    }
}

