import Foundation

/// Monitors a folder for file changes and triggers data reload
final class FolderMonitor: ObservableObject {
    @Published var isMonitoring = false
    
    private var monitor: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "folder-monitor", qos: .utility)
    
    /// Start monitoring the specified folder for changes
    func startMonitoring(folder: URL, onChange: @escaping () -> Void) {
        stopMonitoring()
        
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            print("❌ Failed to open folder for monitoring: \(folder.path)")
            return
        }
        
        monitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        
        monitor?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                onChange()
            }
        }
        
        monitor?.setCancelHandler {
            close(descriptor)
        }
        
        monitor?.resume()
        isMonitoring = true
        
        print("👁️ Started monitoring folder: \(folder.path)")
    }
    
    /// Stop monitoring the current folder
    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        isMonitoring = false
        print("🛑 Stopped folder monitoring")
    }
    
    deinit {
        stopMonitoring()
    }
}
