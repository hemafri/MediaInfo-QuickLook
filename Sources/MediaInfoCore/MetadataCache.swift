import Foundation

public struct CacheTicket: Sendable {
    fileprivate let path: String
    fileprivate let size: Int64
    fileprivate let modified: Date
    fileprivate let epoch: UUID
}

public actor MetadataCache {
    private var epoch = UUID()
    private struct Entry: Codable {
        let size: Int64
        let modified: Date
        let metadata: MediaMetadata
    }
    private var entries: [String: Entry]
    private let storage: URL
    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        storage = support.appendingPathComponent("MediaInfoQuickLook/metadata-cache-v3.json")
        entries = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: storage))) ?? [:]
    }
    private func fingerprint(_ url: URL) -> (Int64, Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attributes[.size] as? NSNumber, let date = attributes[.modificationDate] as? Date, attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (size.int64Value, date)
    }
    public func value(for url: URL) -> MediaMetadata? {
        let key = url.standardizedFileURL.path
        guard let entry = entries[key] else { return nil }
        guard let (size, date) = fingerprint(url), size == entry.size, date == entry.modified else { entries.removeValue(forKey: key); persist(); return nil }
        return entry.metadata
    }
    public func begin(for url: URL) -> CacheTicket? {
        guard let (size, date) = fingerprint(url) else { return nil }
        return CacheTicket(path: url.standardizedFileURL.path, size: size, modified: date, epoch: epoch)
    }
    public func store(_ metadata: MediaMetadata, for url: URL, ticket: CacheTicket?) {
        guard let ticket, ticket.epoch == epoch, ticket.path == url.standardizedFileURL.path,
              let (size, date) = fingerprint(url), size == ticket.size, date == ticket.modified else { return }
        entries[ticket.path] = Entry(size: size, modified: date, metadata: metadata)
        persist()
    }
    /// For synchronous metadata creation. Asynchronous probes must use a ticket captured before analysis.
    public func store(_ metadata: MediaMetadata, for url: URL) {
        store(metadata, for: url, ticket: begin(for: url))
    }
    public func clear() { epoch = UUID(); entries.removeAll(); persist() }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: storage, options: .atomic)
        } catch { NSLog("Metadata cache write failed: %@", error.localizedDescription) }
    }
}
