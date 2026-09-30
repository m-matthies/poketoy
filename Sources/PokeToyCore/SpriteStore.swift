import Foundation

public enum SpriteStoreError: Error, Equatable, LocalizedError {
    case http(status: Int, path: String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .http(404, _): return "Not found on SpriteCollab."
        case .http(let status, _): return "SpriteCollab answered with HTTP \(status)."
        case .timedOut: return "SpriteCollab took too long to answer."
        }
    }
}

/// Fetches SpriteCollab data and keeps it in a local cache.
public actor SpriteStore {
    public static let defaultRemoteBase = URL(string: "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/")!
    public static let catalogMaxAge: TimeInterval = 7 * 24 * 3600

    private let cacheDirectory: URL
    private let remoteBase: URL
    private let bundledSprites: URL?
    /// Portraits shipped with the app (`<path>/<Emotion>.png`); a species found here is never downloaded.
    private let bundledPortraits: URL?
    private let session: URLSession
    /// After a network failure, portraits come only from the cache for a while.
    private var portraitsOfflineUntil: Date?

    public init(cacheDirectory: URL, remoteBase: URL = SpriteStore.defaultRemoteBase, bundledSprites: URL? = nil,
                bundledPortraits: URL? = nil, session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.remoteBase = remoteBase
        self.bundledSprites = bundledSprites
        self.bundledPortraits = bundledPortraits
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
            // Offline on a first start: the Pokémon bundled with the app (all complete) are the catalog.
            if let bundledSprites, let names = try? Self.bundledNames(in: bundledSprites), !names.isEmpty {
                return names.sorted { $0.key < $1.key }
                    .map { CatalogEntry(path: $0.key, displayName: $0.value, isComplete: true) }
            }
            throw error
        }
    }

    /// The names of the Pokémon bundled with the app (`names.json` beside their sprites).
    public static func bundledNames(in directory: URL) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self,
                                 from: Data(contentsOf: directory.appendingPathComponent("names.json")))
    }

    /// Paths of sprites downloaded so far (not the bundled ones), e.g. for the Pokédex's "seen".
    public func downloadedSpritePaths() -> [String] {
        Self.usablePaths(under: cacheDirectory.appendingPathComponent("sprite"))
    }

    /// A local directory with what `SpriteSet` needs for `path`, downloading missing files.
    /// Offline, an incomplete but usable cached or bundled copy is returned instead.
    public func spriteDirectory(for path: String) async throws -> URL {
        let cached = cacheDirectory.appendingPathComponent("sprite").appendingPathComponent(path, isDirectory: true)
        let bundled = bundledSprites?.appendingPathComponent(path, isDirectory: true)
        if Self.isComplete(cached) { return cached }
        if let bundled, Self.isComplete(bundled) { return bundled }
        do {
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
        } catch {
            if Self.isUsable(cached) { return cached }
            if let bundled, Self.isUsable(bundled) { return bundled }
            throw error
        }
    }

    /// Like `spriteDirectory(for:)`, but gives up after `timeout` seconds.
    public func spriteDirectory(for path: String, timeout: TimeInterval) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.spriteDirectory(for: path) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SpriteStoreError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw SpriteStoreError.timedOut }
            return first
        }
    }

    /// Deletes every downloaded sprite and portrait (bundled sprites and the catalog stay).
    public func clearDownloads() {
        for folder in ["sprite", "portrait"] {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(folder))
        }
        portraitsOfflineUntil = nil
    }

    /// Paths (e.g. `0025/0000/0001`) of every usable cached or bundled sprite directory.
    public func cachedSpritePaths() -> [String] {
        let roots = [cacheDirectory.appendingPathComponent("sprite"), bundledSprites].compactMap { $0 }
        return Array(Set(roots.flatMap(Self.usablePaths(under:)))).sorted()
    }

    private static func usablePaths(under root: URL) -> [String] {
        var paths = Set<String>()
        let rootPath = root.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        for case let url as URL in enumerator where url.lastPathComponent == "AnimData.xml" {
            let directory = url.deletingLastPathComponent()
            guard isUsable(directory) else { continue }
            let path = directory.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath) else { continue }
            let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relative.isEmpty { paths.insert(relative) }
        }
        return paths.sorted()
    }

    /// A local portrait image for `path` showing `emotion`, trying its fallbacks in order (ending with "Normal").
    /// Portraits SpriteCollab doesn't have are remembered so they aren't requested again. Nil if none is available.
    public func portrait(for path: String, emotion: Emotion) async -> URL? {
        await portrait(for: path, names: emotion.portraitNames)
    }

    /// A local portrait image for `path`: the first of `names` SpriteCollab has (e.g. ["Normal"]).
    public func portrait(for path: String, names: [String]) async -> URL? {
        if let bundled = bundledPortraits?.appendingPathComponent(path, isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            return names.lazy.map { bundled.appendingPathComponent("\($0).png") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        let directory = cacheDirectory.appendingPathComponent("portrait").appendingPathComponent(path, isDirectory: true)
        for name in names {
            let file = directory.appendingPathComponent("\(name).png")
            if FileManager.default.fileExists(atPath: file.path) { return file }
            let missing = directory.appendingPathComponent(".missing-\(name)")
            if FileManager.default.fileExists(atPath: missing.path) { continue }
            if let until = portraitsOfflineUntil, Date() < until { continue }  // offline: cache only
            do {
                let data = try await fetch("portrait/\(path)/\(name).png")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                return file
            } catch {
                guard Self.isMissing(error) else {
                    portraitsOfflineUntil = Date().addingTimeInterval(60)  // offline: try again in a minute
                    return nil
                }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: missing.path, contents: nil)
            }
        }
        return nil
    }

    /// True when the error means "that file doesn't exist" rather than "couldn't ask".
    private static func isMissing(_ error: Error) -> Bool {
        if case SpriteStoreError.http(404, _) = error { return true }
        return (error as? URLError)?.code == .fileDoesNotExist
    }

    public static func isComplete(_ directory: URL) -> Bool {
        guard let xml = try? Data(contentsOf: directory.appendingPathComponent("AnimData.xml")),
              let data = try? AnimData(xml: xml) else { return false }
        return SpriteSet.requiredFiles(for: data).allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Has `AnimData.xml` and an `Idle` or `Walk` sheet, so `SpriteSet` can load it using fallbacks.
    public static func isUsable(_ directory: URL) -> Bool {
        guard let xml = try? Data(contentsOf: directory.appendingPathComponent("AnimData.xml")),
              let data = try? AnimData(xml: xml) else { return false }
        return ["Idle", "Walk"].contains { name in
            guard let info = data.anims[name] else { return false }
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(info.sourceName)-Anim.png").path)
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
