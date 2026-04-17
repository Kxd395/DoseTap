import Foundation

enum FixtureLoader {
    static func folder(named name: String) throws -> URL {
        guard let resourcesURL = Bundle.module.resourceURL else {
            throw NSError(domain: "FixtureLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture resources are unavailable"])
        }

        let folderURL = resourcesURL
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)

        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            throw NSError(domain: "FixtureLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fixture folder not found: \(name)"])
        }

        return folderURL
    }
}
