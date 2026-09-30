import Foundation

public enum SpriteStoreError: Error, Equatable {
    case http(status: Int, path: String)
}

/// Fetches SpriteCollab data and keeps it in a local cache.
public actor SpriteStore {
    public static let defaultRemoteBase = URL(string: "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/")!
    public static let catalogMaxAge: TimeInterval = 7 * 24 * 3600

    private let cacheDirectory: URL
    private let remoteBase: URL
    private let bundledSprites: URL?
    private let session: URLSession

    public init(cacheDirectory: URL, remoteBase: URL = SpriteStore.defaultRemoteBase, bundledSprites: URL? = nil,
                session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.remoteBase = remoteBase
        self.bundledSprites = bundledSprites
        self.session = session
    }

    /// The Pokémon list. Uses a cached copy younger than `catalogMaxAge` unless `forceRefresh`;
    /// falls back to any cached copy when the network fails.
    public func catalog(forceRefresh: Bool = false) async throws -> [CatalogEntry] {
        let cached = cacheDirectory.appendingPathComponent("tracker.json")
        if !forceRefresh, let age = Self.age(of: cached), age < Self.catalogMaxAge,
           let data = try? Data(contentsOf: cached), let entries = try? Catalog.parse(trackerJSON: data) {
            return entries
        }
        do {
            let data = try await fetch("tracker.json")
            let entries = try Catalog.parse(trackerJSON: data)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cached, options: .atomic)
            return entries
        } catch {
            if let data = try? Data(contentsOf: cached), let entries = try? Catalog.parse(trackerJSON: data) {
                return entries
            }
            throw error
        }
    }

    /// A local directory with everything `SpriteSet` needs for `path`, downloading missing files.
    public func spriteDirectory(for path: String) async throws -> URL {
        let cached = cacheDirectory.appendingPathComponent("sprite").appendingPathComponent(path, isDirectory: true)
        if Self.isComplete(cached) { return cached }
        if let bundled = bundledSprites?.appendingPathComponent(path, isDirectory: true), Self.isComplete(bundled) {
            return bundled
        }

        let xml = try await fetch("sprite/\(path)/AnimData.xml")
        let animData = try AnimData(xml: xml)
        try FileManager.default.createDirectory(at: cached, withIntermediateDirectories: true)
        for file in SpriteSet.requiredFiles(for: animData).sorted() {
            let target = cached.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            try await fetch("sprite/\(path)/\(file)").write(to: target, options: .atomic)
        }
        // Written last: its presence marks the directory as complete.
        try xml.write(to: cached.appendingPathComponent("AnimData.xml"), options: .atomic)
        return cached
    }

    public static func isComplete(_ directory: URL) -> Bool {
        guard let xml = try? Data(contentsOf: directory.appendingPathComponent("AnimData.xml")),
              let data = try? AnimData(xml: xml) else { return false }
        return SpriteSet.requiredFiles(for: data).allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    private func fetch(_ relativePath: String) async throws -> Data {
        let (data, response) = try await session.data(from: remoteBase.appendingPathComponent(relativePath))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SpriteStoreError.http(status: http.statusCode, path: relativePath)
        }
        return data
    }

    private static func age(of url: URL) -> TimeInterval? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(modified)
    }
}
