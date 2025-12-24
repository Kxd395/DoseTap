import SwiftUI

/// Main content view that shows the dashboard when data is loaded
struct ContentView: View {
    @StateObject private var dataStore = DataStore()
    @StateObject private var folderMonitor = FolderMonitor()
    @State private var showingFolderPicker = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(dataStore: dataStore)
        } detail: {
            // Main content
            if dataStore.folderURL != nil {
                DashboardView(dataStore: dataStore)
            } else {
                WelcomeView(showingFolderPicker: $showingFolderPicker)
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Gain access to security-scoped resource
                    _ = url.startAccessingSecurityScopedResource()
                    
                    Task { @MainActor in
                        await dataStore.loadAll(from: url)
                        startMonitoring(url: url)
                    }
                }
            case .failure(let error):
                print("❌ Folder selection error: \(error)")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if dataStore.folderURL != nil {
                    Button("Refresh") {
                        Task { @MainActor in
                            await dataStore.refresh()
                        }
                    }
                    .disabled(dataStore.importStatus == .importing)
                }
                
                Button("Choose Folder") {
                    showingFolderPicker = true
                }
            }
        }
    }
    
    private func startMonitoring(url: URL) {
        folderMonitor.startMonitoring(folder: url) {
            Task { @MainActor in
                // Debounce file system events
                try? await Task.sleep(for: .seconds(1))
                await dataStore.refresh()
            }
        }
    }
}

#Preview {
    ContentView()
}
